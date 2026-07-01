import AppKit
import Carbon.HIToolbox
import LLMToolsCore

@MainActor
protocol HotKeyServiceDelegate: AnyObject {
    func hotKeyService(_ service: HotKeyService, didTriggerQuickActionCapturingSelection shouldCaptureSelection: Bool)
}

@MainActor
final class HotKeyService {
    weak var delegate: HotKeyServiceDelegate?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []

    init() {}

    func unregister() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func registerHotKeys(
        quickActionShortcut: KeyboardShortcutPreference,
        quickActionWithoutSelectionShortcut: KeyboardShortcutPreference
    ) {
        unregister()

        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let shouldCaptureSelection = status == noErr ? hotKeyID.id == 1 : true
                Task { @MainActor in
                    service.delegate?.hotKeyService(
                        service,
                        didTriggerQuickActionCapturingSelection: shouldCaptureSelection
                    )
                }
                return noErr
            },
            1,
            [eventSpec],
            selfPointer,
            &eventHandler
        )

        registerHotKey(
            keyCode: quickActionShortcut.keyCode,
            modifiers: quickActionShortcut.modifiers,
            id: 1
        )
        registerHotKey(
            keyCode: quickActionWithoutSelectionShortcut.keyCode,
            modifiers: quickActionWithoutSelectionShortcut.modifiers,
            id: 2
        )
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4C4D54), id: id)
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
    }
}
