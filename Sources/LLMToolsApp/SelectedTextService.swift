import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
enum SelectedTextService {
    private struct CapturedAccessibilitySelection {
        let id: UUID
        let processIdentifier: pid_t
        let element: AXUIElement
        let range: CFRange
        let text: String
    }

    private struct AccessibilitySelection {
        let processIdentifier: pid_t
        let element: AXUIElement
        let range: CFRange
        let text: String
    }

    private static var lastCapturedAccessibilitySelection: CapturedAccessibilitySelection?
    private static var captureRevision = 0
    private static var clipboardCaptureOwner: UUID?
    private static var pasteboardOwnershipEventMonitor: Any?
    private static var lastUserInteractionDate = Date.distantPast
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

    static func startMonitoringPasteboardOwnershipEvents() {
        guard pasteboardOwnershipEventMonitor == nil else {
            return
        }
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        // 此监听独立于划词功能生命周期，菜单复制、右键和快捷键都会让内部捕获失去剪贴板所有权。
        pasteboardOwnershipEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            let observedAt = Date()
            Task { @MainActor in
                guard !isSyntheticShortcutEvent(event) else {
                    return
                }
                lastUserInteractionDate = observedAt
                guard event.type == .keyDown,
                      event.charactersIgnoringModifiers?.lowercased() == "c" else {
                    return
                }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags.contains(.command),
                      flags.intersection([.control, .option, .shift]).isEmpty else {
                    return
                }
                noteUserCopyShortcut()
            }
        }
    }

    static func stopMonitoringPasteboardOwnershipEvents() {
        if let pasteboardOwnershipEventMonitor {
            NSEvent.removeMonitor(pasteboardOwnershipEventMonitor)
            self.pasteboardOwnershipEventMonitor = nil
        }
    }

    static func captureSelectedText(
        near screenPoint: NSPoint? = nil,
        preserveNonTextClipboardPayloads: Bool = true
    ) async -> String? {
        guard isAccessibilityTrusted else {
            requestAccessibilityPermission()
            return nil
        }

        captureRevision += 1
        let revision = captureRevision
        lastCapturedAccessibilitySelection = nil
        if let selection = captureSelectedTextFromAccessibility(near: screenPoint) {
            lastCapturedAccessibilitySelection = CapturedAccessibilitySelection(
                id: UUID(),
                processIdentifier: selection.processIdentifier,
                element: selection.element,
                range: selection.range,
                text: selection.text
            )
            return selection.text
        }

        // Cmd+C 回退是进程级剪贴板操作，必须串行；后来的捕获等待当前 owner 完成恢复。
        while clipboardCaptureOwner != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
            guard !Task.isCancelled, revision == captureRevision else {
                return nil
            }
        }
        let owner = UUID()
        clipboardCaptureOwner = owner
        defer {
            if clipboardCaptureOwner == owner {
                clipboardCaptureOwner = nil
            }
        }

        let pasteboard = NSPasteboard.general
        let originalSnapshot = PasteboardSnapshot.capture(from: pasteboard)
        let marker = "llmTools-\(UUID().uuidString)"
        let captureStartedAt = Date()

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        let markerChangeCount = pasteboard.changeCount
        sendCopyShortcut()
        await waitForSyntheticCopy()

        // changeCount 记录合成复制完成后的所有权；恢复前若再次变化，说明用户或其他程序已写入新内容。
        let capturedChangeCount = pasteboard.changeCount
        let hasNonTextPayload = preserveNonTextClipboardPayloads && pasteboardContainsNonTextPayload(pasteboard)
        let copied = hasNonTextPayload ? nil : pasteboard.string(forType: .string)
        let userCopiedDuringCapture = lastUserCopyShortcutDate >= captureStartedAt
        let userInteractedDuringCapture = lastUserInteractionDate >= captureStartedAt
        let changeCountDelta = capturedChangeCount >= markerChangeCount
            ? capturedChangeCount - markerChangeCount
            : Int.max
        let markerStillOwned = changeCountDelta == 0 && copied == marker
        let syntheticCopyStillOwned = changeCountDelta == 1 && copied != marker
        await yieldPasteboardOwnershipCheck()
        let pasteboardStillOwned = pasteboard.changeCount == capturedChangeCount
            && (markerStillOwned || syntheticCopyStillOwned)
        if !userCopiedDuringCapture,
           !userInteractedDuringCapture,
           pasteboardStillOwned,
           !hasNonTextPayload {
            originalSnapshot.restore(to: pasteboard)
        }
        // 等待期间用户主动复制的内容属于用户，不得被当成本次选区捕获结果继续处理。
        guard !userCopiedDuringCapture,
              !userInteractedDuringCapture,
              pasteboardStillOwned,
              !Task.isCancelled,
              revision == captureRevision else {
            return nil
        }

        let trimmed = copied?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, trimmed != marker else {
            return nil
        }
        // Cmd+C 回退只能读取文本，无法可靠标识原选区，因此禁止后续自动替换原文。
        lastCapturedAccessibilitySelection = nil
        return copied
    }

    static func clearCapturedSelectionSource() {
        captureRevision += 1
        lastCapturedAccessibilitySelection = nil
    }

    static var currentCapturedSelectionID: UUID? {
        lastCapturedAccessibilitySelection?.id
    }

    static func isSyntheticShortcutEvent(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == syntheticShortcutEventMarker
    }

    static func noteUserCopyShortcut() {
        lastUserCopyShortcutDate = Date()
    }

    private static func captureSelectedTextFromAccessibility(near screenPoint: NSPoint?) -> AccessibilitySelection? {
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

    private static func selectedText(in candidates: [AXUIElement]) -> AccessibilitySelection? {
        for element in candidates {
            guard let selectedText = selectedText(from: element),
                  let selectedRange = selectedRange(from: element) else {
                continue
            }
            var processIdentifier: pid_t = 0
            guard AXUIElementGetPid(element, &processIdentifier) == .success,
                  processIdentifier > 0 else {
                continue
            }
            return AccessibilitySelection(
                processIdentifier: processIdentifier,
                element: element,
                range: selectedRange,
                text: selectedText
            )
        }
        return nil
    }

    private static func attributeElement(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = attributeValue(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func attributeValue(_ attribute: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private static func selectedRange(from element: AXUIElement) -> CFRange? {
        guard let value = attributeValue(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length > 0 else {
            return nil
        }
        return range
    }

    private static func pasteboardContainsNonTextPayload(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.pasteboardItems?.flatMap(\.types) ?? pasteboard.types ?? []
        return types.contains { type in
            let rawValue = type.rawValue.lowercased()
            return nonTextPayloadTypeFragments.contains { rawValue.contains($0) }
        }
    }

    private static func waitForSyntheticCopy() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                continuation.resume()
            }
        }
    }

    private static func yieldPasteboardOwnershipCheck() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    static func replaceSelectedText(with text: String, expectedCaptureID: UUID) -> Bool {
        guard isAccessibilityTrusted else {
            return false
        }

        guard let captured = lastCapturedAccessibilitySelection,
              captured.id == expectedCaptureID,
              NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier == captured.processIdentifier }),
              let currentText = selectedText(from: captured.element),
              let currentRange = selectedRange(from: captured.element),
              currentText == captured.text,
              currentRange.location == captured.range.location,
              currentRange.length == captured.range.length else {
            return false
        }

        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            captured.element,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        ) == .success,
        isSettable.boolValue else {
            return false
        }
        // 直接写回原 AX 选区，避免激活窗口和临时覆盖系统剪贴板造成 TOCTOU 误替换。
        let result = AXUIElementSetAttributeValue(
            captured.element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        if result == .success {
            clearCapturedSelectionSource()
            return true
        }
        return false
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

}
