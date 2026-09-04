@testable import AppBundle
import XCTest

final class HotkeyBindingTest: XCTestCase {
    func testRepeatSuppressedBindingRunsOnceUntilKeyUp() {
        var guardState = HotkeyRepeatGuard()

        assertTrue(guardState.keyDown("alt-s", suppressesRepeat: true))
        assertFalse(guardState.keyDown("alt-s", suppressesRepeat: true))
        assertFalse(guardState.keyDown("alt-s", suppressesRepeat: true))

        guardState.keyUp("alt-s")

        assertTrue(guardState.keyDown("alt-s", suppressesRepeat: true))
    }

    func testRepeatableBindingStillHandlesEveryKeyDown() {
        var guardState = HotkeyRepeatGuard()

        assertTrue(guardState.keyDown("alt-h", suppressesRepeat: false))
        assertTrue(guardState.keyDown("alt-h", suppressesRepeat: false))
    }

    func testResetReleasesSuppressedBindings() {
        var guardState = HotkeyRepeatGuard()
        assertTrue(guardState.keyDown("alt-s", suppressesRepeat: true))

        guardState.reset()

        assertTrue(guardState.keyDown("alt-s", suppressesRepeat: true))
    }
}
