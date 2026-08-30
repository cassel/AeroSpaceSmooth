@testable import AppBundle
import XCTest

@MainActor
final class SmoothWorkspaceLayoutTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testDwindleSequencesFromOneThroughTenWindows() {
        for count in 1 ... 10 {
            setUpWorkspacesForTests()
            enableStyle(.dwindle)

            let root = Workspace.get(byName: name).rootTilingContainer
            let windows = (1 ... count).map { TestWindow.new(id: UInt32($0), parent: root) }

            reconcileSmoothWorkspaceLayouts()

            assertEquals(root.layoutDescription, expectedDwindle(Array(1 ... UInt32(count)), orientationIsHorizontal: true))
            assertEquals(windows[0].isFullscreen, count == 1)
            assertTrue(windows.dropFirst().allSatisfy { !$0.isFullscreen })
        }
    }

    func testVerticalPairSequencesFromOneThroughTenWindows() {
        for count in 1 ... 10 {
            setUpWorkspacesForTests()
            enableStyle(.verticalPairs)

            let root = Workspace.get(byName: name).rootTilingContainer
            let windows = (1 ... count).map { TestWindow.new(id: UInt32($0), parent: root) }

            reconcileSmoothWorkspaceLayouts()

            assertEquals(
                root.layoutDescription,
                count == 1
                    ? .h_tiles([.window(1)])
                    : expectedVerticalPairs(Array(1 ... UInt32(count))),
            )
            assertEquals(windows[0].isFullscreen, count == 1)
        }
    }

    func testNewWindowIsAppendedToDwindleTail() {
        enableStyle(.dwindle)
        let root = Workspace.get(byName: name).rootTilingContainer
        let windows = (1 ... 4).map { TestWindow.new(id: UInt32($0), parent: root) }
        reconcileSmoothWorkspaceLayouts()

        let newWindow = TestWindow.new(id: 5, parent: root)
        newWindow.bind(
            to: windows[1].parent.orDie(),
            adaptiveWeight: WEIGHT_AUTO,
            index: windows[1].ownIndex.orDie() + 1,
        )
        reconcileSmoothWorkspaceLayouts()

        assertEquals(
            root.layoutDescription,
            expectedDwindle([1, 2, 3, 4, 5], orientationIsHorizontal: true),
        )
    }

    func testClosingWindowRebuildsDwindleWithSurvivingOrder() {
        enableStyle(.dwindle)
        let root = Workspace.get(byName: name).rootTilingContainer
        let windows = (1 ... 5).map { TestWindow.new(id: UInt32($0), parent: root) }
        reconcileSmoothWorkspaceLayouts()

        windows[1].unbindFromParent()
        reconcileSmoothWorkspaceLayouts()

        assertEquals(
            root.layoutDescription,
            expectedDwindle([1, 3, 4, 5], orientationIsHorizontal: true),
        )
    }

    func testSameMembershipDoesNotRebuildAfterManualTreeChange() {
        enableStyle(.dwindle)
        let root = Workspace.get(byName: name).rootTilingContainer
        let windows = (1 ... 4).map { TestWindow.new(id: UInt32($0), parent: root) }
        reconcileSmoothWorkspaceLayouts()
        let originalTail = root.children[1]

        windows[0].bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        reconcileSmoothWorkspaceLayouts()

        assertTrue(root.children.contains { $0 === originalTail })
    }

    func testMonitorLimitMovesOverflowToAnotherWorkspaceOnSameMonitor() {
        SmoothLayoutSettingsStore.shared.replaceProfilesForTests([
            "Test Monitor": SmoothMonitorLayoutProfile(
                monitorName: "Test Monitor",
                enabled: true,
                tileLimit: 3,
                styles: Array(repeating: .dwindle, count: SmoothMonitorLayoutProfile.configuredWindowCount),
            ),
        ])
        let source = Workspace.get(byName: name)
        let destination = Workspace.get(byName: "secondary")
        _ = destination.rootTilingContainer
        (1 ... 5).forEach { TestWindow.new(id: UInt32($0), parent: source.rootTilingContainer) }

        reconcileSmoothWorkspaceLayouts()

        assertEquals(source.rootTilingContainer.allLeafWindowsRecursive.count, 3)
        assertEquals(destination.rootTilingContainer.allLeafWindowsRecursive.count, 2)
    }

    func testPreviewProducesOneFramePerWindowForEveryStyleAndCount() {
        for style in SmoothLayoutStyle.allCases {
            for count in 1 ... 10 {
                let frames = SmoothLayoutPreviewGeometry.frames(
                    style: style,
                    count: count,
                    monitorIsHorizontal: true,
                )
                assertEquals(frames.count, style == .fullscreen && count == 1 ? 1 : count)
                assertTrue(frames.allSatisfy {
                    $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= 1 && $0.maxY <= 1 && $0.width > 0 && $0.height > 0
                })
            }
        }
    }

    private func enableStyle(_ style: SmoothLayoutStyle) {
        SmoothLayoutSettingsStore.shared.replaceProfilesForTests([
            "Test Monitor": SmoothMonitorLayoutProfile(
                monitorName: "Test Monitor",
                enabled: true,
                tileLimit: 10,
                styles: Array(repeating: style, count: SmoothMonitorLayoutProfile.configuredWindowCount),
            ),
        ])
    }

    private func expectedDwindle(_ ids: [UInt32], orientationIsHorizontal: Bool) -> LayoutDescription {
        let children: [LayoutDescription] = if ids.count <= 2 {
            ids.map(LayoutDescription.window)
        } else {
            [
                .window(ids[0]),
                expectedDwindle(Array(ids.dropFirst()), orientationIsHorizontal: !orientationIsHorizontal),
            ]
        }
        return orientationIsHorizontal ? .h_tiles(children) : .v_tiles(children)
    }

    private func expectedVerticalPairs(_ ids: [UInt32]) -> LayoutDescription {
        var children: [LayoutDescription] = []
        var index = 0
        while index < ids.count {
            let end = min(index + 2, ids.count)
            let row = ids[index ..< end].map(LayoutDescription.window)
            children.append(row.count == 1 ? row[0] : .h_tiles(row))
            index = end
        }
        return .v_tiles(children)
    }
}
