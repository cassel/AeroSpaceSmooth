@testable import AppBundle
import XCTest

final class WorkspaceNavigatorCommandTest: XCTestCase {
    func testCommandsParseWithoutArguments() {
        XCTAssertTrue(parseCommand("overview").cmdOrDie.flatten().singleOrNil() is OverviewCommand)
        XCTAssertTrue(parseCommand("command-palette").cmdOrDie.flatten().singleOrNil() is CommandPaletteCommand)
    }

    func testCommandsRejectUnexpectedArguments() {
        XCTAssertNotNil(parseCommand("overview extra").errorOrNil)
        XCTAssertNotNil(parseCommand("command-palette extra").errorOrNil)
    }
}
