import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
enum SelectedTextService {
    private static var lastCapturedSourceProcessIdentifier: pid_t?
    private static var lastUserCopyShortcutDate = Date.distantPast
    private static let syntheticShortcutEventMarker: Int64 = 0x4C4C_4D54

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func captureSelectedText() async -> String? {
        guard isAccessibilityTrusted else {
            requestAccessibilityPermission()
            return nil
        }

        let sourceProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        let marker = "llmTools-\(UUID().uuidString)"
        let captureStartedAt = Date()

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        sendCopyShortcut()
        try? await Task.sleep(nanoseconds: 120_000_000)

        let copied = pasteboard.string(forType: .string)
        if lastUserCopyShortcutDate < captureStartedAt {
            if let originalString {
                pasteboard.clearContents()
                pasteboard.setString(originalString, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        let trimmed = copied?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, trimmed != marker else {
            return nil
        }
        lastCapturedSourceProcessIdentifier = sourceProcessIdentifier
        return copied
    }

    static func clearCapturedSelectionSource() {
        lastCapturedSourceProcessIdentifier = nil
    }

    static func isSyntheticShortcutEvent(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == syntheticShortcutEventMarker
    }

    static func noteUserCopyShortcut() {
        lastUserCopyShortcutDate = Date()
    }

    static func replaceSelectedText(with text: String) async -> Bool {
        guard isAccessibilityTrusted else {
            return false
        }

        guard let sourceProcessIdentifier = lastCapturedSourceProcessIdentifier,
              let sourceApplication = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == sourceProcessIdentifier }) else {
            return false
        }

        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)

        NSApp.yieldActivation(to: sourceApplication)
        sourceApplication.activate(from: .current, options: [])
        try? await Task.sleep(nanoseconds: 120_000_000)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendPasteShortcut()
        try? await Task.sleep(nanoseconds: 120_000_000)

        if let originalString {
            pasteboard.clearContents()
            pasteboard.setString(originalString, forType: .string)
        } else {
            pasteboard.clearContents()
        }

        clearCapturedSelectionSource()

        return true
    }

    private static func sendCopyShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticShortcutEventMarker)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticShortcutEventMarker)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func sendPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticShortcutEventMarker)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticShortcutEventMarker)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
