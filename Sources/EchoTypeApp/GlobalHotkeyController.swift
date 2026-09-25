import AppKit
import ApplicationServices
import EchoTypeCore
import Observation

/// The primary hotkey can be one of the legacy bare modifier keys or a captured chord.
enum GlobalHotkeySelection: Equatable, Sendable {
    case modifierKey(UInt16)
    case shortcut(KeyboardShortcutDescriptor)
}

private enum GlobalHotkeyInputEvent: Sendable {
    case flagsChanged(keyCode: UInt16, modifierFlags: UInt)
    case keyDown(keyCode: UInt16, modifierFlags: UInt, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
}

@MainActor
@Observable
final class GlobalHotkeyController {
    private(set) var isEnabled = false
    private(set) var hasAccessibilityPermission = AXIsProcessTrusted()
    private(set) var statusMessage = "Enable the global hotkey to dictate from any app."
    private(set) var selectedKeyCode: UInt16
    private(set) var selectedHotkey: GlobalHotkeySelection
    private(set) var backupShortcut: KeyboardShortcutDescriptor?
    private(set) var selectedMode: ModifierHotkeyMode

    var selectedShortcut: KeyboardShortcutDescriptor? {
        guard case let .shortcut(shortcut) = selectedHotkey else { return nil }
        return shortcut
    }

    var onToggleRecording: (@MainActor () -> Void)?
    var onStartRecording: (@MainActor () -> Void)?
    var onStopRecording: (@MainActor () -> Void)?

    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var recognizer = ModifierTapRecognizer()
    @ObservationIgnored private var shortcutRecognizer: KeyboardShortcutRecognizer?
    @ObservationIgnored private var isHoldRecordingActive = false
    @ObservationIgnored private let defaults: UserDefaults

    private static let keyCodeDefaultsKey = "EchoType.globalHotkeyKeyCode"
    private static let modeDefaultsKey = "EchoType.globalHotkeyMode"
    private static let selectedShortcutDefaultsKey = "EchoType.globalHotkeyShortcut"
    private static let backupShortcutDefaultsKey = "EchoType.globalHotkeyBackupShortcut"
    private static let controlKeyCode: UInt16 = 59
    private static let rightOptionKeyCode: UInt16 = 61
    private static let functionKeyCode: UInt16 = 63
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    private static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedMode = ModifierHotkeyMode(rawValue: defaults.string(forKey: Self.modeDefaultsKey) ?? "") ?? .tapToToggle

        let savedKeyCode = UInt16(exactly: defaults.integer(forKey: Self.keyCodeDefaultsKey))
        let legacyKeyCode: UInt16
        if let savedKeyCode, Self.isLegacyModifierKey(savedKeyCode) {
            legacyKeyCode = savedKeyCode
        } else {
            legacyKeyCode = Self.controlKeyCode
        }
        let savedShortcut = Self.decodeShortcut(defaults.data(forKey: Self.selectedShortcutDefaultsKey))
            .flatMap { Self.isCustomKeyCode($0.keyCode) ? $0 : nil }

        if let savedShortcut {
            selectedKeyCode = savedShortcut.keyCode
            selectedHotkey = .shortcut(savedShortcut)
        } else {
            selectedKeyCode = legacyKeyCode
            selectedHotkey = .modifierKey(legacyKeyCode)
        }
        backupShortcut = Self.decodeShortcut(defaults.data(forKey: Self.backupShortcutDefaultsKey))
            .flatMap { Self.isCustomKeyCode($0.keyCode) ? $0 : nil }

        resetRecognizers()
    }

    var selectedKeyName: String {
        switch selectedHotkey {
        case let .modifierKey(keyCode):
            Self.modifierKeyName(for: keyCode)
        case let .shortcut(shortcut):
            shortcut.displayLabel ?? "Key code \(shortcut.keyCode)"
        }
    }

    func refreshPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        if !hasAccessibilityPermission {
            statusMessage = "Allow EchoType in System Settings → Privacy & Security → Accessibility."
        } else if !isEnabled {
            statusMessage = "Accessibility is ready. Enable the hotkey to listen for modifier taps."
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func chooseKey(keyCode: UInt16) {
        guard Self.isLegacyModifierKey(keyCode) else { return }
        selectedKeyCode = keyCode
        selectedHotkey = .modifierKey(keyCode)
        defaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.removeObject(forKey: Self.selectedShortcutDefaultsKey)
        resetRecognizers()
    }

    /// Selects a captured non-modifier key and its required modifier chord.
    @discardableResult
    func chooseCustomShortcut(_ shortcut: KeyboardShortcutDescriptor) -> Bool {
        guard Self.isCustomKeyCode(shortcut.keyCode),
              let data = try? JSONEncoder().encode(shortcut) else { return false }
        selectedKeyCode = shortcut.keyCode
        selectedHotkey = .shortcut(shortcut)
        defaults.set(Int(shortcut.keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(data, forKey: Self.selectedShortcutDefaultsKey)
        resetRecognizers()
        return true
    }

    /// Stores or clears the optional backup chord. The same shortcut recognizer handles both keys.
    @discardableResult
    func chooseBackupShortcut(_ shortcut: KeyboardShortcutDescriptor?) -> Bool {
        guard let shortcut else {
            backupShortcut = nil
            defaults.removeObject(forKey: Self.backupShortcutDefaultsKey)
            resetRecognizers()
            return true
        }
        guard Self.isCustomKeyCode(shortcut.keyCode),
              !Self.shortcutsMatch(shortcut, selectedShortcut),
              let data = try? JSONEncoder().encode(shortcut) else { return false }
        backupShortcut = shortcut
        defaults.set(data, forKey: Self.backupShortcutDefaultsKey)
        resetRecognizers()
        return true
    }

    func chooseMode(_ mode: ModifierHotkeyMode) {
        guard selectedMode != mode else { return }
        selectedMode = mode
        defaults.set(mode.rawValue, forKey: Self.modeDefaultsKey)
        resetRecognizers()
    }

    func enable() {
        refreshPermission()
        guard hasAccessibilityPermission else { return }
        guard !isEnabled else { return }

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let input: GlobalHotkeyInputEvent
            switch event.type {
            case .flagsChanged:
                input = .flagsChanged(keyCode: event.keyCode, modifierFlags: event.modifierFlags.rawValue)
            case .keyDown:
                input = .keyDown(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags.rawValue,
                    isRepeat: event.isARepeat
                )
            case .keyUp:
                input = .keyUp(keyCode: event.keyCode)
            default:
                return
            }
            Task { @MainActor [weak self] in
                self?.handle(input)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let input: GlobalHotkeyInputEvent
            switch event.type {
            case .flagsChanged:
                input = .flagsChanged(keyCode: event.keyCode, modifierFlags: event.modifierFlags.rawValue)
            case .keyDown:
                input = .keyDown(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags.rawValue,
                    isRepeat: event.isARepeat
                )
            case .keyUp:
                input = .keyUp(keyCode: event.keyCode)
            default:
                return event
            }
            Task { @MainActor [weak self] in
                self?.handle(input)
            }
            return event
        }

        guard globalMonitor != nil || localMonitor != nil else {
            statusMessage = "macOS did not allow the keyboard monitor to start. Check Accessibility permission."
            return
        }
        isEnabled = true
        let backupMessage = backupShortcut.map { " Backup \($0.displayLabel ?? "key code \($0.keyCode)") is also enabled." } ?? ""
        switch selectedHotkey {
        case .modifierKey:
            statusMessage = selectedMode == .tapToToggle
                ? "Listening for a bare \(selectedKeyName) tap. Key combinations such as Control-C are ignored.\(backupMessage)"
                : "Hold \(selectedKeyName) to dictate; release it to finish. Modifier chords are ignored.\(backupMessage)"
        case .shortcut:
            statusMessage = selectedMode == .tapToToggle
                ? "Listening for \(selectedKeyName) with its exact modifier chord. Other combinations are ignored.\(backupMessage)"
                : "Hold \(selectedKeyName) with its exact modifier chord to dictate; release it to finish. Other combinations are ignored.\(backupMessage)"
        }
    }

    func disable() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isEnabled = false
        stopActiveHoldIfNeeded()
        resetRecognizers()
        statusMessage = "Global hotkey is off."
    }

    private func handle(_ event: GlobalHotkeyInputEvent) {
        guard isEnabled else { return }
        switch event {
        case let .flagsChanged(keyCode, modifierFlags):
            guard case let .modifierKey(selectedKeyCode) = selectedHotkey,
                  keyCode == selectedKeyCode else { return }
            let flags = NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
            let targetModifier = Self.modifierFlag(for: selectedKeyCode)
            let hasOtherModifiers = !flags.subtracting(targetModifier).intersection(Self.relevantModifiers).isEmpty
            let isDown = flags.contains(targetModifier)
            dispatch(recognizer.consume(.modifierChanged(isDown: isDown, hasOtherModifiers: hasOtherModifiers)))

        case let .keyDown(keyCode, modifierFlags, isRepeat):
            dispatch(recognizer.consume(.otherKeyDown))
            guard var shortcutRecognizer else { return }
            let flags = Self.shortcutModifierFlags(
                from: NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
            )
            let action = shortcutRecognizer.consume(.keyDown(keyCode: keyCode, modifierFlags: flags, isRepeat: isRepeat))
            self.shortcutRecognizer = shortcutRecognizer
            dispatch(action)

        case let .keyUp(keyCode):
            guard var shortcutRecognizer else { return }
            let action = shortcutRecognizer.consume(.keyUp(keyCode: keyCode))
            self.shortcutRecognizer = shortcutRecognizer
            dispatch(action)
        }
    }

    private func resetRecognizers() {
        stopActiveHoldIfNeeded()
        recognizer = ModifierTapRecognizer(mode: selectedMode)
        switch selectedHotkey {
        case .modifierKey:
            if let backupShortcut {
                shortcutRecognizer = KeyboardShortcutRecognizer(primary: backupShortcut, mode: selectedMode)
            } else {
                shortcutRecognizer = nil
            }
        case let .shortcut(shortcut):
            shortcutRecognizer = KeyboardShortcutRecognizer(
                primary: shortcut,
                backup: backupShortcut,
                isBackupEnabled: backupShortcut != nil,
                mode: selectedMode
            )
        }
    }

    private func stopActiveHoldIfNeeded() {
        guard isHoldRecordingActive else { return }
        isHoldRecordingActive = false
        onStopRecording?()
    }

    private func dispatch(_ action: ModifierHotkeyAction?) {
        switch action {
        case .toggleRecording:
            onToggleRecording?()
        case .startRecording:
            isHoldRecordingActive = true
            onStartRecording?()
        case .stopRecording:
            isHoldRecordingActive = false
            onStopRecording?()
        case nil:
            break
        }
    }

    private static func decodeShortcut(_ data: Data?) -> KeyboardShortcutDescriptor? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcutDescriptor.self, from: data)
    }

    private static func shortcutsMatch(
        _ left: KeyboardShortcutDescriptor,
        _ right: KeyboardShortcutDescriptor?
    ) -> Bool {
        guard let right else { return false }
        return left.keyCode == right.keyCode
            && left.requiredModifierFlags == right.requiredModifierFlags
    }

    private static func isLegacyModifierKey(_ keyCode: UInt16) -> Bool {
        keyCode == controlKeyCode || keyCode == rightOptionKeyCode || keyCode == functionKeyCode
    }

    private static func isCustomKeyCode(_ keyCode: UInt16) -> Bool {
        !modifierKeyCodes.contains(keyCode)
    }

    private static func modifierKeyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case rightOptionKeyCode: "Right Option"
        case functionKeyCode: "Fn / Globe"
        default: "Left Control"
        }
    }

    private static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case rightOptionKeyCode: .option
        case functionKeyCode: .function
        default: .control
        }
    }

    private static func shortcutModifierFlags(from flags: NSEvent.ModifierFlags) -> KeyboardShortcutModifierFlags {
        var result: KeyboardShortcutModifierFlags = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.function) { result.insert(.function) }
        return result
    }
}
