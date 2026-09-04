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
        assertFalse(first.scratchpadIsPresented)
        assertFalse(second.scratchpadIsPresented)
        assertEquals(first.nodeWorkspace?.name, "_smooth-scratchpad-2")

        let shown = await parseCommand("scratchpad toggle 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(shown.exitCode.rawValue, 0)
        assertEquals(workspace.floatingWindows.map(\.windowId).sorted(), [1, 2])
        assertTrue(first.scratchpadIsPresented)
        assertTrue(second.scratchpadIsPresented)

        let hidden = await parseCommand("scratchpad toggle 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(hidden.exitCode.rawValue, 0)
        assertFalse(first.scratchpadIsPresented)
        assertFalse(second.scratchpadIsPresented)
        assertEquals(first.nodeWorkspace?.name, "_smooth-scratchpad-2")
        assertEquals(second.nodeWorkspace?.name, "_smooth-scratchpad-2")
    }

    func testToggleEmptySlotReportsHowToAssign() async {
        let result = await parseCommand("scratchpad toggle 7").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertTrue(result.stderr.first?.contains("scratchpad assign 7") == true)
    }

    func testAssigningFocusedWindowPreservesUserWorkspace() async {
        let workspace = focus.workspace
        let captured = TestWindow.new(id: 8, parent: workspace.rootTilingContainer)
        let remaining = TestWindow.new(id: 9, parent: workspace.rootTilingContainer)
        assertTrue(captured.focusWindow())

        let result = await parseCommand("scratchpad assign 1").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(captured.nodeWorkspace?.name, "_smooth-scratchpad-1")
        assertEquals(focus.workspace, workspace)
        assertEquals(mainMonitorInfo.activeWorkspace, workspace)
        assertEquals(focus.windowOrNil, remaining)
        assertFalse(Workspace.get(byName: "_smooth-scratchpad-1").isVisible)
    }

    func testScratchpadWorkspaceIsNeverSelectedAsMonitorStub() {
        let scratchpad = Workspace.get(byName: "_smooth-scratchpad-4")
        TestWindow.new(id: 10, parent: scratchpad.floatingWindowsContainer)

        let stub = getStubWorkspace(for: mainMonitorInfo)

        assertTrue(stub.isUserFacing)
    }

    func testRemovingHiddenWindowReturnsItToCurrentWorkspace() async {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 11, parent: workspace.rootTilingContainer)
        _ = await parseCommand("scratchpad --window-id 11 assign 3").cmdOrDie.run(.defaultEnv, .emptyStdin)

        ScratchpadManager.shared.remove(windowId: 11, from: 3)

        XCTAssertNil(window.scratchpadSlot)
        assertFalse(window.scratchpadIsPresented)
        assertFalse(window.scratchpadUsesNativeMinimize)
        assertEquals(window.nodeWorkspace, workspace)
        assertFalse(window.isFloating)
        assertTrue(ScratchpadManager.shared.items(in: 3).isEmpty)
    }

    func testRemovingWindowEscapesLeakedInternalWorkspace() async {
        let userWorkspace = focus.workspace
        let window = TestWindow.new(id: 12, parent: userWorkspace.rootTilingContainer)
        _ = await parseCommand("scratchpad --window-id 12 assign 5").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let backingWorkspace = Workspace.get(byName: "_smooth-scratchpad-5")
        assertTrue(backingWorkspace.focusWorkspace())

        ScratchpadManager.shared.remove(windowId: 12, from: 5)

        XCTAssertNil(window.scratchpadSlot)
        assertEquals(window.nodeWorkspace, userWorkspace)
        assertFalse(window.isFloating)
        assertEquals(focus.workspace, userWorkspace)
        assertEquals(mainMonitorInfo.activeWorkspace, userWorkspace)
    }

    func testRefreshRecoversOrphanedWindowFromVisibleInternalWorkspace() {
        let userWorkspace = focus.workspace
        let backingWorkspace = Workspace.get(byName: "_smooth-scratchpad-6")
        let orphanedWindow = TestWindow.new(id: 13, parent: backingWorkspace.floatingWindowsContainer)
        assertTrue(backingWorkspace.focusWorkspace())

        ScratchpadManager.shared.synchronizeAfterModelRefresh()

        XCTAssertNil(orphanedWindow.scratchpadSlot)
        assertEquals(orphanedWindow.nodeWorkspace, userWorkspace)
        assertFalse(orphanedWindow.isFloating)
        assertEquals(focus.workspace, userWorkspace)
        assertEquals(mainMonitorInfo.activeWorkspace, userWorkspace)
        assertFalse(backingWorkspace.isVisible)
    }

    func testRemovingOriginallyFloatingWindowKeepsItFloating() async {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 14, parent: workspace.floatingWindowsContainer)
        _ = await parseCommand("scratchpad --window-id 14 assign 7").cmdOrDie.run(.defaultEnv, .emptyStdin)

        ScratchpadManager.shared.remove(windowId: 14, from: 7)

        XCTAssertNil(window.scratchpadSlot)
        XCTAssertNil(window.scratchpadWasFloating)
        assertEquals(window.nodeWorkspace, workspace)
        assertTrue(window.isFloating)
    }

    func testRemovingPresentedTiledWindowRestoresTiling() async {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 15, parent: workspace.rootTilingContainer)
        _ = await parseCommand("scratchpad --window-id 15 assign 8").cmdOrDie.run(.defaultEnv, .emptyStdin)
        _ = await parseCommand("scratchpad toggle 8").cmdOrDie.run(.defaultEnv, .emptyStdin)

        ScratchpadManager.shared.remove(windowId: 15, from: 8)

        XCTAssertNil(window.scratchpadSlot)
        XCTAssertNil(window.scratchpadWasFloating)
        assertEquals(window.nodeWorkspace, workspace)
        assertFalse(window.isFloating)
    }

    func testCaptureCanBeArmedAndCancelled() {
        ScratchpadManager.shared.beginCapture(for: 6)
        assertEquals(ScratchpadManager.shared.armedSlot, 6)

        ScratchpadManager.shared.cancelCapture()

        XCTAssertNil(ScratchpadManager.shared.armedSlot)
    }
}
