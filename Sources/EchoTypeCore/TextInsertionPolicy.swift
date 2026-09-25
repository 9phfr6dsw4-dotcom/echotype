import Foundation

public struct TextInsertionSnapshot: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let applicationName: String?
    public let focusedRole: String?
    public let focusedSubrole: String?

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        focusedRole: String?,
        focusedSubrole: String? = nil,
        applicationName: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.focusedRole = focusedRole
        self.focusedSubrole = focusedSubrole
    }
}

public struct TextInsertionDiagnostic: Equatable, Sendable {
    public let appAtDictationStop: String
    public let appWhenTextWasReady: String
    public let focusedElementAtStop: String
    public let focusedElementWhenReady: String
    public let pasteResult: String
    public let clipboardRestorationWarning: String?

    public init(
        appAtDictationStop: String,
        appWhenTextWasReady: String,
        focusedElementAtStop: String,
        focusedElementWhenReady: String,
        pasteResult: String,
        clipboardRestorationWarning: String? = nil
    ) {
        self.appAtDictationStop = appAtDictationStop
        self.appWhenTextWasReady = appWhenTextWasReady
        self.focusedElementAtStop = focusedElementAtStop
        self.focusedElementWhenReady = focusedElementWhenReady
        self.pasteResult = pasteResult
        self.clipboardRestorationWarning = clipboardRestorationWarning
    }

    public var description: String {
        var lines = [
            "App at dictation stop: \(appAtDictationStop)",
            "App when text was ready: \(appWhenTextWasReady)",
            "Focused element at stop: \(focusedElementAtStop)",
            "Focused element when ready: \(focusedElementWhenReady)",
            "Paste result: \(pasteResult)"
        ]
        if let clipboardRestorationWarning {
            lines.append("Clipboard: \(clipboardRestorationWarning)")
        }
        return lines.joined(separator: "\n")
    }
}

public enum TextInsertionBlockReason: Equatable, Sendable {
    case targetUnavailable
    case targetChanged
    case excludedApplication
    case secureField
}

public enum TextInsertionDecision: Equatable, Sendable {
    case insert
    case pasteInSameApplication
    case copyOnly(TextInsertionBlockReason)
}

public struct TextInsertionPolicy: Sendable {
    public static let defaultExcludedBundleIdentifiers: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword",
        "com.lastpass.lastpass",
        "com.bitwarden.desktop"
    ]

    private let excludedBundleIdentifiers: Set<String>
    private let textInputRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField"]

    public init(excludedBundleIdentifiers: Set<String> = Self.defaultExcludedBundleIdentifiers) {
        self.excludedBundleIdentifiers = Set(excludedBundleIdentifiers.map { $0.lowercased() })
    }

    public func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return excludedBundleIdentifiers.contains(bundleIdentifier.lowercased())
    }

    public func decision(
        captured: TextInsertionSnapshot?,
        current: TextInsertionSnapshot?,
        sameFocusedElement: Bool
    ) -> TextInsertionDecision {
        guard let captured, let current else { return .copyOnly(.targetUnavailable) }
        guard !isExcluded(bundleIdentifier: captured.bundleIdentifier),
              !isExcluded(bundleIdentifier: current.bundleIdentifier) else {
            return .copyOnly(.excludedApplication)
        }
        guard sameApplication(captured, current) else {
            return .copyOnly(.targetChanged)
        }
        guard !isSecureField(captured), !isSecureField(current) else {
            return .copyOnly(.secureField)
        }
        if sameFocusedElement,
           let role = current.focusedRole,
           textInputRoles.contains(role) {
            return .insert
        }
        return .pasteInSameApplication
    }

    private func isSecureField(_ snapshot: TextInsertionSnapshot) -> Bool {
        snapshot.focusedRole == "AXSecureTextField" || snapshot.focusedSubrole == "AXSecureTextField"
    }

    public func sameApplication(_ lhs: TextInsertionSnapshot, _ rhs: TextInsertionSnapshot) -> Bool {
        // Bundle identity represents the foreground app; PID may change if that app relaunches.
        if let leftBundle = lhs.bundleIdentifier, let rightBundle = rhs.bundleIdentifier {
            return leftBundle.caseInsensitiveCompare(rightBundle) == .orderedSame
        }
        return lhs.processIdentifier > 0 && lhs.processIdentifier == rhs.processIdentifier
    }
}
