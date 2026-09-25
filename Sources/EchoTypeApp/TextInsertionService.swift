import AppKit
import ApplicationServices
import CoreGraphics
import EchoTypeCore
import Foundation

@MainActor
final class CapturedInsertionTarget {
    let snapshot: TextInsertionSnapshot
    let focusedElement: AXUIElement

    init(snapshot: TextInsertionSnapshot, focusedElement: AXUIElement) {
        self.snapshot = snapshot
        self.focusedElement = focusedElement
    }
}

@MainActor
final class TextInsertionService {
    enum Outcome {
        case inserted
        case insertedAndSubmitted
        case copyOnly(TextInsertionBlockReason)
        case failed
    }

    private struct ClipboardItemSnapshot {
        let representations: [(NSPasteboard.PasteboardType, Data)]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func captureTarget() -> CapturedInsertionTarget? {
        captureFocusedTarget()
    }

    func isFrontmostAppExcluded() -> Bool {
        currentPolicy.isExcluded(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    func deliver(
        _ text: String,
        capturedTarget: CapturedInsertionTarget?,
        copyToClipboard: Bool,
        autoSend: Bool
    ) async -> Outcome {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return .failed }

        let captured = capturedTarget
        let current = captureFocusedTarget()
        let sameFocusedElement = if let captured, let current {
            CFEqual(captured.focusedElement, current.focusedElement)
        } else {
            false
        }
        let policy = currentPolicy
        let decision = policy.decision(
            captured: captured?.snapshot,
            current: current?.snapshot,
            sameFocusedElement: sameFocusedElement
        )

        guard case .insert = decision else {
            if copyToClipboard {
                _ = writeTextToClipboard(cleanText)
            }
            if case let .copyOnly(reason) = decision { return .copyOnly(reason) }
            return .failed
        }

        let pasteboard = NSPasteboard.general
        let previousClipboard = snapshotClipboard(pasteboard)
        guard writeTextToClipboard(cleanText) else {
            restoreClipboard(previousClipboard, to: pasteboard)
            return .failed
        }
        let insertedClipboardChangeCount = pasteboard.changeCount
        guard postKey(virtualKey: 9, command: true) else {
            if !copyToClipboard {
                restoreClipboard(previousClipboard, to: pasteboard)
            }
            return .failed
        }

        var submitted = false
        if autoSend {
            try? await Task.sleep(for: .milliseconds(140))
            if sameTargetIsStillFocused(captured) {
                submitted = postKey(virtualKey: 36, command: false)
            }
        }

        if !copyToClipboard {
            try? await Task.sleep(for: .milliseconds(550))
            if pasteboard.changeCount == insertedClipboardChangeCount {
                restoreClipboard(previousClipboard, to: pasteboard)
            }
        }
        return submitted ? .insertedAndSubmitted : .inserted
    }

    private func sameTargetIsStillFocused(_ captured: CapturedInsertionTarget?) -> Bool {
        guard let captured, let current = captureFocusedTarget() else { return false }
        guard CFEqual(captured.focusedElement, current.focusedElement) else { return false }
        return currentPolicy.decision(
            captured: captured.snapshot,
            current: current.snapshot,
            sameFocusedElement: true
        ) == .insert
    }

    private func captureFocusedTarget() -> CapturedInsertionTarget? {
        guard AXIsProcessTrusted(),
              let application = NSWorkspace.shared.frontmostApplication else { return nil }

        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else { return nil }
        let focusedElement = focusedValue as! AXUIElement

        let role = accessibilityString(kAXRoleAttribute, of: focusedElement)
        let subrole = accessibilityString(kAXSubroleAttribute, of: focusedElement)
        let snapshot = TextInsertionSnapshot(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            focusedRole: role,
            focusedSubrole: subrole
        )
        return CapturedInsertionTarget(snapshot: snapshot, focusedElement: focusedElement)
    }

    private var currentPolicy: TextInsertionPolicy {
        guard let data = defaults.data(forKey: ExcludedApplicationsViewModel.defaultsKey),
              let policy = try? JSONDecoder().decode(ExcludedAppPolicy.self, from: data) else {
            return TextInsertionPolicy()
        }
        let identifiers = Set(
            (policy.defaultExcludedApplications + policy.userExcludedApplications)
                .map(\.bundleIdentifier)
        )
        return TextInsertionPolicy(excludedBundleIdentifiers: identifiers)
    }

    private func accessibilityString(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func writeTextToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func snapshotClipboard(_ pasteboard: NSPasteboard) -> [ClipboardItemSnapshot] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let representations = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return ClipboardItemSnapshot(representations: representations)
        }
    }

    private func restoreClipboard(_ snapshots: [ClipboardItemSnapshot], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshots.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshots.map { snapshot in
            let item = NSPasteboardItem()
            for (type, data) in snapshot.representations {
                item.setData(data, forType: type)
            }
            return item
        }
        _ = pasteboard.writeObjects(items)
    }

    private func postKey(virtualKey: CGKeyCode, command: Bool) -> Bool {
        guard AXIsProcessTrusted(),
              let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            return false
        }
        if command {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
