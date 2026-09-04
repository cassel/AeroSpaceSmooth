public struct CommandPaletteCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }

    public static let parser: CmdParser<Self> = .init(
        kind: .commandPalette,
        help: command_palette_help_generated,
        flags: [:],
        posArgs: [],
    )
}
