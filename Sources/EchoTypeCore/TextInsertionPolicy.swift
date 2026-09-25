import Foundation

public struct TextInsertionSnapshot: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let focusedRole: String?
    public let focusedSubrole: String?

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        focusedRole: String?,
        focusedSubrole: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.focusedRole = focusedRole
        self.focusedSubrole = focusedSubrole
    }
}

public enum TextInsertionBlockReason: Equatable, Sendable {
    case targetUnavailable
    case targetChanged
    case excludedApplication
    case secureField
    case notTextInput
}

public enum TextInsertionDecision: Equatable, Sendable {
    case insert
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
        guard captured.processIdentifier == current.processIdentifier,
              sameFocusedElement else {
            return .copyOnly(.targetChanged)
        }
        if isSecureField(captured) || isSecureField(current) {
            return .copyOnly(.secureField)
        }
        guard let role = current.focusedRole, textInputRoles.contains(role) else {
            return .copyOnly(.notTextInput)
        }
        return .insert
    }

    private func isSecureField(_ snapshot: TextInsertionSnapshot) -> Bool {
        snapshot.focusedRole == "AXSecureTextField" || snapshot.focusedSubrole == "AXSecureTextField"
    }
}
