import Foundation

public enum ModifierHotkeyEvent: Equatable, Sendable {
    case modifierChanged(isDown: Bool, hasOtherModifiers: Bool)
    case otherKeyDown
}

public enum ModifierHotkeyAction: Equatable, Sendable {
    case toggleRecording
}

/// Recognizes a tap of one modifier without treating modifier chords as dictation shortcuts.
public struct ModifierTapRecognizer: Sendable {
    private var isPressed = false
    private var chordInterruptedTap = false

    public init() {}

    public mutating func consume(_ event: ModifierHotkeyEvent) -> ModifierHotkeyAction? {
        switch event {
        case let .modifierChanged(isDown: true, hasOtherModifiers):
            guard !isPressed, !hasOtherModifiers else { return nil }
            isPressed = true
            chordInterruptedTap = false
            return nil

        case let .modifierChanged(isDown: false, hasOtherModifiers):
            guard isPressed else { return nil }
            isPressed = false
            defer { chordInterruptedTap = false }
            guard !chordInterruptedTap, !hasOtherModifiers else { return nil }
            return .toggleRecording

        case .otherKeyDown:
            if isPressed {
                chordInterruptedTap = true
            }
            return nil
        }
    }
}
