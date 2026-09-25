import XCTest
@testable import EchoTypeCore

final class TranscriptPersistencePlanTests: XCTestCase {
    func testMarkdownArchiveCanBeEnabledWhileLocalHistoryIsDisabled() {
        let plan = TranscriptPersistencePlan(
            historyEnabled: false,
            archiveDirectorySelected: true
        )

        XCTAssertFalse(plan.saveToLocalHistory)
        XCTAssertTrue(plan.writeMarkdownArchive)
    }

    func testNoArchiveSelectionDoesNotWriteMarkdown() {
        let plan = TranscriptPersistencePlan(
            historyEnabled: true,
            archiveDirectorySelected: false
        )

        XCTAssertTrue(plan.saveToLocalHistory)
        XCTAssertFalse(plan.writeMarkdownArchive)
    }
}
