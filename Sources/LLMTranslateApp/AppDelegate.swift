import AppKit
import Combine
import SwiftUI
import LLMTranslateCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, HotKeyServiceDelegate, SelectionActionServiceDelegate, NSMenuDelegate {
    private let selectionActionCompactSize = NSSize(width: 254, height: 68)
    private let selectionActionExpandedSize = NSSize(width: 254, height: 170)

    private let appState = AppState()
    private let hotKeyService = HotKeyService()
    private let selectionActionService = SelectionActionService()
    private var cancellables: Set<AnyCancellable> = []
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var quickActionWindowController: WindowController?
    private var selectionActionWindowController: WindowController?
    private var floatingWindowController: WindowController?
    private var settingsWindowController: WindowController?
    private var selectionDismissMonitors: [Any] = []
    private var lastSelectionScreenPoint: NSPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKeyService.delegate = self
        hotKeyService.registerDefaultHotKey()
        selectionActionService.delegate = self
        configureStatusItem()
        configureWindows()
        observeAppState()
        Task {
            await appState.bootstrap()
            applyWindowPreferences()
            applySelectionActionPreference()
            refreshStatusMenuItem()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyService.unregister()
        selectionActionService.stop()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: "llmTranslate")
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
        menu.addItem(NSMenuItem(title: "打开悬浮组件", action: #selector(openFloatingWidget), keyEquivalent: "w"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "模型", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: "s"))
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
            contentView: AnyView(QuickActionView(appState: appState) { [weak self] in
                self?.quickActionWindowController?.close()
            })
        )
        selectionActionWindowController = WindowController(
            title: "选择操作",
            frame: NSRect(origin: .zero, size: selectionActionCompactSize),
            contentView: AnyView(SelectionActionView(appState: appState) { [weak self] task in
                self?.performSelectionAction(task)
            }),
            windowKind: .nonActivatingPanel
        )
        selectionActionWindowController?.window?.isOpaque = false
        selectionActionWindowController?.window?.backgroundColor = .clear
        selectionActionWindowController?.window?.hasShadow = false
        floatingWindowController = WindowController(
            title: "悬浮组件",
            frame: NSRect(x: 0, y: 0, width: 360, height: 520),
            contentView: AnyView(FloatingWidgetView(appState: appState)),
            autoCollapseAtScreenEdge: appState.preferences.autoCollapseWidget
        )
        settingsWindowController = WindowController(
            title: "模型",
            frame: NSRect(x: 0, y: 0, width: 860, height: 600),
            contentView: AnyView(SettingsView(appState: appState))
        )
    }

    @objc private func toggleMenu() {
        statusItem?.button?.performClick(nil)
    }

    @objc private func openQuickAction() {
        openQuickActionWindow(nearSelection: false)
    }

    @objc private func openFloatingWidget() {
        floatingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
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
        if shouldCaptureSelection {
            populateSelectedTextIfAvailable()
        } else {
            appState.setInputText("", origin: .manual)
            appState.statusMessage = L10n.text("Paste or type text", language: appState.preferences.appLanguage)
        }
        openQuickAction()
    }

    func selectionActionService(_ service: SelectionActionService, didFinishSelectionAt screenPoint: NSPoint) {
        guard appState.preferences.selectionActionEnabled else {
            return
        }

        guard let selectedText = SelectedTextService.captureSelectedText() else {
            if !SelectedTextService.isAccessibilityTrusted {
                appState.statusMessage = L10n.text("Enable Accessibility permission or paste text", language: appState.preferences.appLanguage)
            }
            return
        }

        appState.setInputText(selectedText, origin: .selection)
        appState.selectedTask = .translate
        appState.showSelectionInlineResult()
        appState.statusMessage = L10n.text("Captured selected text", language: appState.preferences.appLanguage)
        lastSelectionScreenPoint = screenPoint
        showSelectionAction(at: screenPoint)
        appState.runCurrentTask()
    }

    private func populateSelectedTextIfAvailable() {
        if let selectedText = SelectedTextService.captureSelectedText() {
            appState.setInputText(selectedText, origin: .selection)
            appState.statusMessage = L10n.text("Captured selected text", language: appState.preferences.appLanguage)
        } else if !SelectedTextService.isAccessibilityTrusted {
            SelectedTextService.clearCapturedSelectionSource()
            appState.statusMessage = L10n.text("Enable Accessibility permission or paste text", language: appState.preferences.appLanguage)
        } else if appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appState.setInputText("", origin: .manual)
            appState.statusMessage = L10n.text("Paste or type text", language: appState.preferences.appLanguage)
        }
    }

    private func showSelectionAction(at screenPoint: NSPoint) {
        guard appState.preferences.selectionActionEnabled else {
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
        window.orderFrontRegardless()
        installSelectionDismissMonitors()
    }

    private func performSelectionAction(_ task: TaskKind) {
        appState.selectedTask = task
        appState.showSelectionInlineResult()
        refreshSelectionActionWindowLayout(animated: false)
        appState.runCurrentTask()
    }

    private func closeSelectionAction() {
        removeSelectionDismissMonitors()
        selectionActionWindowController?.close()
    }

    private func installSelectionDismissMonitors() {
        removeSelectionDismissMonitors()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if event.window !== self.selectionActionWindowController?.window {
                    self.closeSelectionAction()
                }
            }
            return event
        }) {
            selectionDismissMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in
                guard let self else {
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

    private func observeAppState() {
        appState.$preferences
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyWindowPreferences()
                self?.applySelectionActionPreference()
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

    private func applyWindowPreferences() {
        guard let window = floatingWindowController?.window as? FloatingWindow else {
            return
        }
        window.autoCollapseAtScreenEdge = appState.preferences.autoCollapseWidget
        if appState.preferences.widgetVisibleOnAllSpaces {
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        } else {
            window.collectionBehavior = [.fullScreenAuxiliary, .managed]
        }
    }

    private func applySelectionActionPreference() {
        selectionActionService.setEnabled(appState.preferences.selectionActionEnabled)
        if !appState.preferences.selectionActionEnabled {
            closeSelectionAction()
        }
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
        return appState.statusMessage
    }

    private func refreshMenuTitles() {
        guard let menu = statusItem?.menu else {
            return
        }

        for item in menu.items {
            switch item.action {
            case #selector(openQuickAction):
                item.title = L10n.text("Open Quick Action", language: appState.preferences.appLanguage)
            case #selector(openFloatingWidget):
                item.title = L10n.text("Open Floating Widget", language: appState.preferences.appLanguage)
            case #selector(openSettings):
                if item.keyEquivalent == "," {
                    item.title = L10n.text("Models", language: appState.preferences.appLanguage)
                } else {
                    item.title = L10n.text("Settings", language: appState.preferences.appLanguage)
                }
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
        quickActionWindowController?.window?.title = appState.selectedTask.title(language: appState.preferences.appLanguage)
        if nearSelection {
            positionQuickActionWindowNearSelectionIfPossible()
        }
        quickActionWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        autoCollapseAtScreenEdge: Bool = false,
        windowKind: WindowKind = .regular
    ) {
        let hosting = NSHostingView(rootView: contentView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        let window: FloatingWindow
        switch windowKind {
        case .regular:
            window = FloatingWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
        case .nonActivatingPanel:
            window = SelectionActionWindow(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }
        window.title = title
        window.autoCollapseAtScreenEdge = autoCollapseAtScreenEdge
        window.center()
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        window.isMovableByWindowBackground = true
        window.level = .floating
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SelectionActionWindow: FloatingWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class FloatingWindow: NSWindow {
    var autoCollapseAtScreenEdge = false
    private var expandedWidth: CGFloat = 360
    private let collapsedWidth: CGFloat = 42
    private let edgeTolerance: CGFloat = 24

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
