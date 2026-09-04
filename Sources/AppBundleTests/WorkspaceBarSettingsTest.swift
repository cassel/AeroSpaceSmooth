@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceBarSettingsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testPreferencesPersistAcrossStoreInstances() throws {
        let suiteName = "WorkspaceBarSettingsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkspaceBarSettings(defaults: defaults)

        assertFalse(store.isEnabled)
        assertTrue(store.showsEmptyWorkspaces)
        store.setEnabled(true)
        store.setShowsEmptyWorkspaces(false)

        let reopened = WorkspaceBarSettings(defaults: defaults)
        assertTrue(reopened.isEnabled)
        assertFalse(reopened.showsEmptyWorkspaces)
    }

    func testTrayNeverPublishesInternalWorkspaceNames() {
        let scratchpad = Workspace.get(byName: "_smooth-scratchpad-2")
        TestWindow.new(id: 20, parent: scratchpad.floatingWindowsContainer)
        assertTrue(scratchpad.focusWorkspace())

        updateTrayText()

        assertFalse(TrayMenuModel.shared.trayText.contains("_smooth-"))
        assertFalse(TrayMenuModel.shared.trayItems.contains { $0.name.hasPrefix("_smooth-") })
        assertFalse(TrayMenuModel.shared.workspaces.contains { $0.name.hasPrefix("_smooth-") })
    }
}
