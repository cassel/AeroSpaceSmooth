public enum ScratchpadAction: String, CaseIterable, Equatable, Sendable {
    case assign
    case toggle
}

public struct ScratchpadCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }

    public static let parser: CmdParser<Self> = .init(
        kind: .scratchpad,
        help: scratchpad_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.action, parseScratchpadAction, placeholder: "(assign|toggle)"),
            newMandatoryPosArgParser(\.slot, parseScratchpadSlot, placeholder: "<slot>"),
        ],
    )

    public var action: Lateinit<ScratchpadAction> = .uninitialized
    public var slot: Lateinit<Int> = .uninitialized
}

private func parseScratchpadAction(_ input: PosArgParserInput) -> ParsedCliArgs<ScratchpadAction> {
    .init(parseEnum(input.arg, ScratchpadAction.self), advanceBy: 1)
}

private func parseScratchpadSlot(_ input: PosArgParserInput) -> ParsedCliArgs<Int> {
    let result = Int(input.arg)
        .toResult("Can't convert '\(input.arg)' to a scratchpad slot")
        .filter("Scratchpad slot must be between 1 and 10") { (1 ... smoothWorkspaceSlotCount).contains($0) }
    return .init(result, advanceBy: 1)
}

func parseScratchpadCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ScratchpadCmdArgs> {
    parseSpecificCmdArgs(ScratchpadCmdArgs(rawArgs: args), args)
        .filterNot("--window-id can only be used with 'scratchpad assign'") {
            $0.action.val == .toggle && $0.windowId != nil
        }
}
