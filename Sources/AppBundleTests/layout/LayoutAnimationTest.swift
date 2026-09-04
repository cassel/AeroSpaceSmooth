@testable import AppBundle
import XCTest

@MainActor
final class LayoutAnimationTest: XCTestCase {
    func testRepeatedRejectedSizeIsSuppressedAfterConfirmation() {
        var tracker = LayoutFrameAcceptanceTracker()
        let requested = CGSize(width: 420, height: 300)
        let clamped = CGSize(width: 640, height: 480)

        tracker.observe(windowId: 7, requested: requested, observed: clamped)
        assertEquals(tracker.sizeToApply(windowId: 7, requested: requested), requested)

        tracker.observe(windowId: 7, requested: requested, observed: clamped)
        XCTAssertNil(tracker.sizeToApply(windowId: 7, requested: requested))
    }

    func testNewRequestedSizeIsTriedAndAcceptedSizeClearsRejection() {
        var tracker = LayoutFrameAcceptanceTracker()
        let rejected = CGSize(width: 420, height: 300)
        let clamped = CGSize(width: 640, height: 480)
        let replacement = CGSize(width: 700, height: 520)

        tracker.observe(windowId: 9, requested: rejected, observed: clamped)
        tracker.observe(windowId: 9, requested: rejected, observed: clamped)
        assertEquals(tracker.sizeToApply(windowId: 9, requested: replacement), replacement)

        tracker.observe(windowId: 9, requested: replacement, observed: replacement)
        assertEquals(tracker.sizeToApply(windowId: 9, requested: rejected), rejected)
        XCTAssertNil(tracker.rejectedSizes[9])
    }

    func testRoundingNoiseDoesNotCountAsARefusal() {
        var tracker = LayoutFrameAcceptanceTracker()
        tracker.observe(
            windowId: 11,
            requested: CGSize(width: 500, height: 400),
            observed: CGSize(width: 500.5, height: 399.5),
        )

        XCTAssertNil(tracker.rejectedSizes[11])
    }
}
