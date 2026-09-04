@testable import AppBundle
import Common
import XCTest

@MainActor
final class ScratchpadCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseAndValidateSlots() {
        testParseSingleCommandSucc(
            "scratchpad assign 4",
            ScratchpadCmdArgs(rawArgs: [])
                .copy(\.action, .initialized(.assign))
                .copy(\.slot, .initialized(4)),
        )
        assertEquals(parseCommand("scratchpad toggle 0").errorOrNil, "ERROR: Scratchpad slot must be between 1 and 10")
        assertEquals(parseCommand("scratchpad --window-id 9 toggle 1").errorOrNil, "--window-id can only be used with 'scratchpad assign'")
    }

    func testAssignsMultipleWindowsAndTogglesThemTogether() async {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        let firstResult = await parseCommand("scratchpad --window-id 1 assign 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let secondResult = await parseCommand("scratchpad --window-id 2 assign 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(firstResult.exitCode.rawValue, 0)
        assertEquals(secondResult.exitCode.rawValue, 0)
        assertEquals(first.scratchpadSlot, 2)
        assertEquals(second.scratchpadSlot, 2)
        assertTrue(first.isFloating)
        assertTrue(second.isFloating)
        assertEquals(first.nodeWorkspace?.name, "_smooth-scratchpad-2")

        let shown = await parseCommand("scratchpad toggle 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(shown.exitCode.rawValue, 0)
        assertEquals(workspace.floatingWindows.map(\.windowId).sorted(), [1, 2])

        let hidden = await parseCommand("scratchpad toggle 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(hidden.exitCode.rawValue, 0)
        assertEquals(first.nodeWorkspace?.name, "_smooth-scratchpad-2")
        assertEquals(second.nodeWorkspace?.name, "_smooth-scratchpad-2")
    }

    func testToggleEmptySlotReportsHowToAssign() async {
        let result = await parseCommand("scratchpad toggle 7").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertTrue(result.stderr.first?.contains("scratchpad assign 7") == true)
    }

    func testRemovingHiddenWindowReturnsItToCurrentWorkspace() async {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 11, parent: workspace.rootTilingContainer)
        _ = await parseCommand("scratchpad --window-id 11 assign 3").cmdOrDie.run(.defaultEnv, .emptyStdin)

        ScratchpadManager.shared.remove(windowId: 11, from: 3)

        XCTAssertNil(window.scratchpadSlot)
        assertEquals(window.nodeWorkspace, workspace)
        assertTrue(window.isFloating)
        assertTrue(ScratchpadManager.shared.items(in: 3).isEmpty)
    }

    func testCaptureCanBeArmedAndCancelled() {
        ScratchpadManager.shared.beginCapture(for: 6)
        assertEquals(ScratchpadManager.shared.armedSlot, 6)

        ScratchpadManager.shared.cancelCapture()

        XCTAssertNil(ScratchpadManager.shared.armedSlot)
    }
}
