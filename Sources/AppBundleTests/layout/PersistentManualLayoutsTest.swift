@testable import AppBundle
import XCTest

@MainActor
final class PersistentManualLayoutsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testCaptureAndRestoreNestedTreeOrderAndWeights() async throws {
        let suiteName = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PersistentManualLayoutStore(defaults: defaults)
        let root = Workspace.get(byName: name).rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root, adaptiveWeight: 3)
        let nested = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1)
        let second = TestWindow.new(id: 2, parent: nested, adaptiveWeight: 2)
        let third = TestWindow.new(id: 3, parent: nested, adaptiveWeight: 1)

        await store.capture()

        third.bind(to: root, adaptiveWeight: 7, index: 0)
        first.bind(to: root, adaptiveWeight: 7, index: INDEX_BIND_LAST)
        second.bind(to: root, adaptiveWeight: 7, index: INDEX_BIND_LAST)
        nested.unbindFromParent()
        root.changeOrientation(.v)
        root.layout = .accordion

        await store.restore()

        assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))
        assertEquals(first.getWeight(.h), 3)
        let restoredNested = try XCTUnwrap(root.children.getOrNil(atIndex: 1) as? TilingContainer)
        assertEquals(restoredNested.getWeight(.h), 1)
        assertEquals(second.getWeight(.v), 2)
        assertEquals(third.getWeight(.v), 1)
    }

    func testAutomaticWorkspaceIsNotCaptured() async throws {
        let suiteName = "PersistentManualLayoutsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SmoothLayoutSettingsStore.shared.replaceProfilesForTests([
            "Test Monitor": SmoothMonitorLayoutProfile(
                monitorName: "Test Monitor",
                enabled: true,
                tileLimit: 10,
                styles: Array(repeating: .dwindle, count: SmoothMonitorLayoutProfile.configuredWindowCount),
            ),
        ])
        let store = PersistentManualLayoutStore(defaults: defaults)
        TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)

        await store.capture()

        assertTrue(store.layouts.isEmpty)
    }
}
