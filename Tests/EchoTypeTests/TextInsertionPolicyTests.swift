import XCTest
@testable import EchoTypeCore

final class TextInsertionPolicyTests: XCTestCase {
    private let policy = TextInsertionPolicy()

    func testAllowsPasteOnlyIntoSameNonSecureTextInput() {
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

    func testChangedApplicationOrFocusedElementFallsBackToCopy() {
        let captured = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXTextField"
        )
        let differentApp = TextInsertionSnapshot(
            processIdentifier: 84,
            bundleIdentifier: "com.example.mail",
            focusedRole: "AXTextField"
        )
        let sameAppDifferentField = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXTextField"
        )

        XCTAssertEqual(policy.decision(captured: captured, current: differentApp, sameFocusedElement: false), .copyOnly(.targetChanged))
        XCTAssertEqual(policy.decision(captured: captured, current: sameAppDifferentField, sameFocusedElement: false), .copyOnly(.targetChanged))
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

    func testUnknownFocusedControlDoesNotReceivePastedText() {
        let target = TextInsertionSnapshot(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            focusedRole: "AXButton"
        )

        XCTAssertEqual(
            policy.decision(captured: target, current: target, sameFocusedElement: true),
            .copyOnly(.notTextInput)
        )
    }

    func testUnavailableFocusFallsBackToCopy() {
        XCTAssertEqual(
            policy.decision(captured: nil, current: nil, sameFocusedElement: false),
            .copyOnly(.targetUnavailable)
        )
    }
}
