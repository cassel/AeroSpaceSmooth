public struct OverviewCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }

    public static let parser: CmdParser<Self> = .init(
        kind: .overview,
        help: overview_help_generated,
        flags: [:],
        posArgs: [],
    )
}
