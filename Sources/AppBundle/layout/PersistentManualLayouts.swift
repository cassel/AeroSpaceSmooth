import Combine
import Common
import Foundation

struct PersistentWindowIdentity: Codable, Hashable, Sendable {
    let applicationIdentifier: String
    let title: String
    let titleOccurrence: Int
    let applicationOccurrence: Int
}

struct PersistentLayoutNode: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case container
        case window
    }

    let kind: Kind
    let weight: Double
    let orientation: String?
    let layout: String?
    let window: PersistentWindowIdentity?
    let children: [PersistentLayoutNode]

    var windowIdentities: [PersistentWindowIdentity] {
        window.map { [$0] } ?? children.flatMap(\.windowIdentities)
    }
}

struct PersistentWorkspaceLayout: Codable, Equatable, Sendable {
    let workspaceName: String
    let monitorIdentifier: String
    let root: PersistentLayoutNode
}

@MainActor
final class PersistentManualLayoutStore: ObservableObject {
    static let shared = PersistentManualLayoutStore()

    private static let layoutsKey = "AeroSpaceSmooth.manual-workspace-layouts.v1"
    private static let enabledKey = "AeroSpaceSmooth.restore-manual-workspace-layouts"
    private let defaults: UserDefaults
    private var isReadyToCapture = false

    @Published private(set) var isEnabled: Bool
    @Published private(set) var layouts: [String: PersistentWorkspaceLayout]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        layouts = defaults.data(forKey: Self.layoutsKey)
            .flatMap { try? JSONDecoder().decode([String: PersistentWorkspaceLayout].self, from: $0) }
            ?? [:]
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    func clear() {
        layouts = [:]
        persist()
    }

    func restoreAfterInitialRefresh() async {
        defer { isReadyToCapture = true }
        guard isEnabled else { return }
        await restore()
    }

    func captureIfReady() async {
        guard isReadyToCapture else { return }
        await capture()
    }

    func capture() async {
        guard isEnabled else { return }
        var updated = layouts

        for workspace in Workspace.all where workspace.isUserFacing {
            let monitor = workspace.workspaceMonitor
            let automaticLayoutEnabled = SmoothLayoutSettingsStore.shared.profile(for: monitor).enabled
            let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
            guard !automaticLayoutEnabled, !windows.isEmpty else {
                updated.removeValue(forKey: workspace.name)
                continue
            }

            let identities = await windowIdentities(windows)
            let root = captureNode(workspace.rootTilingContainer, weight: 1, identities: identities)
            updated[workspace.name] = PersistentWorkspaceLayout(
                workspaceName: workspace.name,
                monitorIdentifier: monitor.stableIdentifier,
                root: root,
            )
        }

        if updated != layouts {
            layouts = updated
            persist()
        }
    }

    func restore() async {
        guard isEnabled else { return }

        for workspace in Workspace.all where workspace.isUserFacing {
            guard let saved = layouts[workspace.name] else { continue }
            let monitor = workspace.workspaceMonitor
            guard saved.workspaceName == workspace.name,
                  saved.monitorIdentifier == monitor.stableIdentifier
            else { continue }
            guard !SmoothLayoutSettingsStore.shared.profile(for: monitor).enabled else { continue }

            let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
            guard windows.count == saved.root.windowIdentities.count, !windows.isEmpty else { continue }
            let currentIdentities = await windowIdentities(windows)
            guard let matchedWindows = matchWindows(
                saved.root.windowIdentities,
                currentWindows: windows,
                currentIdentities: currentIdentities,
            ) else { continue }

            restorePersistentLayout(saved.root, in: workspace, windows: matchedWindows)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        defaults.set(data, forKey: Self.layoutsKey)
    }
}

@MainActor
private func windowIdentities(_ windows: [Window]) async -> [UInt32: PersistentWindowIdentity] {
    var applicationCounts: [String: Int] = [:]
    var titleCounts: [String: Int] = [:]
    var result: [UInt32: PersistentWindowIdentity] = [:]

    for window in windows {
        let applicationIdentifier = window.app.rawAppBundleId ?? window.app.execPath ?? window.app.name ?? "unknown-application"
        let title: String
        if let cached = window.persistentLayoutTitle {
            title = cached
        } else {
            title = (try? await window.getTitle(.nonCancellable)) ?? ""
            window.persistentLayoutTitle = title
        }
        let titleKey = "\(applicationIdentifier)\u{1f}\(title)"
        let identity = PersistentWindowIdentity(
            applicationIdentifier: applicationIdentifier,
            title: title,
            titleOccurrence: titleCounts[titleKey, default: 0],
            applicationOccurrence: applicationCounts[applicationIdentifier, default: 0],
        )
        titleCounts[titleKey, default: 0] += 1
        applicationCounts[applicationIdentifier, default: 0] += 1
        result[window.windowId] = identity
    }
    return result
}

@MainActor
private func captureNode(
    _ node: TreeNode,
    weight: Double,
    identities: [UInt32: PersistentWindowIdentity],
) -> PersistentLayoutNode {
    switch node.nodeCases {
        case .window(let window):
            return PersistentLayoutNode(
                kind: .window,
                weight: weight,
                orientation: nil,
                layout: nil,
                window: identities[window.windowId].orDie(),
                children: [],
            )
        case .tilingContainer(let container):
            return PersistentLayoutNode(
                kind: .container,
                weight: weight,
                orientation: container.orientation == .h ? "horizontal" : "vertical",
                layout: container.layout.rawValue,
                window: nil,
                children: container.children.map {
                    captureNode(
                        $0,
                        weight: Double($0.getWeight(container.orientation)),
                        identities: identities,
                    )
                },
            )
        case .workspace, .floatingWindowsContainer, .macosMinimizedWindowsContainer,
             .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer:
            return dieT("Persistent manual layouts only support tiling trees")
    }
}

@MainActor
private func matchWindows(
    _ savedIdentities: [PersistentWindowIdentity],
    currentWindows: [Window],
    currentIdentities: [UInt32: PersistentWindowIdentity],
) -> [PersistentWindowIdentity: Window]? {
    var exact: [String: Window] = [:]
    var byApplication: [String: [Window]] = [:]
    for window in currentWindows {
        guard let identity = currentIdentities[window.windowId] else { return nil }
        exact[persistentExactWindowKey(identity)] = window
        byApplication[identity.applicationIdentifier, default: []].append(window)
    }

    var usedWindowIds: Set<UInt32> = []
    var result: [PersistentWindowIdentity: Window] = [:]
    for identity in savedIdentities {
        let exactWindow = exact[persistentExactWindowKey(identity)].flatMap { window in
            usedWindowIds.contains(window.windowId) ? nil : window
        }
        let fallbackWindow = byApplication[identity.applicationIdentifier]?
            .getOrNil(atIndex: identity.applicationOccurrence)
            .flatMap { window in usedWindowIds.contains(window.windowId) ? nil : window }
        let window = exactWindow ?? fallbackWindow
        guard let window else { return nil }
        usedWindowIds.insert(window.windowId)
        result[identity] = window
    }
    return result
}

private func persistentExactWindowKey(_ identity: PersistentWindowIdentity) -> String {
    "\(identity.applicationIdentifier)\u{1f}\(identity.title)\u{1f}\(identity.titleOccurrence)"
}

@MainActor
private func restorePersistentLayout(
    _ savedRoot: PersistentLayoutNode,
    in workspace: Workspace,
    windows: [PersistentWindowIdentity: Window],
) {
    guard savedRoot.kind == .container,
          let orientation = savedRoot.orientation.flatMap(persistentOrientation),
          let layout = savedRoot.layout.flatMap(Layout.init(rawValue:))
    else { return }

    let root = workspace.rootTilingContainer
    let previouslyFocusedWindow = focus.windowOrNil?.takeIf { workspace.rootTilingContainer.allLeafWindowsRecursive.contains($0) }
    for window in workspace.rootTilingContainer.allLeafWindowsRecursive { window.unbindFromParent() }
    for child in root.children { child.unbindFromParent() }
    root.changeOrientation(orientation)
    root.layout = layout
    restoreChildren(savedRoot.children, parent: root, windows: windows)
    previouslyFocusedWindow?.markAsMostRecentChild()
}

@MainActor
private func restoreChildren(
    _ children: [PersistentLayoutNode],
    parent: TilingContainer,
    windows: [PersistentWindowIdentity: Window],
) {
    for child in children {
        switch child.kind {
            case .window:
                guard let identity = child.window, let window = windows[identity] else { continue }
                window.bind(to: parent, adaptiveWeight: CGFloat(child.weight), index: INDEX_BIND_LAST)
            case .container:
                guard let orientation = child.orientation.flatMap(persistentOrientation),
                      let layout = child.layout.flatMap(Layout.init(rawValue:))
                else { continue }
                let container = TilingContainer(
                    parent: parent,
                    adaptiveWeight: CGFloat(child.weight),
                    orientation,
                    layout,
                    index: INDEX_BIND_LAST,
                )
                restoreChildren(child.children, parent: container, windows: windows)
        }
    }
}

private func persistentOrientation(_ raw: String) -> Orientation? {
    switch raw {
        case "horizontal": .h
        case "vertical": .v
        default: nil
    }
}
