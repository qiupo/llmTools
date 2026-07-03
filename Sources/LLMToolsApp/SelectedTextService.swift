import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
enum SelectedTextService {
    private static var lastCapturedSourceProcessIdentifier: pid_t?
    private static var lastUserCopyShortcutDate = Date.distantPast
    private static let syntheticShortcutEventMarker: Int64 = 0x4C4C_4D54
    private static let nonTextPayloadTypeFragments = [
        "image",
        "png",
        "tiff",
        "jpeg",
        "pdf",
        "file-url",
        "filepromise",
        "file promise",
        "urlnodedata"
    ]

    private struct PasteboardSnapshot {
        struct Item {
            let contents: [(type: NSPasteboard.PasteboardType, data: Data)]
        }

        let items: [Item]

        static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
            let items: [Item] = pasteboard.pasteboardItems?.map { item in
                let contents = item.types.compactMap { type -> (type: NSPasteboard.PasteboardType, data: Data)? in
                    guard let data = item.data(forType: type) else {
                        return nil
                    }
                    return (type, data)
                }
                return Item(contents: contents)
            } ?? []
            return PasteboardSnapshot(items: items)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            let restoredItems = items.map { item in
                let pasteboardItem = NSPasteboardItem()
                for content in item.contents {
                    pasteboardItem.setData(content.data, forType: content.type)
                }
                return pasteboardItem
            }
            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            }
        }
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func captureSelectedText(
        near screenPoint: NSPoint? = nil,
        preserveNonTextClipboardPayloads: Bool = true
    ) async -> String? {
        guard isAccessibilityTrusted else {
            requestAccessibilityPermission()
            return nil
        }

        let sourceProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let accessibilityText = captureSelectedTextFromAccessibility(near: screenPoint) {
            lastCapturedSourceProcessIdentifier = sourceProcessIdentifier
            return accessibilityText
        }

        let pasteboard = NSPasteboard.general
        let originalSnapshot = PasteboardSnapshot.capture(from: pasteboard)
        let marker = "llmTools-\(UUID().uuidString)"
        let captureStartedAt = Date()

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        sendCopyShortcut()
        try? await Task.sleep(nanoseconds: 120_000_000)

        let hasNonTextPayload = preserveNonTextClipboardPayloads && pasteboardContainsNonTextPayload(pasteboard)
        let copied = hasNonTextPayload ? nil : pasteboard.string(forType: .string)
        if lastUserCopyShortcutDate < captureStartedAt {
            if !hasNonTextPayload {
                originalSnapshot.restore(to: pasteboard)
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

    private static func captureSelectedTextFromAccessibility(near screenPoint: NSPoint?) -> String? {
        selectedText(in: accessibilityCandidateElements(near: screenPoint))
    }

    private static func accessibilityCandidateElements(near screenPoint: NSPoint?) -> [AXUIElement] {
        var candidates = focusedAccessibilityCandidateElements()
        if let screenPoint,
           let hitElement = elementAtScreenPoint(screenPoint) {
            appendElementAndParents(hitElement, to: &candidates)
        }

        return candidates
    }

    private static func focusedAccessibilityCandidateElements() -> [AXUIElement] {
        let systemWideElement = AXUIElementCreateSystemWide()
        var candidates: [AXUIElement] = []
        if let focusedElement = attributeElement(kAXFocusedUIElementAttribute, from: systemWideElement) {
            appendElementAndParents(focusedElement, to: &candidates)
        }
        return candidates
    }

    private static func appendElementAndParents(_ element: AXUIElement, to candidates: inout [AXUIElement]) {
        var current: AXUIElement? = element
        var depth = 0
        while let element = current, depth < 5 {
            candidates.append(element)
            current = attributeElement(kAXParentAttribute, from: element)
            depth += 1
        }
    }

    private static func elementAtScreenPoint(_ screenPoint: NSPoint) -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(screenPoint.x),
            Float(screenPoint.y),
            &element
        )
        guard result == .success else {
            return nil
        }
        return element
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        guard let value = attributeValue(kAXSelectedTextAttribute, from: element) else {
            return nil
        }
        let text: String?
        if let string = value as? String {
            text = string
        } else if let attributedString = value as? NSAttributedString {
            text = attributedString.string
        } else {
            text = nil
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return text
    }

    private static func selectedText(in candidates: [AXUIElement]) -> String? {
        for element in candidates {
            if let selectedText = selectedText(from: element) {
                return selectedText
            }
        }
        return nil
    }

    private static func attributeElement(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        attributeValue(attribute, from: element) as! AXUIElement?
    }

    private static func attributeValue(_ attribute: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private static func pasteboardContainsNonTextPayload(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.pasteboardItems?.flatMap(\.types) ?? pasteboard.types ?? []
        return types.contains { type in
            let rawValue = type.rawValue.lowercased()
            return nonTextPayloadTypeFragments.contains { rawValue.contains($0) }
        }
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
