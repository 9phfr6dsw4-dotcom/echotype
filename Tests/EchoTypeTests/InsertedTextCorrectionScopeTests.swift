import XCTest
@testable import EchoTypeCore

final class InsertedTextCorrectionScopeTests: XCTestCase {
    func testCapturesOnlyNonemptySelectionsInsideRecentlyInsertedText() throws {
        let scope = try XCTUnwrap(InsertedTextCorrectionScope(insertedText: "Hello Andromeda world", insertionLocation: 8))

        let candidate = scope.candidate(
            for: InsertedTextCorrectionRange(location: 14, length: 9),
            fieldCharacterCount: 40
        )

        XCTAssertEqual(candidate?.originalText, "Andromeda")
        XCTAssertEqual(candidate?.range, InsertedTextCorrectionRange(location: 14, length: 9))
        XCTAssertNil(scope.candidate(for: InsertedTextCorrectionRange(location: 7, length: 2), fieldCharacterCount: 40))
        XCTAssertNil(scope.candidate(for: InsertedTextCorrectionRange(location: 28, length: 2), fieldCharacterCount: 40))
        XCTAssertNil(scope.candidate(for: InsertedTextCorrectionRange(location: 14, length: 0), fieldCharacterCount: 40))
    }

    func testAllowsAReplacementRangeOnlyWhenCaretMatchesTheExactLengthDelta() throws {
        let scope = try XCTUnwrap(InsertedTextCorrectionScope(insertedText: "Hello Andromeda world", insertionLocation: 8))
        let candidate = try XCTUnwrap(scope.candidate(
            for: InsertedTextCorrectionRange(location: 14, length: 9),
            fieldCharacterCount: 40
        ))

        XCTAssertEqual(
            scope.replacementRange(for: candidate, currentFieldCharacterCount: 43, caretLocation: 26),
            InsertedTextCorrectionRange(location: 14, length: 12)
        )
        XCTAssertNil(scope.replacementRange(for: candidate, currentFieldCharacterCount: 43, caretLocation: 25))
    }

    func testRejectsDeletionAndInvalidOrOutOfFieldRanges() throws {
        let scope = try XCTUnwrap(InsertedTextCorrectionScope(insertedText: "Andromeda", insertionLocation: 5))
        let candidate = try XCTUnwrap(scope.candidate(
            for: InsertedTextCorrectionRange(location: 5, length: 9),
            fieldCharacterCount: 14
        ))

        XCTAssertNil(scope.replacementRange(for: candidate, currentFieldCharacterCount: 5, caretLocation: 5))
        XCTAssertNil(scope.candidate(for: InsertedTextCorrectionRange(location: 5, length: 9), fieldCharacterCount: 10))
        XCTAssertNil(InsertedTextCorrectionScope(insertedText: "", insertionLocation: 0))
        XCTAssertNil(InsertedTextCorrectionScope(insertedText: "word", insertionLocation: -1))
        XCTAssertNil(InsertedTextCorrectionRange(location: -1, length: 1))
        XCTAssertNil(InsertedTextCorrectionRange(location: 1, length: -1))
    }

    func testUsesUTF16OffsetsForNonASCIIInsertedText() throws {
        let scope = try XCTUnwrap(InsertedTextCorrectionScope(insertedText: "😀 café", insertionLocation: 3))
        let candidate = scope.candidate(
            for: InsertedTextCorrectionRange(location: 6, length: 4),
            fieldCharacterCount: 13
        )

        XCTAssertEqual(candidate?.originalText, "café")
    }
}
