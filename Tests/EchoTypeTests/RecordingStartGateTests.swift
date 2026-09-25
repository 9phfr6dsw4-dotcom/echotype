import XCTest
@testable import EchoTypeCore

final class RecordingStartGateTests: XCTestCase {
    func testCancelInvalidatesPendingStartAndAllowsNextAfterItFinishes() throws {
        var gate = RecordingStartGate()
        let first = try XCTUnwrap(gate.begin())

        XCTAssertTrue(gate.isCurrent(first))
        XCTAssertTrue(gate.cancelPending())
        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertNil(gate.begin(), "Do not overlap a canceled request that is still unwinding")

        gate.finish(first)
        let second = try XCTUnwrap(gate.begin())
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(gate.isCurrent(second))
    }

    func testCancelDoesNothingWhenNoStartIsPending() {
        var gate = RecordingStartGate()
        XCTAssertFalse(gate.cancelPending())
    }
}
