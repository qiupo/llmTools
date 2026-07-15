import AppKit
import Carbon.HIToolbox
import LLMToolsCore

@MainActor
protocol HotKeyServiceDelegate: AnyObject {
    func hotKeyService(_ service: HotKeyService, didTriggerQuickActionCapturingSelection shouldCaptureSelection: Bool)
    func hotKeyServiceDidTriggerLiveSubtitles(_ service: HotKeyService)
}

@MainActor
final class HotKeyService {
    struct RegistrationFailure {
        let name: String
        let status: OSStatus
    }

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
        quickActionWithoutSelectionShortcut: KeyboardShortcutPreference,
        liveSubtitleShortcut: KeyboardShortcutPreference
    ) -> [RegistrationFailure] {
        unregister()

        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let eventHandlerStatus = InstallEventHandler(
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
                guard status == noErr else {
                    return noErr
                }
                Task { @MainActor in
                    switch hotKeyID.id {
                    case 1:
                        service.delegate?.hotKeyService(service, didTriggerQuickActionCapturingSelection: true)
                    case 2:
                        service.delegate?.hotKeyService(service, didTriggerQuickActionCapturingSelection: false)
                    case 3:
                        service.delegate?.hotKeyServiceDidTriggerLiveSubtitles(service)
                    default:
                        break
                    }
                }
                return noErr
            },
            1,
            [eventSpec],
            selfPointer,
            &eventHandler
        )
        guard eventHandlerStatus == noErr else {
            return [RegistrationFailure(name: "event-handler", status: eventHandlerStatus)]
        }

        var failures: [RegistrationFailure] = []
        if let failure = registerHotKey(
            keyCode: quickActionShortcut.keyCode,
            modifiers: quickActionShortcut.modifiers,
            id: 1,
            name: "quick-action-selection"
        ) {
            failures.append(failure)
        }
        if let failure = registerHotKey(
            keyCode: quickActionWithoutSelectionShortcut.keyCode,
            modifiers: quickActionWithoutSelectionShortcut.modifiers,
            id: 2,
            name: "quick-action-empty"
        ) {
            failures.append(failure)
        }
        if let failure = registerHotKey(
            keyCode: liveSubtitleShortcut.keyCode,
            modifiers: liveSubtitleShortcut.modifiers,
            id: 3,
            name: "live-subtitles"
        ) {
            failures.append(failure)
        }
        if !failures.isEmpty {
            // 三组全局快捷键是一个配置集合，任何一项失败都不能留下半注册状态。
            unregister()
        }
        return failures
    }

    private func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32,
        name: String
    ) -> RegistrationFailure? {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4C4D54), id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
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
        guard status == noErr, hotKeyRef != nil else {
            // Carbon 会在组合键被系统或其他应用占用时返回错误，必须显式暴露给用户。
            return RegistrationFailure(name: name, status: status)
        }
        return nil
    }
}
