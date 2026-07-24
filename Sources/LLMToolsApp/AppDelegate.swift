import AppKit
import Combine
import SwiftUI
import LLMToolsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, HotKeyServiceDelegate, SelectionActionServiceDelegate, NSMenuDelegate {
    private struct RegisteredHotKeys: Equatable {
        let quickAction: KeyboardShortcutPreference
        let quickActionWithoutSelection: KeyboardShortcutPreference
        let liveSubtitles: KeyboardShortcutPreference

        static var defaults: RegisteredHotKeys {
            let preferences = AppPreferences()
            return RegisteredHotKeys(
                quickAction: preferences.quickActionShortcut,
                quickActionWithoutSelection: preferences.quickActionWithoutSelectionShortcut,
                liveSubtitles: preferences.liveSubtitleShortcut
            )
        }
    }

    private enum LiveSubtitleResizeCursorKind {
        case horizontal
        case vertical

        var cursor: NSCursor {
            switch self {
            case .horizontal:
                return .resizeLeftRight
            case .vertical:
                return .resizeUpDown
            }
        }
    }

    private let selectionActionCompactSize = NSSize(width: 260, height: 58)
    private let selectionActionExpandedSize = NSSize(width: 260, height: 167)
    private let settingsWindowContentSize = NSSize(width: 700, height: 640)
    private let liveSubtitleWindowInitialSize = NSSize(
        width: CGFloat(MediaSubtitlePreferences.defaultLiveWindowWidth),
        height: CGFloat(MediaSubtitlePreferences.defaultLiveWindowHeight)
    )
    private let liveSubtitleWindowMinSize = NSSize(
        width: CGFloat(MediaSubtitlePreferences.minimumLiveWindowWidth),
        height: CGFloat(MediaSubtitlePreferences.minimumLiveWindowHeight)
    )
    private let liveSubtitleImmersiveTwoLineHeight: CGFloat = 96
    private let liveSubtitleImmersiveBilingualHeight: CGFloat = 128
    private let liveMeetingWindowContentSize = NSSize(width: 980, height: 700)
    private let ttsWindowContentSize = NSSize(width: 1_120, height: 760)
    private let ttsVoiceWindowContentSize = NSSize(width: 760, height: 580)
    private let statusMenuMessageLimit = 32

    private let appState = AppState()
    private let hotKeyService = HotKeyService()
    private let selectionActionService = SelectionActionService()
    private let settingsNavigation = SettingsNavigationState()
    // 快捷操作是高频临时窗口，默认置顶；用户仍可通过窗口内图钉随时取消。
    private let quickActionPinState = WindowPinState(isPinned: true)
    private let selectionActionPinState = WindowPinState()
    private let floatingWidgetPinState = WindowPinState()
    private let liveSubtitlePinState = WindowPinState()
    private let liveMeetingPinState = WindowPinState()
    private let ttsPinState = WindowPinState()
    private let ttsVoicePinState = WindowPinState()
    private lazy var localAppBridgeServer = LocalAppBridgeServer(appState: appState)
    private var cancellables: Set<AnyCancellable> = []
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var quickActionWindowController: WindowController?
    private var selectionActionWindowController: WindowController?
    private var floatingWindowController: WindowController?
    private var liveSubtitleWindowController: WindowController?
    private var liveMeetingWindowController: WindowController?
    private var ttsWindowController: WindowController?
    private var ttsVoiceWindowController: WindowController?
    private var settingsWindowController: WindowController?
    private var liveSubtitleWindowResizeObserver: Any?
    private var selectionDismissMonitors: [Any] = []
    private var selectedTextCopyMonitor: Any?
    private var quickActionSelectionCaptureTask: Task<Void, Never>?
    private var quickActionSelectionCaptureRevision = 0
    private var selectionActionCaptureTask: Task<Void, Never>?
    private var selectionCaptureRevision = 0
    private var lastRegisteredHotKeys: RegisteredHotKeys?
    private var hotKeyRegistrationError: String?
    private var hotKeyPreferencesBeingRestored: RegisteredHotKeys?
    private var liveSubtitleEscapeMonitors: [Any] = []
    private var liveSubtitlePointerMonitors: [Any] = []
    private var liveSubtitleResizeCursorKind: LiveSubtitleResizeCursorKind?
    private var terminationPreparationInProgress = false
    private var lastSelectionScreenPoint: NSPoint?
    private var selectionActionShownAt = Date.distantPast
    private var isSelectionActionEnabled = false
    private var isSelectionActionVisible = false
    private let selectionGestureLineHeight: CGFloat = 28

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKeyService.delegate = self
        selectionActionService.delegate = self
        configureMainMenu()
        configureStatusItem()
        configureWindows()
        SelectedTextService.startMonitoringPasteboardOwnershipEvents()
        installSelectedTextCopyMonitor()
        installLiveSubtitleEscapeMonitors()
        installLiveSubtitlePointerMonitors()
        observeAppState()
        if ProcessInfo.processInfo.environment["LLMTOOLS_OPEN_MEETING_WINDOW"] == "1" {
            openLiveMeeting()
        }
        if ProcessInfo.processInfo.environment["LLMTOOLS_OPEN_TTS_WINDOW"] == "1" {
            openTextToSpeech()
        }
        if ProcessInfo.processInfo.environment["LLMTOOLS_OPEN_TTS_VOICE_WINDOW"] == "1" {
            openTTSVoiceManagement()
        }
        Task {
            await appState.bootstrap()
            localAppBridgeServer.start()
            applyWindowPreferences()
            applySelectionActionPreference()
            applyHotKeyPreferences()
            refreshStatusMenuItem()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPreparationInProgress else { return .terminateLater }
        terminationPreparationInProgress = true
        Task { @MainActor [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: true)
                return
            }
            await appState.stopTTSForShutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyService.unregister()
        SelectedTextService.stopMonitoringPasteboardOwnershipEvents()
        appState.cancelCurrentTask(unloadModel: true)
        appState.stopAppLiveSubtitlesForShutdown()
        appState.prepareLiveMeetingForAbnormalTermination()
        if let liveSubtitleWindowResizeObserver {
            NotificationCenter.default.removeObserver(liveSubtitleWindowResizeObserver)
        }
        removeSelectedTextCopyMonitor()
        removeLiveSubtitleEscapeMonitors()
        removeLiveSubtitlePointerMonitors()
        selectionActionService.stop()
        localAppBridgeServer.stop()
    }

    private func installSelectedTextCopyMonitor() {
        removeSelectedTextCopyMonitor()
        // 菜单栏浮窗可能在 Edit 菜单阶段丢失 copy:，仅对真实 NSTextView 选区做确定性兜底。
        selectedTextCopyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard CommandFriendlyTextView.copyActiveSelectionIfNeeded(for: event) else {
                return event
            }
            return nil
        }
    }

    private func removeSelectedTextCopyMonitor() {
        if let selectedTextCopyMonitor {
            NSEvent.removeMonitor(selectedTextCopyMonitor)
            self.selectedTextCopyMonitor = nil
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "llmTools")
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")

        // accessory 应用也需要标准编辑菜单，TextField/TextEditor 才能把快捷键交给当前 responder。
        let undoItem = NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        let cutItem = NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let pasteItem = NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pastePlainItem = NSMenuItem(
            title: "粘贴并匹配样式",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        pastePlainItem.keyEquivalentModifierMask = [.command, .option, .shift]
        let selectAllItem = NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenu.addItem(undoItem)
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(cutItem)
        editMenu.addItem(copyItem)
        editMenu.addItem(pasteItem)
        editMenu.addItem(pastePlainItem)
        editMenu.addItem(.separator())
        editMenu.addItem(selectAllItem)

        appMenu.addItem(NSMenuItem(
            title: "退出 llmTools",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu
        editMenuItem.submenu = editMenu
        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: "llmTools")
            button.action = #selector(toggleMenu)
            button.target = self
        }

        let menu = NSMenu()
        menu.delegate = self
        let statusMenuItem = NSMenuItem(title: "状态：启动中", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "打开快捷操作", action: #selector(openQuickAction), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "图片 OCR", action: #selector(openImageOCR), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "开始实时字幕", action: #selector(toggleAppLiveSubtitles), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "会议转写与纪要", action: #selector(openLiveMeeting), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "文案转语音", action: #selector(openTextToSpeech), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "音色管理", action: #selector(openTTSVoiceManagement), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开悬浮组件", action: #selector(openFloatingWidget), keyEquivalent: "w"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "模型", action: #selector(openModelSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openGeneralSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        self.statusMenuItem = statusMenuItem
        self.statusItem = statusItem
    }

    private func configureWindows() {
        quickActionWindowController = WindowController(
            title: "快捷操作",
            frame: NSRect(x: 0, y: 0, width: 500, height: 400),
            contentView: AnyView(QuickActionView(
                appState: appState,
                pinState: quickActionPinState,
                onTitleChange: { [weak self] in
                    self?.refreshQuickActionWindowTitle()
                },
                onClose: { [weak self] in
                    self?.quickActionWindowController?.close()
                }
            )),
            pinState: quickActionPinState
        )
        if let quickActionWindow = quickActionWindowController?.window as? FloatingWindow {
            quickActionWindow.onEscape = { [weak self] in
                self?.quickActionWindowController?.close()
            }
            quickActionWindow.onClose = { [weak self] in
                self?.cancelPendingQuickActionSelectionCapture()
                self?.appState.resetQuickActionSession()
            }
            quickActionWindow.onKeyboardShortcut = { [weak self] shortcut in
                self?.handleQuickActionShortcut(shortcut) ?? false
            }
            quickActionWindow.onCommandPaste = { [weak self] in
                guard let self,
                      appState.quickActionMode == .image,
                      appState.canLoadOCRImageFromPasteboard() else {
                    return false
                }
                appState.loadOCRImageFromPasteboard()
                return true
            }
        }
        selectionActionWindowController = WindowController(
            title: "选择操作",
            frame: NSRect(origin: .zero, size: selectionActionCompactSize),
            contentView: AnyView(SelectionActionView(appState: appState, pinState: selectionActionPinState) { [weak self] task in
                self?.performSelectionAction(task)
            }),
            pinState: selectionActionPinState,
            windowKind: .nonActivatingPanel
        )
        selectionActionWindowController?.window?.isOpaque = false
        selectionActionWindowController?.window?.backgroundColor = .clear
        selectionActionWindowController?.window?.hasShadow = false
        floatingWindowController = WindowController(
            title: "悬浮组件",
            frame: NSRect(x: 0, y: 0, width: 360, height: 520),
            contentView: AnyView(FloatingWidgetView(appState: appState, pinState: floatingWidgetPinState)),
            pinState: floatingWidgetPinState,
            autoCollapseAtScreenEdge: appState.preferences.autoCollapseWidget
        )
        liveSubtitleWindowController = WindowController(
            title: "实时字幕",
            frame: NSRect(origin: .zero, size: liveSubtitleWindowInitialSize),
            contentView: AnyView(LiveSubtitleFloatingView(appState: appState, pinState: liveSubtitlePinState) { [weak self] in
                self?.closeLiveSubtitlesFromWindow()
            }),
            pinState: liveSubtitlePinState,
            windowKind: .nonActivatingPanel,
            allowsResizing: true
        )
        if let liveSubtitleWindow = liveSubtitleWindowController?.window {
            liveSubtitleWindow.isOpaque = false
            liveSubtitleWindow.backgroundColor = .clear
            liveSubtitleWindow.hasShadow = false
            liveSubtitleWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            liveSubtitleWindow.contentMinSize = liveSubtitleWindowMinSize
            liveSubtitleWindow.minSize = liveSubtitleWindowMinSize
            if let liveSubtitlePanel = liveSubtitleWindow as? SelectionActionWindow {
                liveSubtitlePanel.onEscape = { [weak self] in
                    self?.closeLiveSubtitlesFromWindow()
                }
            }
            liveSubtitleWindowResizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: liveSubtitleWindow,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else {
                    return
                }
                Task { @MainActor in
                    self?.persistLiveSubtitleWindowSize(window)
                }
            }
        }
        liveMeetingWindowController = WindowController(
            title: "会议转写与纪要",
            frame: NSRect(origin: .zero, size: liveMeetingWindowContentSize),
            contentView: AnyView(LiveMeetingView(appState: appState, pinState: liveMeetingPinState)),
            pinState: liveMeetingPinState,
            allowsResizing: true
        )
        if let liveMeetingWindow = liveMeetingWindowController?.window {
            liveMeetingWindow.contentMinSize = NSSize(width: 760, height: 520)
            liveMeetingWindow.minSize = NSSize(width: 760, height: 520)
        }
        ttsWindowController = WindowController(
            title: "文案转语音",
            frame: NSRect(origin: .zero, size: ttsWindowContentSize),
            contentView: AnyView(
                TextToSpeechView(appState: appState, pinState: ttsPinState) { [weak self] in
                    self?.openTTSVoiceManagement()
                }
            ),
            pinState: ttsPinState,
            allowsResizing: true
        )
        if let ttsWindow = ttsWindowController?.window {
            ttsWindow.contentMinSize = NSSize(width: 900, height: 600)
            ttsWindow.minSize = NSSize(width: 900, height: 600)
        }
        // 音色配置独立成窗口，主工作台只保留选音色与生成音频的流程。
        ttsVoiceWindowController = WindowController(
            title: "音色管理",
            frame: NSRect(origin: .zero, size: ttsVoiceWindowContentSize),
            contentView: AnyView(TTSVoiceManagementView(appState: appState, pinState: ttsVoicePinState)),
            pinState: ttsVoicePinState,
            allowsResizing: true
        )
        if let voiceWindow = ttsVoiceWindowController?.window {
            voiceWindow.contentMinSize = NSSize(width: 720, height: 520)
            voiceWindow.minSize = NSSize(width: 720, height: 520)
        }
        settingsWindowController = WindowController(
            title: "设置",
            frame: NSRect(origin: .zero, size: settingsWindowContentSize),
            contentView: AnyView(SettingsView(appState: appState, navigation: settingsNavigation))
        )
        if let settingsWindow = settingsWindowController?.window {
            settingsWindow.contentMinSize = NSSize(width: settingsWindowContentSize.width, height: 380)
            settingsWindow.contentMaxSize = NSSize(width: settingsWindowContentSize.width, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    @objc private func toggleMenu() {
        statusItem?.button?.performClick(nil)
    }

    @objc private func openQuickAction() {
        _ = appState.switchQuickActionMode(to: .text)
        openQuickActionWindow(nearSelection: false)
    }

    @objc private func openImageOCR() {
        _ = appState.switchQuickActionMode(to: .image)
        openQuickActionWindow(nearSelection: false)
    }

    @objc private func openFloatingWidget() {
        floatingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openLiveMeeting() {
        liveMeetingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openTextToSpeech() {
        ttsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor [weak self] in
            await self?.appState.refreshTTSHealth()
        }
    }

    @objc private func openTTSVoiceManagement() {
        ttsVoiceWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor [weak self] in
            await self?.appState.refreshTTSHealth()
        }
    }

    @objc private func toggleAppLiveSubtitles() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if appState.appLiveSubtitlesAreRunning {
                _ = await appState.stopAppLiveSubtitles()
            } else {
                await openAppLiveSubtitles()
            }
        }
    }

    private func openAppLiveSubtitles() async {
        if appState.appLiveSubtitlesAreRunning {
            showLiveSubtitleWindow()
            return
        }
        do {
            _ = try await appState.startAppLiveSubtitles()
        } catch {
            // AppState stores the failure state; still show the floating window so the user can see it.
        }
        showLiveSubtitleWindow()
    }

    private func closeLiveSubtitlesFromWindow() {
        if let window = liveSubtitleWindowController?.window {
            persistLiveSubtitleWindowSize(window)
            window.orderOut(nil)
        }
        clearLiveSubtitleResizeCursor()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if appState.appLiveSubtitlesAreRunning {
                _ = await appState.stopAppLiveSubtitles(payload: StopAppLiveSubtitlePayload(reason: "window_closed"))
            }
            if let window = liveSubtitleWindowController?.window {
                persistLiveSubtitleWindowSize(window)
                window.orderOut(nil)
            }
            clearLiveSubtitleResizeCursor()
        }
    }

    @objc private func openGeneralSettings() {
        showSettings(tab: .general)
    }

    @objc private func openModelSettings() {
        showSettings(tab: .models)
    }

    private func showSettings(tab: SettingsTab) {
        settingsNavigation.selectedTab = tab
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuTitles()
        refreshStatusMenuItem()
    }

    func hotKeyService(_ service: HotKeyService, didTriggerQuickActionCapturingSelection shouldCaptureSelection: Bool) {
        appState.cancelQuickActionWork()
        if shouldCaptureSelection {
            populateSelectedTextIfAvailable()
        } else {
            cancelPendingQuickActionSelectionCapture()
            appState.setInputText("", origin: .manual)
            appState.statusMessage = L10n.text("Paste or type text", language: appState.preferences.appLanguage)
            openQuickAction()
        }
    }

    func hotKeyServiceDidTriggerLiveSubtitles(_ service: HotKeyService) {
        Task { @MainActor [weak self] in
            await self?.openAppLiveSubtitles()
        }
    }

    func selectionActionService(
        _ service: SelectionActionService,
        didTriggerSelectionAt screenPoint: NSPoint,
        source: SelectionActionTriggerSource,
        gesture: SelectionActionGesture?
    ) {
        guard isSelectionActionEnabled else {
            return
        }

        selectionCaptureRevision += 1
        let revision = selectionCaptureRevision
        selectionActionCaptureTask?.cancel()
        selectionActionCaptureTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.handleSelectionActionTrigger(
                at: screenPoint,
                source: source,
                gesture: gesture,
                revision: revision
            )
        }
    }

    private func handleSelectionActionTrigger(
        at screenPoint: NSPoint,
        source: SelectionActionTriggerSource,
        gesture: SelectionActionGesture?,
        revision: Int
    ) async {
        guard isSelectionActionEnabled else {
            return
        }
        guard shouldHandleSelectionActionTrigger(source: source, gesture: gesture) else {
            return
        }

        guard let selectedText = await captureSelectedTextForSelectionAction(
            source: source,
            at: screenPoint,
            revision: revision
        ) else {
            guard !Task.isCancelled, revision == selectionCaptureRevision else {
                return
            }
            if !SelectedTextService.isAccessibilityTrusted {
                appState.statusMessage = L10n.text("Enable Accessibility permission or paste text", language: appState.preferences.appLanguage)
            } else {
                appState.statusMessage = L10n.text("Paste or type text", language: appState.preferences.appLanguage)
            }
            return
        }
        guard !Task.isCancelled, revision == selectionCaptureRevision else {
            return
        }

        guard appState.prepareAutomaticSelectionText(selectedText) else {
            lastSelectionScreenPoint = screenPoint
            showSelectionAction(at: screenPoint)
            return
        }

        appState.setInputText(selectedText, origin: .selection)
        appState.selectedTask = .translate
        appState.showSelectionInlineResult()
        appState.statusMessage = L10n.text("Captured selected text", language: appState.preferences.appLanguage)
        lastSelectionScreenPoint = screenPoint
        showSelectionAction(at: screenPoint)
        guard !appState.selectedTextModelIsRemote else {
            appState.statusMessage = L10n.text(
                "Selected text is ready. Choose an action to send it to the remote provider.",
                language: appState.preferences.appLanguage
            )
            return
        }
        appState.runCurrentTask()
    }

    private func captureSelectedTextForSelectionAction(
        source: SelectionActionTriggerSource,
        at screenPoint: NSPoint,
        revision: Int
    ) async -> String? {
        let retryDelays: [UInt64] = [0, 180_000_000, 320_000_000]
        for delay in retryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled,
                  revision == selectionCaptureRevision,
                  isSelectionActionEnabled else {
                return nil
            }
            if let selectedText = await SelectedTextService.captureSelectedText(
                near: screenPoint,
                preserveNonTextClipboardPayloads: true
            ) {
                return selectedText
            }
        }
        return nil
    }

    private func shouldHandleSelectionActionTrigger(source: SelectionActionTriggerSource, gesture: SelectionActionGesture?) -> Bool {
        guard source == .mouseDrag,
              let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let lineLimitRule = appState.preferences.selectionLineLimitRules.first(where: { $0.bundleIdentifier == bundleIdentifier }),
              let gesture else {
            return true
        }

        let maximumLines = max(1, lineLimitRule.maximumLineCount)
        let maximumHeight = CGFloat(maximumLines) * selectionGestureLineHeight
        if gesture.height > maximumHeight {
            return false
        }
        return true
    }

    private func populateSelectedTextIfAvailable() {
        selectionCaptureRevision += 1
        selectionActionCaptureTask?.cancel()
        selectionActionCaptureTask = nil
        cancelPendingQuickActionSelectionCapture()
        quickActionSelectionCaptureRevision += 1
        let revision = quickActionSelectionCaptureRevision
        quickActionSelectionCaptureTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if let selectedText = await SelectedTextService.captureSelectedText() {
                guard !Task.isCancelled, revision == quickActionSelectionCaptureRevision else {
                    return
                }
                appState.setInputText(selectedText, origin: .selection)
                appState.statusMessage = L10n.text("Captured selected text", language: appState.preferences.appLanguage)
            } else if !SelectedTextService.isAccessibilityTrusted {
                guard !Task.isCancelled, revision == quickActionSelectionCaptureRevision else {
                    return
                }
                SelectedTextService.clearCapturedSelectionSource()
                appState.statusMessage = L10n.text("Enable Accessibility permission or paste text", language: appState.preferences.appLanguage)
            } else if appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard !Task.isCancelled, revision == quickActionSelectionCaptureRevision else {
                    return
                }
                appState.setInputText("", origin: .manual)
                appState.statusMessage = L10n.text("Paste or type text", language: appState.preferences.appLanguage)
            }
            guard !Task.isCancelled, revision == quickActionSelectionCaptureRevision else {
                return
            }
            quickActionSelectionCaptureTask = nil
            openQuickAction()
        }
    }

    private func cancelPendingQuickActionSelectionCapture() {
        quickActionSelectionCaptureTask?.cancel()
        quickActionSelectionCaptureTask = nil
        quickActionSelectionCaptureRevision += 1
        selectionCaptureRevision += 1
        selectionActionCaptureTask?.cancel()
        selectionActionCaptureTask = nil
    }

    private func showSelectionAction(at screenPoint: NSPoint) {
        guard isSelectionActionEnabled else {
            return
        }
        guard let window = selectionActionWindowController?.window else {
            return
        }

        let targetSize = selectionActionWindowSize()
        let origin = selectionActionWindowOrigin(
            near: screenPoint,
            windowSize: targetSize
        )
        window.setFrame(NSRect(origin: origin, size: targetSize), display: true)
        isSelectionActionVisible = true
        selectionActionShownAt = Date()
        window.orderFrontRegardless()
        installSelectionDismissMonitors()
    }

    private func performSelectionAction(_ task: TaskKind) {
        let selectedText = appState.inputText
        appState.setInputText(selectedText, origin: .selection)
        appState.selectedTask = task
        appState.selectionInlineResultVisible = false
        openQuickActionWindow(nearSelection: true)
        closeSelectionAction()
    }

    private func closeSelectionAction() {
        isSelectionActionVisible = false
        removeSelectionDismissMonitors()
        selectionActionWindowController?.window?.orderOut(nil)
    }

    private func installLiveSubtitleEscapeMonitors() {
        removeLiveSubtitleEscapeMonitors()

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else {
                return event
            }
            guard self.handleLiveSubtitleEscapeEvent(event, requirePointerInsideWindow: false) else {
                return event
            }
            return nil
        }) {
            liveSubtitleEscapeMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            Task { @MainActor in
                _ = self?.handleLiveSubtitleEscapeEvent(event, requirePointerInsideWindow: true)
            }
        }) {
            liveSubtitleEscapeMonitors.append(globalMonitor)
        }
    }

    private func removeLiveSubtitleEscapeMonitors() {
        liveSubtitleEscapeMonitors.forEach(NSEvent.removeMonitor)
        liveSubtitleEscapeMonitors.removeAll()
    }

    private func installLiveSubtitlePointerMonitors() {
        removeLiveSubtitlePointerMonitors()

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.updateLiveSubtitleResizeCursor(at: NSEvent.mouseLocation)
            return event
        }) {
            liveSubtitlePointerMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.updateLiveSubtitleResizeCursor(at: NSEvent.mouseLocation)
            }
        }) {
            liveSubtitlePointerMonitors.append(globalMonitor)
        }
    }

    private func removeLiveSubtitlePointerMonitors() {
        liveSubtitlePointerMonitors.forEach(NSEvent.removeMonitor)
        liveSubtitlePointerMonitors.removeAll()
        clearLiveSubtitleResizeCursor()
    }

    private func updateLiveSubtitleResizeCursor(at screenPoint: NSPoint) {
        guard let cursorKind = liveSubtitleResizeCursorKind(at: screenPoint) else {
            clearLiveSubtitleResizeCursor()
            return
        }
        guard liveSubtitleResizeCursorKind != cursorKind else {
            return
        }
        clearLiveSubtitleResizeCursor()
        cursorKind.cursor.push()
        liveSubtitleResizeCursorKind = cursorKind
    }

    private func clearLiveSubtitleResizeCursor() {
        guard liveSubtitleResizeCursorKind != nil else {
            return
        }
        NSCursor.pop()
        liveSubtitleResizeCursorKind = nil
    }

    private func liveSubtitleResizeCursorKind(at screenPoint: NSPoint) -> LiveSubtitleResizeCursorKind? {
        guard let window = liveSubtitleWindowController?.window,
              window.isVisible,
              window.styleMask.contains(.resizable) else {
            return nil
        }

        let edgeSlop: CGFloat = 10
        let frame = window.frame
        let hitFrame = frame.insetBy(dx: -edgeSlop, dy: -edgeSlop)
        guard hitFrame.contains(screenPoint) else {
            return nil
        }

        let canResizeHorizontally = Self.canResizeLiveSubtitleWindow(
            minimum: window.contentMinSize.width,
            maximum: window.contentMaxSize.width
        )
        let canResizeVertically = Self.canResizeLiveSubtitleWindow(
            minimum: window.contentMinSize.height,
            maximum: window.contentMaxSize.height
        )
        let isNearHorizontalEdge = abs(screenPoint.x - frame.minX) <= edgeSlop
            || abs(screenPoint.x - frame.maxX) <= edgeSlop
        let isNearVerticalEdge = abs(screenPoint.y - frame.minY) <= edgeSlop
            || abs(screenPoint.y - frame.maxY) <= edgeSlop

        if canResizeHorizontally && isNearHorizontalEdge {
            return .horizontal
        }
        if canResizeVertically && isNearVerticalEdge {
            return .vertical
        }
        return nil
    }

    private static func canResizeLiveSubtitleWindow(minimum: CGFloat, maximum: CGFloat) -> Bool {
        if maximum.isFinite {
            return maximum - minimum > 1
        }
        return true
    }

    @discardableResult
    private func handleLiveSubtitleEscapeEvent(_ event: NSEvent, requirePointerInsideWindow: Bool) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 53,
              modifiers.isEmpty,
              let window = liveSubtitleWindowController?.window,
              window.isVisible else {
            return false
        }

        if requirePointerInsideWindow || event.window == nil {
            guard window.frame.contains(NSEvent.mouseLocation) else {
                return false
            }
        } else if let eventWindow = event.window,
                  eventWindow !== window {
            return false
        }

        closeLiveSubtitlesFromWindow()
        return true
    }

    private func installSelectionDismissMonitors() {
        removeSelectionDismissMonitors()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if event.window !== self.selectionActionWindowController?.window,
                   !self.selectionActionPinState.isPinned {
                    self.closeSelectionAction()
                }
            }
            return event
        }) {
            selectionDismissMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in
                guard let self else {
                    return
                }
                guard !SelectedTextService.isSyntheticShortcutEvent(event),
                      !self.selectionActionPinState.isPinned,
                      self.shouldDismissSelectionAction(for: event) else {
                    return
                }
                guard !self.isMouseInsideSelectionActionWindow() else {
                    return
                }
                self.closeSelectionAction()
            }
        }) {
            selectionDismissMonitors.append(globalMonitor)
        }
    }

    private func removeSelectionDismissMonitors() {
        selectionDismissMonitors.forEach(NSEvent.removeMonitor)
        selectionDismissMonitors.removeAll()
    }

    private func shouldDismissSelectionAction(for event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            return true
        default:
            return Date().timeIntervalSince(selectionActionShownAt) > 0.2
        }
    }

    private func observeAppState() {
        appState.$preferences
            .dropFirst()
            .sink { [weak self] preferences in
                self?.applyWindowPreferences(preferences)
                self?.applySelectionActionPreference(preferences)
                self?.applyHotKeyPreferences(preferences)
                self?.refreshStatusMenuItem()
            }
            .store(in: &cancellables)

        appState.$models
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshStatusMenuItem()
            }
            .store(in: &cancellables)

        appState.$statusMessage
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshStatusMenuItem()
            }
            .store(in: &cancellables)

        appState.$appLiveSubtitleRunState
            .dropFirst()
            .sink { [weak self] state in
                self?.refreshLiveSubtitleWindow(for: state)
                self?.refreshStatusMenuItem()
                self?.refreshMenuTitles()
            }
            .store(in: &cancellables)

        appState.$appLiveSubtitleIsImmersive
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshLiveSubtitleWindowLayout(animated: true)
            }
            .store(in: &cancellables)

        appState.$appLiveSubtitleDisplayMode
            .dropFirst()
            .sink { [weak self] _ in
                guard self?.appState.appLiveSubtitleIsImmersive == true else {
                    return
                }
                self?.refreshLiveSubtitleWindowLayout(animated: true)
            }
            .store(in: &cancellables)

        appState.$isRunning
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshSelectionActionWindowLayout()
            }
            .store(in: &cancellables)

        appState.$outputText
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshSelectionActionWindowLayout()
            }
            .store(in: &cancellables)

        appState.$validationError
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshSelectionActionWindowLayout()
            }
            .store(in: &cancellables)

        appState.$inputOrigin
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshSelectionActionWindowLayout()
            }
            .store(in: &cancellables)
    }

    private func applyWindowPreferences(_ preferences: AppPreferences? = nil) {
        guard let window = floatingWindowController?.window as? FloatingWindow else {
            return
        }
        let preferences = preferences ?? appState.preferences
        window.autoCollapseAtScreenEdge = preferences.autoCollapseWidget
        if preferences.widgetVisibleOnAllSpaces {
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        } else {
            window.collectionBehavior = [.fullScreenAuxiliary, .managed]
        }
    }

    private func refreshLiveSubtitleWindow(for state: AppState.AppLiveSubtitleRunState) {
        switch state {
        case .starting, .running, .failed:
            showLiveSubtitleWindow()
        case .stopping, .stopped:
            if let window = liveSubtitleWindowController?.window {
                persistLiveSubtitleWindowSize(window)
                window.orderOut(nil)
                clearLiveSubtitleResizeCursor()
            }
        }
    }

    private func showLiveSubtitleWindow() {
        guard let window = liveSubtitleWindowController?.window else {
            return
        }
        if !window.isVisible {
            positionLiveSubtitleWindow(window)
        }
        refreshLiveSubtitleWindowLayout(animated: false)
        window.orderFrontRegardless()
        updateLiveSubtitleResizeCursor(at: NSEvent.mouseLocation)
    }

    private func positionLiveSubtitleWindow(_ window: NSWindow) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let availableWidth = max(liveSubtitleWindowMinSize.width, visibleFrame.width - 80)
        let availableHeight = max(liveSubtitleWindowMinSize.height, visibleFrame.height - 120)
        let savedWidth = CGFloat(appState.preferences.mediaSubtitles.liveWindowWidth)
        let savedHeight = CGFloat(appState.preferences.mediaSubtitles.liveWindowHeight)
        let width = min(max(liveSubtitleWindowMinSize.width, savedWidth), availableWidth)
        let height = min(max(liveSubtitleWindowMinSize.height, savedHeight), availableHeight)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.minY + 64
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func persistLiveSubtitleWindowSize(_ window: NSWindow) {
        guard !appState.appLiveSubtitleIsImmersive else {
            return
        }
        let width = Double(window.frame.width)
        let height = Double(window.frame.height)
        let current = appState.preferences.mediaSubtitles
        guard abs(width - current.liveWindowWidth) >= 1 || abs(height - current.liveWindowHeight) >= 1 else {
            return
        }
        appState.setLiveSubtitleWindowSize(width: width, height: height)
    }

    private func refreshLiveSubtitleWindowLayout(animated: Bool) {
        guard let window = liveSubtitleWindowController?.window else {
            return
        }
        if appState.appLiveSubtitleIsImmersive {
            let targetHeight = liveSubtitleImmersiveHeight()
            let minimumSize = NSSize(width: liveSubtitleWindowMinSize.width, height: targetHeight)
            let maximumSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: targetHeight)
            window.contentMinSize = minimumSize
            window.minSize = minimumSize
            window.contentMaxSize = maximumSize
            window.maxSize = maximumSize
            invalidateResizeCursorRects(for: window)
            guard window.isVisible else {
                return
            }
            resizeLiveSubtitleWindow(
                window,
                targetSize: NSSize(width: max(window.frame.width, liveSubtitleWindowMinSize.width), height: targetHeight),
                animated: animated
            )
        } else {
            window.contentMinSize = liveSubtitleWindowMinSize
            window.minSize = liveSubtitleWindowMinSize
            let maximumSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.contentMaxSize = maximumSize
            window.maxSize = maximumSize
            invalidateResizeCursorRects(for: window)
            guard window.isVisible else {
                return
            }
            let targetSize = normalLiveSubtitleWindowSize()
            resizeLiveSubtitleWindow(window, targetSize: targetSize, animated: animated)
        }
    }

    private func liveSubtitleImmersiveHeight() -> CGFloat {
        appState.appLiveSubtitleDisplayMode == .bilingual
            ? liveSubtitleImmersiveBilingualHeight
            : liveSubtitleImmersiveTwoLineHeight
    }

    private func normalLiveSubtitleWindowSize() -> NSSize {
        let visibleFrame = liveSubtitleVisibleFrame()
        let availableWidth = max(liveSubtitleWindowMinSize.width, visibleFrame.width - 80)
        let availableHeight = max(liveSubtitleWindowMinSize.height, visibleFrame.height - 120)
        let savedWidth = CGFloat(appState.preferences.mediaSubtitles.liveWindowWidth)
        let savedHeight = CGFloat(appState.preferences.mediaSubtitles.liveWindowHeight)
        return NSSize(
            width: min(max(liveSubtitleWindowMinSize.width, savedWidth), availableWidth),
            height: min(max(liveSubtitleWindowMinSize.height, savedHeight), availableHeight)
        )
    }

    private func resizeLiveSubtitleWindow(
        _ window: NSWindow,
        targetSize: NSSize,
        animated: Bool
    ) {
        let visibleFrame = liveSubtitleVisibleFrame(for: window)
        let width = min(max(targetSize.width, window.minSize.width), max(window.minSize.width, visibleFrame.width - 40))
        let height = min(max(targetSize.height, window.minSize.height), max(window.minSize.height, visibleFrame.height - 80))
        let centeredX = window.frame.midX - width / 2
        let minX = visibleFrame.minX + 20
        let maxX = max(minX, visibleFrame.maxX - width - 20)
        let minY = visibleFrame.minY + 20
        let maxY = max(minY, visibleFrame.maxY - height - 20)
        let x = min(max(centeredX, minX), maxX)
        let y = min(max(window.frame.minY, minY), maxY)
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: animated)
        invalidateResizeCursorRects(for: window)
    }

    private func liveSubtitleVisibleFrame(for window: NSWindow? = nil) -> NSRect {
        if let window,
           let screen = NSScreen.screens.first(where: { NSIntersectsRect($0.frame, window.frame) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func invalidateResizeCursorRects(for window: NSWindow) {
        guard let hostingView = window.contentView as? WindowHostingView else {
            return
        }
        window.invalidateCursorRects(for: hostingView)
    }

    private func applySelectionActionPreference(_ preferences: AppPreferences? = nil) {
        let isEnabled = (preferences ?? appState.preferences).selectionActionEnabled
        let preferences = preferences ?? appState.preferences
        isSelectionActionEnabled = isEnabled
        selectionActionService.setEnabledTriggerSources(selectionActionTriggerSources(for: preferences))
        selectionActionService.setEnabled(isEnabled)
        if !isEnabled {
            closeSelectionAction()
        }
    }

    private func applyHotKeyPreferences(_ preferences: AppPreferences? = nil) {
        let preferences = preferences ?? appState.preferences
        let requested = RegisteredHotKeys(
            quickAction: preferences.quickActionShortcut,
            quickActionWithoutSelection: preferences.quickActionWithoutSelectionShortcut,
            liveSubtitles: preferences.liveSubtitleShortcut
        )
        if hotKeyPreferencesBeingRestored == requested {
            hotKeyPreferencesBeingRestored = nil
            return
        }
        guard requested != lastRegisteredHotKeys else {
            return
        }
        let previous = lastRegisteredHotKeys
        let failures = hotKeyService.registerHotKeys(
            quickActionShortcut: requested.quickAction,
            quickActionWithoutSelectionShortcut: requested.quickActionWithoutSelection,
            liveSubtitleShortcut: requested.liveSubtitles
        )
        if let failure = failures.first {
            var rollbackMessage = ""
            let fallback = previous ?? (requested == .defaults ? nil : .defaults)
            if let fallback {
                // registerHotKeys 会先注销当前集合，即使配置未变化，失败后也必须重新注册旧集合。
                let rollbackFailures = hotKeyService.registerHotKeys(
                    quickActionShortcut: fallback.quickAction,
                    quickActionWithoutSelectionShortcut: fallback.quickActionWithoutSelection,
                    liveSubtitleShortcut: fallback.liveSubtitles
                )
                if let rollbackFailure = rollbackFailures.first {
                    lastRegisteredHotKeys = nil
                    rollbackMessage = " " + L10n.text(
                        "The previous shortcut set could not be restored.",
                        language: appState.preferences.appLanguage
                    ) + " [\(rollbackFailure.name): \(rollbackFailure.status)]"
                } else {
                    lastRegisteredHotKeys = fallback
                }
            } else {
                lastRegisteredHotKeys = nil
            }
            let message = L10n.text(
                "A global shortcut could not be registered. Choose a different shortcut.",
                language: appState.preferences.appLanguage
            ) + " [\(failure.name): \(failure.status)]" + rollbackMessage
            hotKeyRegistrationError = message
            appState.validationError = message
            if let fallback, fallback != requested {
                // 注册失败的组合不能留在磁盘，否则重启后没有可回滚集合，三组快捷键都会失效。
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    self.hotKeyPreferencesBeingRestored = fallback
                    self.appState.restoreGlobalShortcutPreferences(
                        quickAction: fallback.quickAction,
                        quickActionWithoutSelection: fallback.quickActionWithoutSelection,
                        liveSubtitles: fallback.liveSubtitles,
                        errorMessage: message
                    )
                }
            }
            return
        }

        lastRegisteredHotKeys = requested
        if appState.validationError == hotKeyRegistrationError {
            appState.validationError = nil
        }
        hotKeyRegistrationError = nil
    }

    private func selectionActionTriggerSources(for preferences: AppPreferences) -> Set<SelectionActionTriggerSource> {
        var sources = Set<SelectionActionTriggerSource>()
        if preferences.selectionActionTriggerMouseDrag {
            sources.insert(.mouseDrag)
        }
        if preferences.selectionActionTriggerDoubleClick {
            sources.insert(.doubleClick)
        }
        if preferences.selectionActionTriggerSelectAll {
            sources.insert(.selectAllShortcut)
        }
        return sources
    }

    private func refreshStatusMenuItem() {
        let statusText = compactStatusText()
        let modelName = appState.selectedModelDisplayName(limit: 14)
        statusMenuItem?.title = "\(statusText) · \(modelName)"
    }

    private func compactStatusText() -> String {
        if appState.isRunning {
            return L10n.text("Running", language: appState.preferences.appLanguage)
        }
        if appState.appLiveSubtitlesAreRunning {
            return L10n.text("Live subtitles", language: appState.preferences.appLanguage)
        }
        return compactMenuStatus(appState.statusMessage)
    }

    private func compactMenuStatus(_ text: String) -> String {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard normalized.count > statusMenuMessageLimit else {
            return normalized
        }
        return "\(normalized.prefix(max(1, statusMenuMessageLimit - 1)))…"
    }

    private func refreshMenuTitles() {
        guard let menu = statusItem?.menu else {
            return
        }

        for item in menu.items {
            switch item.action {
            case #selector(openQuickAction):
                item.title = L10n.text("Open Quick Action", language: appState.preferences.appLanguage)
            case #selector(openImageOCR):
                item.title = L10n.text("Image OCR", language: appState.preferences.appLanguage)
            case #selector(toggleAppLiveSubtitles):
                item.title = L10n.text(
                    appState.appLiveSubtitlesAreRunning ? "Stop live subtitles" : "Start live subtitles",
                    language: appState.preferences.appLanguage
                )
            case #selector(openFloatingWidget):
                item.title = L10n.text("Open Floating Widget", language: appState.preferences.appLanguage)
            case #selector(openTextToSpeech):
                item.title = appState.preferences.appLanguage == .chinese ? "文案转语音" : "Text to Speech"
            case #selector(openTTSVoiceManagement):
                item.title = appState.preferences.appLanguage == .chinese ? "音色管理" : "Voice Management"
            case #selector(openModelSettings):
                item.title = L10n.text("Models", language: appState.preferences.appLanguage)
            case #selector(openGeneralSettings):
                item.title = L10n.text("Settings", language: appState.preferences.appLanguage)
            case #selector(quitApp):
                item.title = L10n.text("Quit", language: appState.preferences.appLanguage)
            default:
                break
            }
        }
    }

    private func positionQuickActionWindowNearSelectionIfPossible() {
        guard let screenPoint = lastSelectionScreenPoint,
              let window = quickActionWindowController?.window,
              appState.inputOrigin == .selection else {
            return
        }

        let origin = preferredWindowOrigin(
            near: screenPoint,
            windowSize: window.frame.size,
            padding: 14,
            placement: .quickAction
        )
        window.setFrameOrigin(origin)
    }

    private func openQuickActionWindow(nearSelection: Bool) {
        refreshQuickActionWindowTitle()
        if nearSelection {
            positionQuickActionWindowNearSelectionIfPossible()
        }
        quickActionWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleQuickActionShortcut(_ shortcut: KeyboardShortcutPreference) -> Bool {
        guard !appState.isRunning, !appState.isPreparingOCRImage else {
            return false
        }
        let shortcuts = appState.preferences.quickActionPopupShortcuts

        if shortcut == shortcuts.textMode {
            guard appState.switchQuickActionMode(to: .text) else { return false }
            refreshQuickActionWindowTitle()
            return true
        }
        if shortcut == shortcuts.imageMode {
            guard appState.switchQuickActionMode(to: .image) else { return false }
            refreshQuickActionWindowTitle()
            return true
        }
        if shortcut == shortcuts.mediaMode {
            guard appState.switchQuickActionMode(to: .media) else { return false }
            refreshQuickActionWindowTitle()
            return true
        }
        if shortcut == shortcuts.speechMode {
            guard appState.switchQuickActionMode(to: .speech) else { return false }
            refreshQuickActionWindowTitle()
            return true
        }

        switch appState.quickActionMode {
        case .text:
            guard let task = shortcuts.textTask(matching: shortcut) else {
                return false
            }
            appState.selectedTask = task
            refreshQuickActionWindowTitle()
            return true
        case .image:
            guard let mode = shortcuts.ocrMode(matching: shortcut) else {
                return false
            }
            appState.setOCRMode(mode)
            refreshQuickActionWindowTitle()
            return true
        case .media:
            return false
        case .speech:
            guard let action = shortcuts.speechAction(matching: shortcut) else {
                return false
            }
            switch action {
            case .generate:
                if appState.quickTTSIsGenerating {
                    appState.cancelQuickTTSGeneration()
                } else {
                    appState.generateQuickTTS()
                }
            case .voicePreview:
                appState.previewQuickTTSVoice()
            case .playback:
                appState.playQuickTTS()
            case .exportWAV:
                appState.exportQuickTTS(format: .wav)
            case .exportM4A:
                appState.exportQuickTTS(format: .m4a)
            }
            return true
        }
    }

    private func refreshQuickActionWindowTitle() {
        switch appState.quickActionMode {
        case .image:
            quickActionWindowController?.window?.title = L10n.text("Image OCR", language: appState.preferences.appLanguage)
        case .media:
            quickActionWindowController?.window?.title = L10n.text("Media subtitles", language: appState.preferences.appLanguage)
        case .speech:
            quickActionWindowController?.window?.title = L10n.text("Generate speech", language: appState.preferences.appLanguage)
        case .text:
            quickActionWindowController?.window?.title = appState.selectedTask.title(language: appState.preferences.appLanguage)
        }
    }

    private var selectionActionShouldShowInlineResult: Bool {
        appState.inputOrigin == .selection && appState.selectionInlineResultVisible
    }

    private func isMouseInsideSelectionActionWindow() -> Bool {
        guard let frame = selectionActionWindowController?.window?.frame else {
            return false
        }
        return NSMouseInRect(NSEvent.mouseLocation, frame, false)
    }

    private func refreshSelectionActionWindowLayout(animated: Bool = false) {
        guard let window = selectionActionWindowController?.window else {
            return
        }

        guard isSelectionActionEnabled else {
            closeSelectionAction()
            return
        }

        guard isSelectionActionVisible else {
            return
        }

        if !selectionActionShouldShowInlineResult && appState.inputOrigin != .selection {
            closeSelectionAction()
            return
        }

        let targetSize = selectionActionWindowSize()
        let anchorPoint = lastSelectionScreenPoint
            ?? NSPoint(x: window.frame.midX, y: window.frame.maxY)
        let origin = selectionActionWindowOrigin(
            near: anchorPoint,
            windowSize: targetSize
        )
        window.setFrame(NSRect(origin: origin, size: targetSize), display: true, animate: animated)

        if appState.inputOrigin == .selection {
            window.orderFrontRegardless()
            installSelectionDismissMonitors()
        }
    }

    private enum WindowPlacement {
        case compactSelectionMenu
        case quickAction
    }

    private func selectionActionWindowSize() -> NSSize {
        selectionActionShouldShowInlineResult ? selectionActionExpandedSize : selectionActionCompactSize
    }

    private func selectionActionWindowOrigin(
        near point: NSPoint,
        windowSize: NSSize
    ) -> NSPoint {
        let visibleFrame = NSScreen.screens
            .first(where: { NSMouseInRect(point, $0.frame, false) })?
            .visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let padding: CGFloat = 10
        let compactOrigin = preferredWindowOrigin(
            near: point,
            windowSize: selectionActionCompactSize,
            padding: padding,
            placement: .compactSelectionMenu
        )

        let extraHeight = max(0, windowSize.height - selectionActionCompactSize.height)
        let candidate = NSPoint(x: compactOrigin.x, y: compactOrigin.y - extraHeight)
        let clampedX = min(max(candidate.x, visibleFrame.minX + padding), visibleFrame.maxX - windowSize.width - padding)
        let clampedY = min(max(candidate.y, visibleFrame.minY + padding), visibleFrame.maxY - windowSize.height - padding)
        return NSPoint(x: clampedX, y: clampedY)
    }

    private func preferredWindowOrigin(
        near point: NSPoint,
        windowSize: NSSize,
        padding: CGFloat,
        placement: WindowPlacement
    ) -> NSPoint {
        let visibleFrame = NSScreen.screens
            .first(where: { NSMouseInRect(point, $0.frame, false) })?
            .visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let topSpace = visibleFrame.maxY - point.y
        let bottomSpace = point.y - visibleFrame.minY
        let rightSpace = visibleFrame.maxX - point.x
        let leftSpace = point.x - visibleFrame.minX

        let horizontalBias: CGFloat
        switch placement {
        case .compactSelectionMenu:
            horizontalBias = 0.18
        case .quickAction:
            horizontalBias = 0.28
        }

        let centeredX = point.x - windowSize.width * horizontalBias
        let aboveY = point.y - windowSize.height - padding
        let belowY = point.y + padding
        let rightX = point.x + padding
        let leftX = point.x - windowSize.width - padding

        let prefersBelow = topSpace < windowSize.height + 24 && bottomSpace > topSpace
        let prefersSide = max(leftSpace, rightSpace) > max(topSpace, bottomSpace) + 80 && windowSize.width <= max(leftSpace, rightSpace) - padding

        var candidate = NSPoint(x: centeredX, y: prefersBelow ? belowY : aboveY)

        if prefersSide {
            candidate.x = rightSpace >= leftSpace ? rightX : leftX
            candidate.y = point.y - min(windowSize.height * 0.24, 72)
        } else if prefersBelow {
            candidate.x = centeredX
            candidate.y = belowY
        }

        let clampedX = min(max(candidate.x, visibleFrame.minX + padding), visibleFrame.maxX - windowSize.width - padding)
        let clampedY = min(max(candidate.y, visibleFrame.minY + padding), visibleFrame.maxY - windowSize.height - padding)
        return NSPoint(x: clampedX, y: clampedY)
    }
}

final class WindowController: NSWindowController {
    enum WindowKind {
        case regular
        case nonActivatingPanel
    }

    init(
        title: String,
        frame: NSRect,
        contentView: AnyView,
        pinState: WindowPinState? = nil,
        windowLevel: NSWindow.Level = .normal,
        autoCollapseAtScreenEdge: Bool = false,
        windowKind: WindowKind = .regular,
        allowsResizing: Bool = false
    ) {
        let hosting = WindowHostingView(rootView: contentView)
        hosting.usesResizeCursorRects = allowsResizing
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        let window: NSWindow
        switch windowKind {
        case .regular:
            window = FloatingWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
        case .nonActivatingPanel:
            var styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
            if allowsResizing {
                styleMask.insert(.resizable)
            }
            window = SelectionActionWindow(
                contentRect: frame,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
        }
        window.title = title
        if let floatingWindow = window as? FloatingWindow {
            floatingWindow.autoCollapseAtScreenEdge = autoCollapseAtScreenEdge
        }
        window.center()
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        window.isMovableByWindowBackground = true
        window.level = windowLevel
        pinState?.attach(to: window)
        if allowsResizing {
            window.acceptsMouseMovedEvents = true
        }
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WindowHostingView: NSHostingView<AnyView> {
    var usesResizeCursorRects = false {
        didSet {
            guard usesResizeCursorRects != oldValue else {
                return
            }
            window?.invalidateCursorRects(for: self)
        }
    }

    private let resizeCursorThickness: CGFloat = 8

    override func resetCursorRects() {
        super.resetCursorRects()
        guard usesResizeCursorRects,
              let window,
              window.styleMask.contains(.resizable),
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        let canResizeHorizontally = Self.canResize(
            minimum: window.contentMinSize.width,
            maximum: window.contentMaxSize.width
        )
        let canResizeVertically = Self.canResize(
            minimum: window.contentMinSize.height,
            maximum: window.contentMaxSize.height
        )
        guard canResizeHorizontally || canResizeVertically else {
            return
        }

        let thickness = min(resizeCursorThickness, bounds.width / 2, bounds.height / 2)
        if canResizeHorizontally {
            let verticalInset = canResizeVertically ? thickness : 0
            let sideHeight = max(0, bounds.height - verticalInset * 2)
            addCursorRect(
                NSRect(x: bounds.minX, y: bounds.minY + verticalInset, width: thickness, height: sideHeight),
                cursor: .resizeLeftRight
            )
            addCursorRect(
                NSRect(x: bounds.maxX - thickness, y: bounds.minY + verticalInset, width: thickness, height: sideHeight),
                cursor: .resizeLeftRight
            )
        }
        if canResizeVertically {
            addCursorRect(
                NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: thickness),
                cursor: .resizeUpDown
            )
            addCursorRect(
                NSRect(x: bounds.minX, y: bounds.maxY - thickness, width: bounds.width, height: thickness),
                cursor: .resizeUpDown
            )
        }
    }

    private static func canResize(minimum: CGFloat, maximum: CGFloat) -> Bool {
        if maximum.isFinite {
            return maximum - minimum > 1
        }
        return true
    }
}

final class SelectionActionWindow: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53, modifiers.isEmpty, let onEscape {
                onEscape()
                return
            }
        }

        super.sendEvent(event)
    }
}

class FloatingWindow: NSWindow {
    var autoCollapseAtScreenEdge = false
    var onEscape: (() -> Void)?
    var onClose: (() -> Void)?
    var onKeyboardShortcut: ((KeyboardShortcutPreference) -> Bool)?
    var onCommandPaste: (() -> Bool)?
    private var expandedWidth: CGFloat = 360
    private let collapsedWidth: CGFloat = 42
    private let edgeTolerance: CGFloat = 24

    override func close() {
        onClose?()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53,
               modifiers.isEmpty,
               let textView = firstResponder as? NSTextView,
               textView.hasMarkedText() {
                super.sendEvent(event)
                return
            }
            if event.keyCode == 53, modifiers.isEmpty, let onEscape {
                onEscape()
                return
            }
            // 先走当前第一响应者的标准编辑命令，避免业务兜底吞掉 SwiftUI 的文本选区。
            if performStandardEditingCommand(for: event) {
                return
            }
            if modifiers == .command,
               event.charactersIgnoringModifiers?.lowercased() == "v",
               !isEditingText,
               let onCommandPaste,
               onCommandPaste() {
                return
            }
            if let shortcut = KeyboardShortcutPreference(event: event),
               let onKeyboardShortcut,
               onKeyboardShortcut(shortcut) {
                return
            }
        }

        super.sendEvent(event)
    }

    private var isEditingText: Bool {
        if let textView = firstResponder as? NSTextView {
            return textView.isEditable
        }
        if let textField = firstResponder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    private func performStandardEditingCommand(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        let action: Selector
        switch characters {
        case "a" where modifiers == .command:
            action = #selector(NSText.selectAll(_:))
        case "c" where modifiers == .command:
            action = #selector(NSText.copy(_:))
        case "v" where modifiers == .command:
            action = #selector(NSText.paste(_:))
        case "x" where modifiers == .command:
            action = #selector(NSText.cut(_:))
        case "z" where modifiers == .command || modifiers == [.command, .shift]:
            action = Selector((event.modifierFlags.contains(.shift) ? "redo:" : "undo:"))
        default:
            return false
        }

        return firstResponder?.tryToPerform(action, with: nil) == true
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        updateCollapseState()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        if frameRect.width > collapsedWidth {
            expandedWidth = frameRect.width
        }
        updateCollapseState()
    }

    override func mouseDown(with event: NSEvent) {
        if autoCollapseAtScreenEdge, frame.width <= collapsedWidth {
            expandFromCollapsedState()
            return
        }
        super.mouseDown(with: event)
    }

    private func updateCollapseState() {
        guard autoCollapseAtScreenEdge, let screen else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = self.frame
        let nearLeft = abs(frame.minX - visibleFrame.minX) <= edgeTolerance
        let nearRight = abs(frame.maxX - visibleFrame.maxX) <= edgeTolerance

        if nearLeft && frame.width > collapsedWidth {
            setFrame(
                NSRect(x: visibleFrame.minX, y: frame.minY, width: collapsedWidth, height: frame.height),
                display: true,
                animate: true
            )
        } else if nearRight && frame.width > collapsedWidth {
            setFrame(
                NSRect(x: visibleFrame.maxX - collapsedWidth, y: frame.minY, width: collapsedWidth, height: frame.height),
                display: true,
                animate: true
            )
        } else if !nearLeft && !nearRight && frame.width <= collapsedWidth {
            expandFromCollapsedState()
        }
    }

    private func expandFromCollapsedState() {
        guard let screen else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = self.frame
        let x = abs(frame.maxX - visibleFrame.maxX) <= edgeTolerance
            ? visibleFrame.maxX - expandedWidth
            : frame.minX
        setFrame(
            NSRect(x: x, y: frame.minY, width: expandedWidth, height: frame.height),
            display: true,
            animate: true
        )
    }
}
