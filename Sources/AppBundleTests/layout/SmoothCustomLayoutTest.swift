@testable import AppBundle
import XCTest

@MainActor
final class SmoothCustomLayoutTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testEveryPresetProducesAValidBlueprintFromOneThroughTenWindows() throws {
        for style in SmoothLayoutStyle.allCases {
            for count in 1 ... SmoothMonitorLayoutProfile.configuredWindowCount {
                let layout = SmoothCustomLayoutBlueprint.preset(
                    style: style,
                    windowCount: count,
                    monitorIsHorizontal: true,
                )
                try layout.validate()
                assertEquals(layout.frames.count, count)
            }
        }
    }

    func testHybridDwindleStartingAtThirdWindow() throws {
        let layout = SmoothCustomLayoutBlueprint.hybridDwindle(
            windowCount: 4,
            startsAt: 3,
            primaryAxis: .horizontal,
        )
        try layout.validate()

        assertRect(layout.frames[0], x: 0, y: 0, width: 0.5, height: 1)
        assertRect(layout.frames[1], x: 0.5, y: 0, width: 0.5, height: 0.5)
        assertRect(layout.frames[2], x: 0.5, y: 0.5, width: 0.25, height: 0.5)
        assertRect(layout.frames[3], x: 0.75, y: 0.5, width: 0.25, height: 0.5)
    }

    func testHybridDwindleStartingAtFourthWindow() throws {
        let layout = SmoothCustomLayoutBlueprint.hybridDwindle(
            windowCount: 5,
            startsAt: 4,
            primaryAxis: .horizontal,
        )
        try layout.validate()

        assertRect(layout.frames[0], x: 0, y: 0, width: 1.0 / 3.0, height: 1)
        assertRect(layout.frames[1], x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
        assertRect(layout.frames[2], x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 0.5)
        assertRect(layout.frames[3], x: 2.0 / 3.0, y: 0.5, width: 1.0 / 6.0, height: 0.5)
        assertRect(layout.frames[4], x: 5.0 / 6.0, y: 0.5, width: 1.0 / 6.0, height: 0.5)
    }

    func testContinueFromPreviousCountSplitsSelectedTile() throws {
        let previous = SmoothCustomLayoutBlueprint.preset(
            style: .columns,
            windowCount: 2,
            monitorIsHorizontal: true,
        )
        let layout = try XCTUnwrap(SmoothCustomLayoutBlueprint.continuing(
            previous,
            splitSlot: 1,
            axis: .vertical,
        ))

        try layout.validate()
        assertRect(layout.frames[0], x: 0, y: 0, width: 0.5, height: 1)
        assertRect(layout.frames[1], x: 0.5, y: 0, width: 0.5, height: 0.5)
        assertRect(layout.frames[2], x: 0.5, y: 0.5, width: 0.5, height: 0.5)
    }

    func testSplitDescriptorsExposeResizableDividersAndRegions() throws {
        let layout = SmoothCustomLayoutBlueprint.preset(
            style: .dwindle,
            windowCount: 3,
            monitorIsHorizontal: true,
        )

        let root = try XCTUnwrap(layout.splits.first { $0.path.isEmpty })
        let tail = try XCTUnwrap(layout.splits.first { $0.path == [.second] })
        assertEquals(root.axis, .horizontal)
        assertRect(root.region, x: 0, y: 0, width: 1, height: 1)
        assertEquals(tail.axis, .vertical)
        assertRect(tail.region, x: 0.5, y: 0, width: 0.5, height: 1)
    }

    func testDirectDividerResizeUpdatesOnlyTheSelectedSplit() throws {
        var layout = SmoothCustomLayoutBlueprint.preset(
            style: .dwindle,
            windowCount: 3,
            monitorIsHorizontal: true,
        )

        layout.setSplitRatio(0.65, at: [])
        layout.setSplitRatio(0.7, at: [.second])

        try layout.validate()
        assertRect(layout.frames[0], x: 0, y: 0, width: 0.65, height: 1)
        assertRect(layout.frames[1], x: 0.65, y: 0, width: 0.35, height: 0.7)
        assertRect(layout.frames[2], x: 0.65, y: 0.7, width: 0.35, height: 0.3)
    }

    func testDirectDividerResizeClampsToSupportedRange() throws {
        var layout = SmoothCustomLayoutBlueprint.preset(
            style: .columns,
            windowCount: 2,
            monitorIsHorizontal: true,
        )

        layout.setSplitRatio(0.01, at: [])
        try layout.validate()
        assertRect(layout.frames[0], x: 0, y: 0, width: 0.10, height: 1)

        layout.setSplitRatio(0.99, at: [])
        try layout.validate()
        assertRect(layout.frames[0], x: 0, y: 0, width: 0.90, height: 1)
    }

    func testBlueprintRoundTripsThroughJSON() throws {
        var original = SmoothCustomLayoutBlueprint.hybridDwindle(
            windowCount: 6,
            startsAt: 4,
            primaryAxis: .horizontal,
        )
        original.setParentRatio(0.65, of: 0)
        original.swapSlots(1, 4)

        let decoded = try JSONDecoder().decode(
            SmoothCustomLayoutBlueprint.self,
            from: JSONEncoder().encode(original),
        )
        assertEquals(decoded, original)
        try decoded.validate()
    }

    func testValidationRejectsInvalidRatioAndSlots() {
        let invalidRatio = SmoothCustomLayoutBlueprint(
            windowCount: 2,
            root: .split(
                axis: .horizontal,
                ratio: 0.95,
                first: .window(slot: 0),
                second: .window(slot: 1),
            ),
        )
        XCTAssertThrowsError(try invalidRatio.validate())

        let duplicateSlot = SmoothCustomLayoutBlueprint(
            windowCount: 2,
            root: .split(
                axis: .horizontal,
                ratio: 0.5,
                first: .window(slot: 0),
                second: .window(slot: 0),
            ),
        )
        XCTAssertThrowsError(try duplicateSlot.validate())
    }

    func testLegacyMonitorProfileDecodesWithoutCustomLayouts() throws {
        let data = Data("""
            {
              "monitorName": "Legacy Monitor",
              "enabled": true,
              "tileLimit": 6,
              "styles": ["fullscreen", "columns"]
            }
            """.utf8)
        let profile = try JSONDecoder().decode(SmoothMonitorLayoutProfile.self, from: data).normalized

        assertTrue(profile.customLayouts.isEmpty)
        assertEquals(profile.style(for: 1), .fullscreen)
        assertEquals(profile.style(for: 2), .columns)
    }

    func testStoreRepairsBlueprintSavedWithInactivePresetOnce() throws {
        let suiteName = "SmoothCustomLayoutTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = SmoothCustomLayoutBlueprint.hybridDwindle(
            windowCount: 4,
            startsAt: 3,
            primaryAxis: .horizontal,
        )
        let profile = SmoothMonitorLayoutProfile(
            monitorName: "LG Ultra HD",
            enabled: true,
            tileLimit: 8,
            styles: Array(repeating: .dwindle, count: SmoothMonitorLayoutProfile.configuredWindowCount),
            customLayouts: ["4": custom],
        )
        defaults.set(
            try JSONEncoder().encode(["LG Ultra HD": profile]),
            forKey: "AeroSpaceSmooth.monitor-layout-profiles.v1",
        )

        let repaired = SmoothLayoutSettingsStore(defaults: defaults)
        assertEquals(repaired.profile(named: "LG Ultra HD", isHorizontal: true).style(for: 4), .manual)

        var explicitlyChangedProfile = repaired.profile(named: "LG Ultra HD", isHorizontal: true)
        explicitlyChangedProfile.styles[3] = .grid
        defaults.set(
            try JSONEncoder().encode(["LG Ultra HD": explicitlyChangedProfile]),
            forKey: "AeroSpaceSmooth.monitor-layout-profiles.v2",
        )
        let reopened = SmoothLayoutSettingsStore(defaults: defaults)
        assertEquals(reopened.profile(named: "LG Ultra HD", isHorizontal: true).style(for: 4), .grid)
    }

    func testLegacyMonitorProfileMigratesToStableIdentifierAndSurvivesRename() throws {
        let suiteName = "SmoothMonitorIdentifierTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = SmoothMonitorLayoutProfile(
            monitorName: "Old Display Name",
            enabled: false,
            tileLimit: 4,
            styles: Array(repeating: .grid, count: SmoothMonitorLayoutProfile.configuredWindowCount),
        )
        defaults.set(
            try JSONEncoder().encode(["Old Display Name": legacy]),
            forKey: "AeroSpaceSmooth.monitor-layout-profiles.v1",
        )

        let store = SmoothLayoutSettingsStore(defaults: defaults)
        let migrated = store.profile(identifier: "display-uuid", named: "Old Display Name", isHorizontal: true)
        assertEquals(migrated.monitorIdentifier, "display-uuid")
        assertEquals(migrated.tileLimit, 4)
        assertFalse(migrated.enabled)

        let renamed = store.profile(identifier: "display-uuid", named: "Localized Display Name", isHorizontal: true)
        assertEquals(renamed.monitorName, "Localized Display Name")
        assertEquals(renamed.tileLimit, 4)
        assertEquals(store.profiles.count, 1)
    }

    func testRuntimeAppliesHybridCustomTreeAndDoesNotRebuildItRepeatedly() {
        let custom = SmoothCustomLayoutBlueprint.hybridDwindle(
            windowCount: 4,
            startsAt: 3,
            primaryAxis: .horizontal,
        )
        SmoothLayoutSettingsStore.shared.replaceProfilesForTests([
            "Test Monitor": SmoothMonitorLayoutProfile(
                monitorName: "Test Monitor",
                enabled: true,
                tileLimit: 10,
                styles: Array(repeating: .manual, count: SmoothMonitorLayoutProfile.configuredWindowCount),
                customLayouts: ["4": custom],
            ),
        ])
        let root = Workspace.get(byName: name).rootTilingContainer
        (1 ... 4).forEach { TestWindow.new(id: UInt32($0), parent: root) }

        reconcileSmoothWorkspaceLayouts()
        let primary = root.children[0]
        let tail = root.children[1]
        assertEquals(root.layoutDescription, .h_tiles([
            .window(1),
            .v_tiles([.window(2), .h_tiles([.window(3), .window(4)])]),
        ]))

        reconcileSmoothWorkspaceLayouts()
        assertTrue(root.children[0] === primary)
        assertTrue(root.children[1] === tail)
    }

    private func assertRect(
        _ rect: CGRect?,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        guard let rect else {
            XCTFail("Missing frame", file: file, line: line)
            return
        }
        XCTAssertEqual(rect.minX, x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rect.minY, y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rect.width, width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rect.height, height, accuracy: 0.0001, file: file, line: line)
    }
}
