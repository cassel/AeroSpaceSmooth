import Common

struct OverviewCommand: Command {
    let args: OverviewCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        WorkspaceNavigatorController.shared.show(.overview)
        return .succ
    }
}

struct CommandPaletteCommand: Command {
    let args: CommandPaletteCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        WorkspaceNavigatorController.shared.show(.commandPalette)
        return .succ
    }
}
