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

    private struct CorrectionInsertionContext {
        let scope: InsertedTextCorrectionScope
        let originalFieldCharacterCount: Int
        let originalSelection: InsertedTextCorrectionRange
    }

    private struct PendingCorrectionSelection {
        let candidate: InsertedTextCorrectionCandidate
        let generation: UInt64
    }

    private struct CorrectionObservationSession {
        let target: CapturedInsertionTarget
        let scope: InsertedTextCorrectionScope
        let deadline: ContinuousClock.Instant
        var pendingSelection: PendingCorrectionSelection?
        var selectionGeneration: UInt64 = 0
    }

    private let defaults: UserDefaults
    private var correctionSession: CorrectionObservationSession?
    private var correctionObserver: AXObserver?
    private var correctionRunLoopSource: CFRunLoopSource?
    private var correctionObserverRetain: Unmanaged<TextInsertionService>?
    private var correctionLifetimeTask: Task<Void, Never>?
    private var correctionDebounceTask: Task<Void, Never>?

    static let correctionLearningPreferenceKey = "EchoType.learnRecentInsertionCorrections"

    var onTranscriptCorrection: ((String, String) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func captureTarget() -> CapturedInsertionTarget? {
        captureFocusedTarget()
    }

    func isFrontmostAppExcluded() -> Bool {
        currentPolicy.isExcluded(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    func setCorrectionLearningEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.correctionLearningPreferenceKey)
        if !enabled { stopCorrectionObservation() }
    }

    func cancelCorrectionObservationIfTargetIsInvalid() {
        guard let session = correctionSession else { return }
        guard isCorrectionObservationOpen(session), isCorrectionTargetValid(session.target) else {
            stopCorrectionObservation()
            return
        }
    }

    func deliver(
        _ text: String,
        capturedTarget: CapturedInsertionTarget?,
        copyToClipboard: Bool,
        autoSend: Bool
    ) async -> Outcome {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return .failed }

        stopCorrectionObservation()

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

        let correctionInsertion = defaults.bool(forKey: Self.correctionLearningPreferenceKey)
            ? correctionInsertionContext(for: cleanText, target: current)
            : nil

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

        let correctionDeadline = ContinuousClock().now.advanced(by: .seconds(10))
        if let correctionInsertion, let current {
            try? await Task.sleep(for: .milliseconds(100))
            startCorrectionObservation(
                correctionInsertion,
                target: current,
                deadline: correctionDeadline
            )
        }

        var submitted = false
        if autoSend {
            try? await Task.sleep(for: .milliseconds(140))
            if sameTargetIsStillFocused(captured) {
                submitted = postKey(virtualKey: 36, command: false)
            }
        }
        if submitted { stopCorrectionObservation() }

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

    private func correctionInsertionContext(
        for text: String,
        target: CapturedInsertionTarget?
    ) -> CorrectionInsertionContext? {
        guard let target,
              isCorrectionTargetValid(target),
              let selection = accessibilityRange(kAXSelectedTextRangeAttribute, of: target.focusedElement),
              let fieldCharacterCount = accessibilityCharacterCount(of: target.focusedElement),
              let selectionEnd = selection.upperBound,
              selectionEnd <= fieldCharacterCount,
              let scope = InsertedTextCorrectionScope(
                insertedText: text,
                insertionLocation: selection.location
              ) else {
            return nil
        }
        return CorrectionInsertionContext(
            scope: scope,
            originalFieldCharacterCount: fieldCharacterCount,
            originalSelection: selection
        )
    }

    private func startCorrectionObservation(
        _ insertion: CorrectionInsertionContext,
        target: CapturedInsertionTarget,
        deadline: ContinuousClock.Instant
    ) {
        guard defaults.bool(forKey: Self.correctionLearningPreferenceKey),
              ContinuousClock().now < deadline,
              isCorrectionTargetValid(target),
              let postInsertionCount = accessibilityCharacterCount(of: target.focusedElement),
              let postInsertionSelection = accessibilityRange(
                kAXSelectedTextRangeAttribute,
                of: target.focusedElement
              ),
              postInsertionSelection.length == 0 else {
            return
        }

        let (remainingCharacterCount, subtractionOverflow) = insertion.originalFieldCharacterCount
            .subtractingReportingOverflow(insertion.originalSelection.length)
        let (expectedCharacterCount, additionOverflow) = remainingCharacterCount
            .addingReportingOverflow(insertion.scope.insertedText.utf16.count)
        let (expectedCaretLocation, caretOverflow) = insertion.scope.insertionLocation
            .addingReportingOverflow(insertion.scope.insertedText.utf16.count)
        guard !subtractionOverflow,
              !additionOverflow,
              !caretOverflow,
              postInsertionCount == expectedCharacterCount,
              postInsertionSelection.location == expectedCaretLocation,
              let insertedRange = InsertedTextCorrectionRange(
                location: insertion.scope.insertionLocation,
                length: insertion.scope.insertedText.utf16.count
              ),
              let insertedCandidate = insertion.scope.candidate(
                for: insertedRange,
                fieldCharacterCount: postInsertionCount
              ),
              insertedCandidate.originalText == insertion.scope.insertedText else {
            return
        }

        // Keep the C callback target alive until notifications and the run-loop source are removed.
        let retainedService = Unmanaged.passRetained(self)
        var observer: AXObserver?
        guard AXObserverCreate(target.snapshot.processIdentifier, echoTypeCorrectionObserverCallback, &observer)
                == .success,
              let observer else {
            retainedService.release()
            return
        }

        let context = retainedService.toOpaque()
        guard AXObserverAddNotification(
            observer,
            target.focusedElement,
            kAXSelectedTextChangedNotification as CFString,
            context
        ) == .success else {
            retainedService.release()
            return
        }
        guard AXObserverAddNotification(
            observer,
            target.focusedElement,
            kAXValueChangedNotification as CFString,
            context
        ) == .success else {
            _ = AXObserverRemoveNotification(
                observer,
                target.focusedElement,
                kAXSelectedTextChangedNotification as CFString
            )
            retainedService.release()
            return
        }

        correctionSession = CorrectionObservationSession(
            target: target,
            scope: insertion.scope,
            deadline: deadline
        )
        correctionObserver = observer
        correctionObserverRetain = retainedService
        let source = AXObserverGetRunLoopSource(observer)
        correctionRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        startCorrectionLifetimeTask(deadline: deadline)
    }

    fileprivate func receiveCorrectionAXNotification(element: AXUIElement, notification: CFString) {
        guard var session = correctionSession else { return }
        guard isCorrectionObservationOpen(session) else {
            stopCorrectionObservation()
            return
        }
        guard CFEqual(element, session.target.focusedElement),
              isCorrectionTargetValid(session.target) else {
            stopCorrectionObservation()
            return
        }

        if (notification as String) == (kAXSelectedTextChangedNotification as String) {
            guard let selection = accessibilityRange(kAXSelectedTextRangeAttribute, of: element),
                  let fieldCharacterCount = accessibilityCharacterCount(of: element) else {
                stopCorrectionObservation()
                return
            }

            session.selectionGeneration &+= 1
            if selection.length == 0 {
                if correctionDebounceTask == nil {
                    session.pendingSelection = nil
                }
                correctionSession = session
                return
            }

            guard let candidate = session.scope.candidate(
                for: selection,
                fieldCharacterCount: fieldCharacterCount
            ) else {
                correctionDebounceTask?.cancel()
                correctionDebounceTask = nil
                session.pendingSelection = nil
                correctionSession = session
                return
            }

            correctionDebounceTask?.cancel()
            correctionDebounceTask = nil
            session.pendingSelection = PendingCorrectionSelection(
                candidate: candidate,
                generation: session.selectionGeneration
            )
            correctionSession = session
            return
        }

        guard (notification as String) == (kAXValueChangedNotification as String),
              let pendingSelection = session.pendingSelection else {
            return
        }
        correctionDebounceTask?.cancel()
        let generation = pendingSelection.generation
        correctionDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.attemptCorrection(generation: generation)
        }
    }

    private func attemptCorrection(generation: UInt64) {
        correctionDebounceTask = nil
        guard var session = correctionSession,
              let pendingSelection = session.pendingSelection,
              pendingSelection.generation == generation else {
            return
        }
        guard isCorrectionObservationOpen(session) else {
            stopCorrectionObservation()
            return
        }

        session.pendingSelection = nil
        correctionSession = session
        let target = session.target
        guard isCorrectionTargetValid(target),
              let fieldCharacterCount = accessibilityCharacterCount(of: target.focusedElement),
              let caret = accessibilityRange(kAXSelectedTextRangeAttribute, of: target.focusedElement) else {
            stopCorrectionObservation()
            return
        }
        guard caret.length == 0,
              let replacementRange = session.scope.replacementRange(
                for: pendingSelection.candidate,
                currentFieldCharacterCount: fieldCharacterCount,
                caretLocation: caret.location
              ),
              session.scope.candidate(
                for: replacementRange,
                fieldCharacterCount: fieldCharacterCount
              ) != nil,
              isCorrectionTargetValid(target),
              let correctedText = accessibilityString(
                for: replacementRange,
                of: target.focusedElement
              ),
              (correctedText as NSString).length == replacementRange.length,
              isCorrectionObservationOpen(session),
              isCorrectionTargetValid(target) else {
            return
        }

        let corrections = TranscriptCorrectionExtractor.extract(
            from: pendingSelection.candidate.originalText,
            to: correctedText
        )
        for correction in corrections {
            guard let activeSession = correctionSession,
                  isCorrectionObservationOpen(activeSession),
                  isCorrectionTargetValid(target) else {
                stopCorrectionObservation()
                return
            }
            onTranscriptCorrection?(correction.original, correction.replacement)
        }
    }

    private func isCorrectionObservationOpen(_ session: CorrectionObservationSession) -> Bool {
        CorrectionObservationDeadlinePolicy.isOpen(deadline: session.deadline, now: ContinuousClock().now)
    }

    private func startCorrectionLifetimeTask(deadline: ContinuousClock.Instant) {
        correctionLifetimeTask?.cancel()
        correctionLifetimeTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled, clock.now < deadline {
                guard let self else { return }
                guard self.isCorrectionTargetValid() else {
                    self.stopCorrectionObservation()
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            self?.stopCorrectionObservation()
        }
    }

    private func isCorrectionTargetValid(_ target: CapturedInsertionTarget? = nil) -> Bool {
        guard defaults.bool(forKey: Self.correctionLearningPreferenceKey),
              AXIsProcessTrusted(),
              let expectedTarget = target ?? correctionSession?.target,
              let expectedBundleIdentifier = expectedTarget.snapshot.bundleIdentifier,
              let application = NSWorkspace.shared.frontmostApplication,
              let applicationBundleIdentifier = application.bundleIdentifier,
              application.processIdentifier == expectedTarget.snapshot.processIdentifier,
              applicationBundleIdentifier == expectedBundleIdentifier,
              !currentPolicy.isExcluded(bundleIdentifier: applicationBundleIdentifier),
              let current = captureFocusedTarget(),
              CFEqual(expectedTarget.focusedElement, current.focusedElement),
              current.snapshot.processIdentifier == expectedTarget.snapshot.processIdentifier,
              current.snapshot.bundleIdentifier == expectedBundleIdentifier,
              let role = current.snapshot.focusedRole,
              let subrole = current.snapshot.focusedSubrole,
              ["AXTextField", "AXTextArea", "AXSearchField"].contains(role),
              role != "AXSecureTextField",
              subrole != "AXSecureTextField",
              !currentPolicy.isExcluded(bundleIdentifier: current.snapshot.bundleIdentifier) else {
            return false
        }
        return true
    }

    private func stopCorrectionObservation() {
        correctionDebounceTask?.cancel()
        correctionDebounceTask = nil
        correctionLifetimeTask?.cancel()
        correctionLifetimeTask = nil

        let session = correctionSession
        correctionSession = nil
        if let observer = correctionObserver, let element = session?.target.focusedElement {
            _ = AXObserverRemoveNotification(
                observer,
                element,
                kAXSelectedTextChangedNotification as CFString
            )
            _ = AXObserverRemoveNotification(
                observer,
                element,
                kAXValueChangedNotification as CFString
            )
        }
        if let source = correctionRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        correctionObserver = nil
        correctionRunLoopSource = nil
        correctionObserverRetain?.release()
        correctionObserverRetain = nil
    }

    private func captureFocusedTarget() -> CapturedInsertionTarget? {
        guard AXIsProcessTrusted(),
              let application = NSWorkspace.shared.frontmostApplication else { return nil }

        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else { return nil }
        let focusedElement = focusedValue as! AXUIElement

        let role = accessibilityAttributeString(kAXRoleAttribute, of: focusedElement)
        let subrole = accessibilityAttributeString(kAXSubroleAttribute, of: focusedElement)
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

    private func accessibilityAttributeString(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func accessibilityRange(
        _ attribute: String,
        of element: AXUIElement
    ) -> InsertedTextCorrectionRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID(),
              let axValue = value as? AXValue,
              AXValueGetType(axValue) == .cfRange else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return InsertedTextCorrectionRange(location: range.location, length: range.length)
    }

    private func accessibilityCharacterCount(of element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXNumberOfCharactersAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == CFNumberGetTypeID(),
              let number = value as? NSNumber else {
            return nil
        }
        let count = number.intValue
        return count >= 0 ? count : nil
    }

    private func accessibilityString(
        for range: InsertedTextCorrectionRange,
        of element: AXUIElement
    ) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            parameter,
            &value
        ) == .success,
              let value else {
            return nil
        }
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

private func echoTypeCorrectionObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard Thread.isMainThread, let refcon else { return }
    let service = Unmanaged<TextInsertionService>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        service.receiveCorrectionAXNotification(element: element, notification: notification)
    }
}
