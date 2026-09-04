import AppKit
import Combine
import Common
import SwiftUI

@MainActor
final class WorkspaceBarSettings: ObservableObject {
    static let shared = WorkspaceBarSettings()

    private static let enabledKey = "AeroSpaceSmooth.workspace-bar.enabled"
    private static let showEmptyKey = "AeroSpaceSmooth.workspace-bar.show-empty"
    private let defaults: UserDefaults

    @Published private(set) var isEnabled: Bool
    @Published private(set) var showsEmptyWorkspaces: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        showsEmptyWorkspaces = defaults.object(forKey: Self.showEmptyKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        WorkspaceBarController.shared.refresh()
    }

    func setShowsEmptyWorkspaces(_ show: Bool) {
        showsEmptyWorkspaces = show
        defaults.set(show, forKey: Self.showEmptyKey)
        WorkspaceBarController.shared.refresh()
    }
}

private struct WorkspaceBarItem: Identifiable {
    let name: String
    let isActive: Bool
    let isFocused: Bool
    let windowCount: Int
    let hasFullscreenWindow: Bool

    var id: String { name }
}

private struct WorkspaceBarSnapshot {
    let monitorName: String
    let items: [WorkspaceBarItem]
}

@MainActor
final class WorkspaceBarController {
    static let shared = WorkspaceBarController()

    private var panels: [String: NSPanel] = [:]

    private init() {}

    func refresh() {
        guard !isUnitTest else { return }
        let settings = WorkspaceBarSettings.shared
        guard settings.isEnabled, TrayMenuModel.shared.isEnabled else {
            hideAll()
            return
        }

        let monitors = sortedMonitorInfos
        let activeIdentifiers = Set(monitors.map(\.stableIdentifier))
        for identifier in panels.keys where !activeIdentifiers.contains(identifier) {
            panels.removeValue(forKey: identifier)?.close()
        }

        for monitor in monitors {
            guard let screen = NSScreen.screens.getOrNil(atIndex: monitor.monitorAppKitNsScreenScreensId - 1) else { continue }
            let workspaces = Workspace.all
                .filter { workspace in
                    !workspace.name.hasPrefix("_smooth-") &&
                        workspace.workspaceMonitor.stableIdentifier == monitor.stableIdentifier &&
                        (settings.showsEmptyWorkspaces || workspace.isVisible || !workspace.isEffectivelyEmpty)
                }
                .sorted()
            let snapshot = WorkspaceBarSnapshot(
                monitorName: monitor.name,
                items: workspaces.map { workspace in
                    WorkspaceBarItem(
                        name: workspace.name,
                        isActive: monitor.activeWorkspace == workspace,
                        isFocused: focus.workspace == workspace,
                        windowCount: workspace.allLeafWindowsRecursive.count,
                        hasFullscreenWindow: workspace.allLeafWindowsRecursive.contains(where: \.isFullscreen),
                    )
                },
            )
            let panel = panels[monitor.stableIdentifier] ?? makePanel()
            panels[monitor.stableIdentifier] = panel
            panel.contentViewController = NSHostingController(rootView: WorkspaceBarView(snapshot: snapshot))
            position(panel, on: screen, itemCount: snapshot.items.count)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return panel
    }

    private func position(_ panel: NSPanel, on screen: NSScreen, itemCount: Int) {
        let width = min(screen.visibleFrame.width - 32, max(180, CGFloat(itemCount) * 52 + 36))
        let height: CGFloat = 36
        panel.setFrame(
            NSRect(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.maxY - height - 8,
                width: width,
                height: height,
            ),
            display: true,
        )
    }

    private func hideAll() {
        for panel in panels.values { panel.orderOut(nil) }
    }
}

@MainActor
private struct WorkspaceBarView: View {
    let snapshot: WorkspaceBarSnapshot

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "display")
                .foregroundStyle(.secondary)
                .help(snapshot.monitorName)
            ForEach(snapshot.items) { item in
                Button {
                    focusWorkspace(named: item.name)
                } label: {
                    HStack(spacing: 3) {
                        if item.isFocused {
                            Circle().fill(.tint).frame(width: 5, height: 5)
                        }
                        Text(item.name)
                            .font(.system(.caption, design: .rounded, weight: item.isActive ? .bold : .medium))
                        if item.hasFullscreenWindow {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 26)
                    .background(item.isActive ? Color.accentColor.opacity(0.24) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("\(item.name) · \(item.windowCount) windows")
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.12)))
    }

    private func focusWorkspace(named name: String) {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        Task.startUnstructured { @MainActor in
            try await runLightSession(.menuBarButton, token) {
                _ = Workspace.get(byName: name).focusWorkspace()
            }
        }
    }
}
