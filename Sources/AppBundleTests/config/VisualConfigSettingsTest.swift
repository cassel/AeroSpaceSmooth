@testable import AppBundle
import XCTest

@MainActor
final class VisualConfigSettingsTest: XCTestCase {
    private let fixture = """
        # Keep this comment.
        config-version = 2
        start-at-login = false
        auto-reload-config = true
        exec.inherit-env-vars = true
        exec.env-vars.PATH = '/opt/homebrew/bin:${PATH}'
        after-login-command = []
        after-startup-command = [
            # Keep the command comment until this field is edited.
            'exec-and-forget borders active_color=0xff00ff99',
        ]
        enable-normalization-flatten-containers = false
        enable-normalization-opposite-orientation-for-nested-containers = false
        default-root-container-layout = 'tiles'
        default-root-container-orientation = 'auto'
        accordion-padding = 30
        persistent-workspaces = ['1', '2', '3']
        on-focused-monitor-changed = ['move-mouse monitor-lazy-center']
        on-focus-changed = []
        on-window-detected = [
            {
                if = 'test %{app-bundle-id} = com.google.Chrome',
                run = 'move-node-to-workspace 3',
            },
        ]

        # Keep the workspace comment.
        [workspace-to-monitor-force-assignment]
        1 = ['Built-in Retina Display', 'main']
        3 = ['LG Ultra HD', 'main']

        [gaps]
        inner.horizontal = 8
        inner.vertical = 8
        outer.left = 8
        outer.bottom = 8
        outer.top = 8
        outer.right = 8

        # Keep the shortcut comments.
        [mode.main.binding]
        alt-f = 'fullscreen'
        alt-1 = ['focus-monitor -- "Built-in Retina Display"', 'workspace 1']

        [mode.service.binding]
        esc = ['reload-config', 'mode main']
        """

    func testNoopPatchPreservesDocumentExactly() throws {
        let draft = try VisualConfigCodec.decode(fixture)
        assertEquals(VisualConfigCodec.patch(fixture, from: draft, to: draft), fixture)
    }

    func testScalarAndTableEditsPreserveCommentsAndProduceValidConfig() throws {
        let original = try VisualConfigCodec.decode(fixture)
        var draft = original
        draft.accordionPadding = 42
        draft.layoutAnimationDurationMs = 240
        draft.gaps.innerHorizontal = 12
        draft.mainBindings[0].commands = ["fullscreen --no-outer-gaps"]

        let patched = VisualConfigCodec.patch(fixture, from: original, to: draft)
        XCTAssertTrue(patched.contains("# Keep this comment."))
        XCTAssertTrue(patched.contains("# Keep the workspace comment."))
        XCTAssertTrue(patched.contains("# Keep the shortcut comments."))
        XCTAssertTrue(patched.contains("accordion-padding = 42"))
        XCTAssertTrue(patched.contains("layout-animation-duration-ms = 240\n\n# Keep the workspace comment."))
        XCTAssertTrue(patched.contains("inner.horizontal = 12"))
        XCTAssertTrue(
            parseConfig(patched).errors.isEmpty,
            parseConfig(patched).errors.map { $0.description(.error) }.joined(separator: "\n") + "\n" + patched,
        )

        let decoded = try VisualConfigCodec.decode(patched)
        assertEquals(decoded.accordionPadding, 42)
        assertEquals(decoded.gaps.innerHorizontal, 12)
    }

    func testEditsListsRulesAssignmentsAndEnvironment() throws {
        let original = try VisualConfigCodec.decode(fixture)
        var draft = original
        draft.environmentVariables.append(VisualConfigPair(key: "EDITOR", value: "vim"))
        draft.afterStartupCommands.append("exec-and-forget open -a Finder")
        draft.windowRules.append(VisualWindowRule(
            condition: "test %{app-bundle-id} = com.hnc.Discord",
            commands: ["move-node-to-workspace 3"],
        ))
        draft.workspaceAssignments.append(VisualWorkspaceAssignment(workspace: "4", monitors: ["LG Ultra HD", "main"]))
        draft.serviceBindings.append(VisualHotkeyBinding(shortcut: "r", commands: ["flatten-workspace-tree", "mode main"]))

        let patched = VisualConfigCodec.patch(fixture, from: original, to: draft)
        XCTAssertTrue(
            parseConfig(patched).errors.isEmpty,
            parseConfig(patched).errors.map { $0.description(.error) }.joined(separator: "\n") + "\n" + patched,
        )
        let decoded = try VisualConfigCodec.decode(patched)
        XCTAssertEqual(decoded.environmentVariables.map(\.key).toSet(), ["PATH", "EDITOR"].toSet())
        XCTAssertEqual(decoded.windowRules.count, 2)
        XCTAssertEqual(decoded.workspaceAssignments.map(\.workspace).toSet(), ["1", "3", "4"].toSet())
        XCTAssertEqual(decoded.serviceBindings.count, 2)
    }

    func testApplicationLayoutRuleRoundTripsThroughStandardConfig() throws {
        let original = try VisualConfigCodec.decode(fixture)
        var draft = original
        draft.windowRules.insert(
            VisualWindowRule(applicationBundleIdentifier: "com.dmitrynikolaev.numi", layout: .floating),
            at: 0,
        )

        let patched = VisualConfigCodec.patch(fixture, from: original, to: draft)
        XCTAssertTrue(
            parseConfig(patched).errors.isEmpty,
            parseConfig(patched).errors.map { $0.description(.error) }.joined(separator: "\n") + "\n" + patched,
        )
        XCTAssertTrue(patched.contains("check-further-callbacks = true"))

        let decoded = try VisualConfigCodec.decode(patched)
        assertEquals(
            decoded.windowRules.first?.visualApplicationRule,
            VisualApplicationRule(
                bundleIdentifier: "com.dmitrynikolaev.numi",
                titleContains: "",
                layout: .floating,
                workspace: "",
            ),
        )
        XCTAssertEqual(decoded.windowRules.first?.checkFurtherCallbacks, true)
    }

    func testOnlySupportedApplicationRulesAppearInVisualEditor() {
        XCTAssertEqual(
            VisualWindowRule(
                condition: "test %{app-bundle-id} = com.hnc.Discord",
                commands: ["layout tiling"],
            ).visualApplicationRule,
            VisualApplicationRule(
                bundleIdentifier: "com.hnc.Discord",
                titleContains: "",
                layout: .tiling,
                workspace: "",
            ),
        )
        XCTAssertNil(VisualWindowRule(
            condition: "test %{app-bundle-id} = com.hnc.Discord || test %{window-title} = Settings",
            commands: ["layout floating"],
        ).visualApplicationRule)
        XCTAssertNil(VisualWindowRule(
            condition: "test %{app-bundle-id} = com.hnc.Discord",
            commands: ["exec-and-forget open -a Finder"],
        ).visualApplicationRule)
    }

    func testVisualApplicationRuleSupportsTitleWorkspaceAndOrderedActions() throws {
        let original = try VisualConfigCodec.decode(fixture)
        var draft = original
        let visualRule = VisualApplicationRule(
            bundleIdentifier: "com.apple.Terminal",
            titleContains: "Bob's [scratch] terminal",
            layout: .floating,
            workspace: "utilities",
            scratchpadSlot: 4,
        )
        draft.windowRules.insert(VisualWindowRule(applicationRule: visualRule), at: 0)

        let patched = VisualConfigCodec.patch(fixture, from: original, to: draft)
        XCTAssertTrue(
            parseConfig(patched).errors.isEmpty,
            parseConfig(patched).errors.map { $0.description(.error) }.joined(separator: "\n") + "\n" + patched,
        )
        let decoded = try VisualConfigCodec.decode(patched)
        assertEquals(decoded.windowRules.first?.visualApplicationRule, visualRule)
        assertEquals(decoded.windowRules.first?.commands, [
            "layout floating",
            "move-node-to-workspace -- 'utilities'",
            "scratchpad assign 4",
        ])
    }
}
