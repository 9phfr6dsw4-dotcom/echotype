import XCTest
@testable import EchoTypeCore

final class TranscriptionVocabularyTests: XCTestCase {
    func testCombinesCustomAndLearnedTermsWithoutDuplicates() {
        let terms = TranscriptionVocabulary.terms(
            customTerms: ["EchoType", "Jordan  Lee"],
            learnedTerms: [
                makeLearnedTerm("ECHOTYPE", pinned: false),
                makeLearnedTerm("Parakeet", pinned: false)
            ]
        )

        XCTAssertEqual(terms, ["EchoType", "Jordan Lee", "Parakeet"])
    }

    func testPinnedLearnedTermsArePrioritizedWithinAppleLimit() {
        let customTerms = (0..<3).map { "Custom \($0)" }
        let learnedTerms = [
            makeLearnedTerm("Pinned Name", pinned: true),
            makeLearnedTerm("Unpinned Name", pinned: false)
        ]

        let terms = TranscriptionVocabulary.terms(
            customTerms: customTerms,
            learnedTerms: learnedTerms,
            maximumCount: 2
        )

        XCTAssertEqual(terms, ["Pinned Name", "Custom 0"])
    }

    func testIgnoresBlankTermsAndNormalizesWhitespace() {
        let terms = TranscriptionVocabulary.terms(
            customTerms: ["  ", " Ada   Lovelace ", "ada lovelace"],
            learnedTerms: []
        )

        XCTAssertEqual(terms, ["Ada Lovelace"])
    }

    func testWhisperPromptUsesOnlyProvidedVocabularyTerms() {
        XCTAssertEqual(
            TranscriptionVocabulary.whisperPromptText(from: ["EchoType", "Ada Lovelace"]),
            "EchoType, Ada Lovelace"
        )
    }

    private func makeLearnedTerm(_ term: String, pinned: Bool) -> LocalLearnedTerm {
        var store = LocalLearningStore()
        for _ in 0..<LocalLearningPolicy.minimumCorrectionOccurrences {
            _ = store.observeCorrection(original: "misheard", replacement: term)
        }
        if pinned {
            _ = store.setPinned(true, for: term)
        }
        return try! XCTUnwrap(store.learnedTerms.first)
    }
}
