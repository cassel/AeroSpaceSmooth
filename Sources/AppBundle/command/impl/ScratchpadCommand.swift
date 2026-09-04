import Common

struct ScratchpadCommand: Command {
    let args: ScratchpadCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

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
enum ScratchpadManager {
    static func assign(_ window: Window, to slot: Int) {
        guard (1 ... smoothWorkspaceSlotCount).contains(slot) else { return }
        window.scratchpadSlot = slot
        window.isFullscreen = false
        window.bindAsFloatingWindow(to: backingWorkspace(slot: slot))
    }

    static func toggle(slot: Int, on workspace: Workspace, io: CmdIo) -> BinaryExitCode {
        let windows = Workspace.all
            .flatMap(\.allLeafWindowsRecursive)
            .filter { $0.scratchpadSlot == slot }
            .sorted { $0.windowId < $1.windowId }
        guard !windows.isEmpty else {
            return .fail(io.err("Scratchpad slot \(slot) has no windows. Focus a window and run 'scratchpad assign \(slot)' first."))
        }

        let isPresented = windows.contains { $0.nodeWorkspace == workspace }
        if isPresented {
            let backing = backingWorkspace(slot: slot)
            for window in windows { window.bindAsFloatingWindow(to: backing) }
        } else {
            for window in windows { window.bindAsFloatingWindow(to: workspace) }
            _ = windows.first?.focusWindow()
        }
        return .succ
    }

    static func windowCount(slot: Int) -> Int {
        Workspace.all.flatMap(\.allLeafWindowsRecursive).count { $0.scratchpadSlot == slot }
    }

    private static func backingWorkspace(slot: Int) -> Workspace {
        Workspace.get(byName: "_smooth-scratchpad-\(slot)")
    }
}
