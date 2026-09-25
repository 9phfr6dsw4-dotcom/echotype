import AppKit
import ApplicationServices
import EchoTypeCore
import Observation

@MainActor
@Observable
final class GlobalHotkeyController {
    private(set) var isEnabled = false
    private(set) var hasAccessibilityPermission = AXIsProcessTrusted()
    private(set) var statusMessage = "Enable the global hotkey to dictate from any app."
    private(set) var selectedKeyCode: UInt16

    var onToggleRecording: (@MainActor () -> Void)?

    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var recognizer = ModifierTapRecognizer()
    @ObservationIgnored private let defaults: UserDefaults

    private static let keyCodeDefaultsKey = "EchoType.globalHotkeyKeyCode"
    private static let controlKeyCode: UInt16 = 59
    private static let rightOptionKeyCode: UInt16 = 61
    private static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedKeyCode = UInt16(defaults.integer(forKey: Self.keyCodeDefaultsKey))
        if defaults.object(forKey: Self.keyCodeDefaultsKey) == nil {
            selectedKeyCode = Self.controlKeyCode
        }
        if selectedKeyCode != Self.controlKeyCode && selectedKeyCode != Self.rightOptionKeyCode {
            selectedKeyCode = Self.controlKeyCode
        }
    }

    var selectedKeyName: String {
        selectedKeyCode == Self.rightOptionKeyCode ? "Right Option" : "Left Control"
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
        guard keyCode == Self.controlKeyCode || keyCode == Self.rightOptionKeyCode else { return }
        selectedKeyCode = keyCode
        defaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        recognizer = ModifierTapRecognizer()
    }

    func enable() {
        refreshPermission()
        guard hasAccessibilityPermission else { return }
        guard !isEnabled else { return }

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let isModifierChange = event.type == .flagsChanged
            let keyCode = isModifierChange ? event.keyCode : 0
            let flags = isModifierChange ? event.modifierFlags.rawValue : 0
            Task { @MainActor [weak self] in
                self?.handle(isModifierChange: isModifierChange, keyCode: keyCode, modifierFlags: flags)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let isModifierChange = event.type == .flagsChanged
            let keyCode = isModifierChange ? event.keyCode : 0
            let flags = isModifierChange ? event.modifierFlags.rawValue : 0
            Task { @MainActor [weak self] in
                self?.handle(isModifierChange: isModifierChange, keyCode: keyCode, modifierFlags: flags)
            }
            return event
        }

        guard globalMonitor != nil || localMonitor != nil else {
            statusMessage = "macOS did not allow the keyboard monitor to start. Check Accessibility permission."
            return
        }
        isEnabled = true
        statusMessage = "Listening for a bare \(selectedKeyName) tap. Key combinations such as Control-C are ignored."
    }

    func disable() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isEnabled = false
        recognizer = ModifierTapRecognizer()
        statusMessage = "Global hotkey is off."
    }

    private func handle(isModifierChange: Bool, keyCode: UInt16, modifierFlags: UInt) {
        guard isEnabled else { return }
        guard isModifierChange else {
            _ = recognizer.consume(.otherKeyDown)
            return
        }
        guard keyCode == selectedKeyCode else { return }

        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
        let targetModifier: NSEvent.ModifierFlags = selectedKeyCode == Self.controlKeyCode ? .control : .option
        let hasOtherModifiers = !flags.subtracting(targetModifier).intersection(Self.relevantModifiers).isEmpty
        let isDown = flags.contains(targetModifier)
        if recognizer.consume(.modifierChanged(isDown: isDown, hasOtherModifiers: hasOtherModifiers)) == .toggleRecording {
            onToggleRecording?()
        }
    }
}
