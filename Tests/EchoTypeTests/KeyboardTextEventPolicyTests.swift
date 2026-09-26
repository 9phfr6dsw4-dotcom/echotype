import XCTest
@testable import EchoTypeCore

final class KeyboardTextEventPolicyTests: XCTestCase {
    func testSplitsLongTextIntoBoundedUnicodeEventChunks() {
        let input = String(repeating: "a", count: 45)
        let chunks = KeyboardTextEventPolicy.unicodeChunks(for: input)

        XCTAssertEqual(chunks.map(\.count), [20, 20, 5])
        XCTAssertEqual(chunks.flatMap { $0 }, Array(input.utf16))
    }

    func testDoesNotSplitSurrogatePairsAcrossEvents() {
        let input = String(repeating: "a", count: 19) + "😀" + "b"
        let chunks = KeyboardTextEventPolicy.unicodeChunks(for: input)

        XCTAssertEqual(chunks.map(\.count), [19, 2, 1])
        XCTAssertEqual(chunks.flatMap { $0 }, Array(input.utf16))
    }

    func testEmptyTextProducesNoKeyboardEvents() {
        XCTAssertTrue(KeyboardTextEventPolicy.unicodeChunks(for: "").isEmpty)
    }
}
