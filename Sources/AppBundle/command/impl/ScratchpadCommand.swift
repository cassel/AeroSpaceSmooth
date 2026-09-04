import AppKit
import Combine
import Common

struct ScratchpadCommand: Command {
    let args: ScratchpadCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true
    var suppressesKeyRepeat: Bool { args.action.val == .toggle }

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        switch args.action.val {
            case .assign:
                guard let target = args.resolveTargetOrReportError(env, io), let window = target.windowOrNil else {
                    return .fail(io.err(noWindowIsFocused))
                }
                ScratchpadManager.assign(window, to: args.slot.val)
                return .succ
            case .toggle:
                return ScratchpadManager.toggle(slot: args.slot.val, on: focus.workspace, io: io)
        }
    }
}

@MainActor
struct ScratchpadWindowItem: Identifiable, Equatable {
    let id: UInt32
    let applicationName: String
    let title: String
    let applicationPath: String?
    let isPresented: Bool
}

@MainActor
final class ScratchpadManager: ObservableObject {
    static let shared = ScratchpadManager()

    @Published private(set) var armedSlot: Int?
    @Published private(set) var statusMessage = ""
    @Published private(set) var windowItemsBySlot: [Int: [ScratchpadWindowItem]] = [:]

    private var captureIsAllowed = false
    private var captureTimeoutTask: Task<Void, Never>?
    private var titleRefreshTask: Task<Void, Never>?
    private var modelSignature: [Int: [String]] = [:]

    private init() {}

    static func assign(_ window: Window, to slot: Int) {
        shared.assign(window, to: slot)
    }

    private func assign(_ window: Window, to slot: Int) {
        guard (1 ... smoothWorkspaceSlotCount).contains(slot) else { return }
        let workspaceToKeepVisible = focus.workspace
        if window.scratchpadSlot == nil {
            window.scratchpadWasFloating = window.isFloating
        }
        window.scratchpadSlot = slot
        window.isFullscreen = false
        window.bindAsFloatingWindow(to: Self.backingWorkspace(slot: slot))
        _ = workspaceToKeepVisible.focusWorkspace()
        statusMessage = "\(window.app.name ?? "Window \(window.windowId)") was added to Slot \(slot) and hidden."
        refreshWindowItems(force: true)
    }

    static func toggle(slot: Int, on workspace: Workspace, io: CmdIo) -> BinaryExitCode {
        let windows = assignedWindows(in: slot)
        guard !windows.isEmpty else {
            return .fail(io.err("Scratchpad slot \(slot) has no windows. Focus a window and run 'scratchpad assign \(slot)' first."))
        }

        let isPresented = windows.contains { $0.nodeWorkspace == workspace }
        if isPresented {
            let backing = backingWorkspace(slot: slot)
            for window in windows { window.bindAsFloatingWindow(to: backing) }
            _ = workspace.focusWorkspace()
            shared.statusMessage = "Slot \(slot) was hidden."
        } else {
            for window in windows { window.bindAsFloatingWindow(to: workspace) }
            _ = windows.first?.focusWindow()
            shared.statusMessage = "Slot \(slot) is now visible on workspace \(workspace.name)."
        }
        shared.refreshWindowItems(force: true)
        return .succ
    }

    static func windowCount(slot: Int) -> Int {
        assignedWindows(in: slot).count
    }

    func beginCapture(for slot: Int) {
        guard (1 ... smoothWorkspaceSlotCount).contains(slot) else { return }
        captureTimeoutTask?.cancel()
        armedSlot = slot
        captureIsAllowed = false
        statusMessage = "Slot \(slot) is ready. Click the window you want to capture."
        captureTimeoutTask = Task.startUnstructured { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, self?.armedSlot == slot else { return }
            self?.armedSlot = nil
            self?.captureIsAllowed = false
            self?.statusMessage = "Capture timed out. No window was changed."
        }
    }

    func cancelCapture() {
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil
        armedSlot = nil
        captureIsAllowed = false
        statusMessage = "Capture cancelled."
    }

    func noteExternalSelection() {
        guard armedSlot != nil else { return }
        captureIsAllowed = true
    }

    func synchronizeAfterModelRefresh() {
        restoreVisibleInternalWorkspaces()
        if let slot = armedSlot,
           captureIsAllowed,
           let window = focus.windowOrNil,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.pid
        {
            captureTimeoutTask?.cancel()
            captureTimeoutTask = nil
            armedSlot = nil
            captureIsAllowed = false
            assign(window, to: slot)
        } else {
            refreshWindowItems()
        }
    }

    func items(in slot: Int) -> [ScratchpadWindowItem] {
        windowItemsBySlot[slot] ?? []
    }

    func isPresented(slot: Int, on workspace: Workspace) -> Bool {
        Self.assignedWindows(in: slot).contains { $0.nodeWorkspace == workspace }
    }

    func remove(windowId: UInt32, from slot: Int) {
        guard let window = Window.get(byId: windowId), window.scratchpadSlot == slot else { return }
        let sourceWorkspace = window.nodeWorkspace.orDie()
        let wasHidden = !sourceWorkspace.isUserFacing
        let destination = focus.workspace.isUserFacing
            ? focus.workspace
            : getStubWorkspace(for: sourceWorkspace.workspaceMonitor)
        let restoreAsFloating = window.scratchpadWasFloating ?? false
        window.scratchpadSlot = nil
        window.scratchpadWasFloating = nil
        if wasHidden {
            restore(window, to: destination, asFloating: restoreAsFloating)
            _ = window.focusWindow()
        } else if !restoreAsFloating {
            restore(window, to: sourceWorkspace, asFloating: false)
        }
        statusMessage = wasHidden
            ? "\(window.app.name ?? "Window \(window.windowId)") was removed from Slot \(slot) and restored on workspace \(destination.name)."
            : "\(window.app.name ?? "Window \(window.windowId)") was removed from Slot \(slot)."
        refreshWindowItems(force: true)
    }

    func refreshWindowItems(force: Bool = false) {
        let grouped = Dictionary(grouping: Self.assignedWindows(), by: { $0.scratchpadSlot.orDie() })
        let signature = grouped.mapValues { windows in
            windows.map { "\($0.windowId):\($0.nodeWorkspace?.name ?? "")" }
        }
        guard force || signature != modelSignature else { return }
        modelSignature = signature
        titleRefreshTask?.cancel()

        let preliminary = grouped.mapValues { windows in
            windows.map {
                ScratchpadWindowItem(
                    id: $0.windowId,
                    applicationName: $0.app.name ?? "Application",
                    title: $0.persistentLayoutTitle ?? "Window \($0.windowId)",
                    applicationPath: $0.app.bundlePath,
                    isPresented: !$0.nodeWorkspace.orDie().name.hasPrefix("_smooth-scratchpad-"),
                )
            }
        }
        windowItemsBySlot = preliminary
        guard !isUnitTest else { return }

        let expectedSignature = signature
        titleRefreshTask = Task.startUnstructured { @MainActor [weak self] in
            var refreshed = preliminary
            for (slot, windows) in grouped {
                for (index, window) in windows.enumerated() {
                    guard !Task.isCancelled else { return }
                    let title = (try? await window.getTitle(.cancellable))
                        .flatMap { $0.takeIf { !$0.isEmpty } }
                        ?? preliminary[slot].orDie()[index].title
                    refreshed[slot]?[index] = ScratchpadWindowItem(
                        id: window.windowId,
                        applicationName: window.app.name ?? "Application",
                        title: title,
                        applicationPath: window.app.bundlePath,
                        isPresented: !window.nodeWorkspace.orDie().name.hasPrefix("_smooth-scratchpad-"),
                    )
                }
            }
            guard !Task.isCancelled, self?.modelSignature == expectedSignature else { return }
            self?.windowItemsBySlot = refreshed
        }
    }

    private static func assignedWindows(in slot: Int) -> [Window] {
        assignedWindows().filter { $0.scratchpadSlot == slot }
    }

    private static func assignedWindows() -> [Window] {
        Workspace.all
            .flatMap(\.allLeafWindowsRecursive)
            .filter { $0.scratchpadSlot != nil }
            .sorted { $0.windowId < $1.windowId }
    }

    private static func backingWorkspace(slot: Int) -> Workspace {
        Workspace.get(byName: "_smooth-scratchpad-\(slot)")
    }

    /// Repairs state produced by older builds where a private scratchpad workspace
    /// could become visible. Unassigned windows are restored instead of stranded.
    private func restoreVisibleInternalWorkspaces() {
        for monitor in sortedMonitorInfos {
            let internalWorkspace = monitor.activeWorkspace
            guard !internalWorkspace.isUserFacing else { continue }

            let destination = getStubWorkspace(for: monitor)
            let orphanedWindows = internalWorkspace.allLeafWindowsRecursive.filter { $0.scratchpadSlot == nil }
            for window in orphanedWindows {
                restore(window, to: destination, asFloating: window.scratchpadWasFloating ?? false)
                window.scratchpadWasFloating = nil
            }

            if focus.workspace == internalWorkspace {
                if let window = orphanedWindows.first {
                    _ = window.focusWindow()
                } else {
                    _ = destination.focusWorkspace()
                }
            } else {
                _ = monitor.setActiveWorkspace(destination)
            }
        }
    }

    private func restore(_ window: Window, to workspace: Workspace, asFloating: Bool) {
        if asFloating {
            window.bindAsFloatingWindow(to: workspace)
        } else {
            window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
    }
}
