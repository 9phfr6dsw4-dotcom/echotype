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

    var diagnosticLabel: String {
        switch self {
        case let .flagsChanged(keyCode, _): "flagsChanged keyCode \(keyCode)"
        case let .keyDown(keyCode, _, isRepeat):
            if isRepeat {
                "keyDown keyCode \(keyCode) repeat"
            } else {
                "keyDown keyCode \(keyCode)"
            }
        case let .keyUp(keyCode): "keyUp keyCode \(keyCode)"
        }
    }
}

@MainActor
@Observable
final class GlobalHotkeyController {
    private(set) var isEnabled = false
    private(set) var hasAccessibilityPermission = AXIsProcessTrusted()
    private(set) var statusMessage = "Global hotkey has not been enabled yet."
    private(set) var receivedKeyboardEventCount = 0
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
    @ObservationIgnored private var lastKeyboardEventDescription: String?
    @ObservationIgnored private var lastRecognizedAction: String?
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
        guard hasAccessibilityPermission else {
            if GlobalHotkeyStatusPolicy.shouldStopHoldRecording(
                accessibilityGranted: hasAccessibilityPermission,
                holdRecordingActive: isHoldRecordingActive
            ) {
                stopActiveHoldIfNeeded()
            }
            removeMonitors()
            isEnabled = false
            resetRecognizers()
            refreshStatusMessage()
            return
        }

        let previouslyEnabled = GlobalHotkeyStatusPolicy.storedEnabledPreference(in: defaults)
        if GlobalHotkeyStatusPolicy.shouldActivateListener(
            accessibilityGranted: hasAccessibilityPermission,
            previouslyEnabled: previouslyEnabled
        ), !isEnabled {
            installMonitors()
        } else {
            refreshStatusMessage()
        }
    }

    func openAccessibilitySettings() {
        if !AXIsProcessTrusted() {
            let promptKey = "AXTrustedCheckOptionPrompt"
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Saves the user's opt-in before prompting for permission, then restores monitoring on return/next launch.
    func requestEnable() {
        GlobalHotkeyStatusPolicy.setEnabledPreference(true, in: defaults)
        refreshPermission()
        if !hasAccessibilityPermission {
            openAccessibilitySettings()
        }
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
        GlobalHotkeyStatusPolicy.setEnabledPreference(true, in: defaults)
        refreshPermission()
    }

    private func installMonitors() {
        guard hasAccessibilityPermission, !isEnabled else { return }
        receivedKeyboardEventCount = 0
        lastKeyboardEventDescription = nil
        lastRecognizedAction = nil

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
                self?.handle(input, source: "another app")
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
                self?.handle(input, source: "EchoType")
            }
            return event
        }

        guard globalMonitor != nil else {
            removeMonitors()
            isEnabled = false
            lastKeyboardEventDescription = "Global keyboard listener registration failed; choose Enable Hotkey to retry."
            refreshStatusMessage()
            return
        }
        isEnabled = true
        refreshStatusMessage()
    }

    func disable() {
        GlobalHotkeyStatusPolicy.setEnabledPreference(false, in: defaults)
        removeMonitors()
        isEnabled = false
        stopActiveHoldIfNeeded()
        resetRecognizers()
        lastRecognizedAction = nil
        refreshStatusMessage()
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func refreshStatusMessage() {
        statusMessage = GlobalHotkeyStatusPolicy.message(
            accessibilityGranted: hasAccessibilityPermission,
            hotkeyEnabledPreference: GlobalHotkeyStatusPolicy.storedEnabledPreference(in: defaults) ?? true,
            globalMonitorInstalled: globalMonitor != nil,
            receivedEventCount: receivedKeyboardEventCount,
            configuredHotkey: "\(selectedKeyName) (\(selectedMode == .tapToToggle ? "tap to toggle" : "hold to talk"))",
            lastEventDescription: lastKeyboardEventDescription,
            lastRecognizedAction: lastRecognizedAction
        )
    }

    private func handle(_ event: GlobalHotkeyInputEvent, source: String) {
        guard isEnabled else { return }
        receivedKeyboardEventCount += 1
        lastKeyboardEventDescription = "\(event.diagnosticLabel) from \(source)"
        lastRecognizedAction = nil
        switch event {
        case let .flagsChanged(keyCode, modifierFlags):
            guard case let .modifierKey(selectedKeyCode) = selectedHotkey,
                  keyCode == selectedKeyCode else { break }
            let flags = NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
            let targetModifier = Self.modifierFlag(for: selectedKeyCode)
            let hasOtherModifiers = !flags.subtracting(targetModifier).intersection(Self.relevantModifiers).isEmpty
            let isDown = flags.contains(targetModifier)
            dispatch(recognizer.consume(.modifierChanged(isDown: isDown, hasOtherModifiers: hasOtherModifiers)))

        case let .keyDown(keyCode, modifierFlags, isRepeat):
            dispatch(recognizer.consume(.otherKeyDown))
            guard var shortcutRecognizer else { break }
            let flags = Self.shortcutModifierFlags(
                from: NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
            )
            let action = shortcutRecognizer.consume(.keyDown(keyCode: keyCode, modifierFlags: flags, isRepeat: isRepeat))
            self.shortcutRecognizer = shortcutRecognizer
            dispatch(action)

        case let .keyUp(keyCode):
            guard var shortcutRecognizer else { break }
            let action = shortcutRecognizer.consume(.keyUp(keyCode: keyCode))
            self.shortcutRecognizer = shortcutRecognizer
            dispatch(action)
        }
        refreshStatusMessage()
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
        refreshStatusMessage()
    }

    private func stopActiveHoldIfNeeded() {
        guard isHoldRecordingActive else { return }
        isHoldRecordingActive = false
        onStopRecording?()
    }

    private func dispatch(_ action: ModifierHotkeyAction?) {
        switch action {
        case .toggleRecording:
            lastRecognizedAction = "toggle dictation"
            onToggleRecording?()
        case .startRecording:
            lastRecognizedAction = "start dictation"
            isHoldRecordingActive = true
            onStartRecording?()
        case .stopRecording:
            lastRecognizedAction = "stop dictation"
            isHoldRecordingActive = false
            onStopRecording?()
        case nil:
            break
        }
        refreshStatusMessage()
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
