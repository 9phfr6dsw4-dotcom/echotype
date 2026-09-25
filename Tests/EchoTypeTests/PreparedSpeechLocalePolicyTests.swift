import XCTest
@testable import EchoTypeCore

final class PreparedSpeechLocalePolicyTests: XCTestCase {
    func testPreparedLocaleIsReusableForSamePinnedLanguage() {
        XCTAssertTrue(PreparedSpeechLocalePolicy.isPrepared(
            preparedIdentifier: "en-US",
            requestedIdentifier: "en"
        ))
    }

    func testDifferentOrMissingPreparedLanguageRequiresPreparation() {
        XCTAssertFalse(PreparedSpeechLocalePolicy.isPrepared(
            preparedIdentifier: "fr-FR",
            requestedIdentifier: "de"
        ))
        XCTAssertFalse(PreparedSpeechLocalePolicy.isPrepared(
            preparedIdentifier: nil,
            requestedIdentifier: "en-US"
        ))
    }

    func testScriptVariantsRequireSeparatePreparation() {
        XCTAssertFalse(PreparedSpeechLocalePolicy.isPrepared(
            preparedIdentifier: "zh-Hans-CN",
            requestedIdentifier: "zh-Hant-TW"
        ))
        XCTAssertTrue(PreparedSpeechLocalePolicy.isPrepared(
            preparedIdentifier: "zh-Hans-CN",
            requestedIdentifier: "zh-Hans-SG"
        ))
    }
}
