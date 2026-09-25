import XCTest
@testable import EchoTypeCore

final class TextInsertionPolicyTests: XCTestCase {
    private let policy = TextInsertionPolicy()

    func testDiagnosticIncludesAppsFocusAndSkipReason() {
        let diagnostic = TextInsertionDiagnostic(
            appAtDictationStop: "ChatGPT",
            appWhenTextWasReady: "Claude",
            focusedElementAtStop: "AXTextArea",
            focusedElementWhenReady: "Unavailable (Accessibility API did not expose the focused element)",
            pasteResult: "The frontmost app changed between dictation stop and paste."
        )

        XCTAssertEqual(
            diagnostic.description,
            "App at dictation stop: ChatGPT\nApp when text was ready: Claude\nFocused element at stop: AXTextArea\nFocused element when ready: Unavailable (Accessibility API did not expose the focused element)\nPaste result: The frontmost app changed between dictation stop and paste."
        )
    }

    func testDiagnosticReportsClipboardRestorationFailure() {
        let diagnostic = TextInsertionDiagnostic(
            appAtDictationStop: "Claude",
            appWhenTextWasReady: "Claude",
            focusedElementAtStop: "Unavailable (Accessibility API did not expose the focused element)",
            focusedElementWhenReady: "Unavailable (Accessibility API did not expose the focused element)",
            pasteResult: "Command-V was sent; app acceptance cannot be confirmed.",
            clipboardRestorationWarning: "EchoType could not restore the previous clipboard contents."
        )

        XCTAssertTrue(diagnostic.description.contains("Clipboard: EchoType could not restore the previous clipboard contents."))
        XCTAssertTrue(diagnostic.description.contains("Paste result: Command-V was sent; app acceptance cannot be confirmed."))
    }

    func testVerifiedTextInputUsesAccessibilityInsertion() {
        let target = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXTextArea"
        )

        XCTAssertEqual(
            policy.decision(captured: target, current: target, sameFocusedElement: true),
            .insert
        )
    }

    func testSecureTextFieldIsNeverEligible() {
        let target = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXSecureTextField"
        )

        XCTAssertEqual(
            policy.decision(captured: target, current: target, sameFocusedElement: true),
            .copyOnly(.secureField)
        )
    }

    func testChangedApplicationFallsBackToCopyButSameAppFocusChangeStillPastes() {
        let captured = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXTextField"
        )
        let differentApp = TextInsertionSnapshot(
            processIdentifier: 84,
            bundleIdentifier: "com.example.mail",
            focusedRole: nil
        )
        let sameAppDifferentField = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXTextField"
        )

        XCTAssertEqual(policy.decision(captured: captured, current: differentApp, sameFocusedElement: false), .copyOnly(.targetChanged))
        XCTAssertEqual(policy.decision(captured: captured, current: sameAppDifferentField, sameFocusedElement: false), .pasteInSameApplication)
    }

    func testSameBundleIdentifierRemainsSameAppAcrossProcessChanges() {
        let beforeRestart = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXTextArea"
        )
        let afterRestart = TextInsertionSnapshot(
            processIdentifier: 84,
            bundleIdentifier: "COM.EXAMPLE.EDITOR",
            focusedRole: nil
        )

        XCTAssertTrue(policy.sameApplication(beforeRestart, afterRestart))
        XCTAssertEqual(
            policy.decision(captured: beforeRestart, current: afterRestart, sameFocusedElement: false),
            .pasteInSameApplication
        )
    }

    func testPasswordManagerIsExcludedEvenWhenItHasATextField() {
        let target = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.1password.1password",
            focusedRole: "AXTextField"
        )

        XCTAssertEqual(
            policy.decision(captured: target, current: target, sameFocusedElement: true),
            .copyOnly(.excludedApplication)
        )
    }

    func testUnknownFocusedControlFallsBackToSameAppPaste() {
        let target = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXButton"
        )

        XCTAssertEqual(
            policy.decision(captured: target, current: target, sameFocusedElement: false),
            .pasteInSameApplication
        )
    }

    func testUnavailableTextFieldFallsBackToPasteWhenAppIsKnown() {
        let target = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: nil
        )

        XCTAssertEqual(
            policy.decision(captured: target, current: target, sameFocusedElement: false),
            .pasteInSameApplication
        )
    }

    func testUnavailableApplicationFallsBackToCopy() {
        XCTAssertEqual(
            policy.decision(captured: nil, current: nil, sameFocusedElement: false),
            .copyOnly(.targetUnavailable)
        )
    }

    func testSecureFieldSubroleIsNeverEligible() {
        let target = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXTextField",
            focusedSubrole: "AXSecureTextField"
        )

        XCTAssertEqual(
            policy.decision(captured: target, current: target, sameFocusedElement: true),
            .copyOnly(.secureField)
        )
    }
}
