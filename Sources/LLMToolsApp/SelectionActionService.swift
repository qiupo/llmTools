import AppKit

@MainActor
protocol SelectionActionServiceDelegate: AnyObject {
    func selectionActionService(
        _ service: SelectionActionService,
        didTriggerSelectionAt screenPoint: NSPoint,
        source: SelectionActionTriggerSource
    )
}

enum SelectionActionTriggerSource {
    case mouseDrag
    case doubleClick
    case selectAllShortcut
}

@MainActor
final class SelectionActionService {
    weak var delegate: SelectionActionServiceDelegate?

    private var isEnabled = false
    private var enabledTriggerSources: Set<SelectionActionTriggerSource> = [.mouseDrag, .doubleClick]
    private var monitors: [Any] = []
    private var pendingTriggerTask: Task<Void, Never>?
    private var dragStartPoint: NSPoint?
    private var hasDragged = false
    private var mouseDownClickCount = 0
    private var lastTriggerDate = Date.distantPast
    private let minimumDragDistance: CGFloat = 8
    private let minimumTriggerInterval: TimeInterval = 0.8
    private let selectionSettlingDelay: TimeInterval = 0.18

    func setEnabledTriggerSources(_ sources: Set<SelectionActionTriggerSource>) {
        enabledTriggerSources = sources
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            installFreshMonitors()
            isEnabled = true
        } else {
            isEnabled = false
            removeMonitors()
        }
        resetGestureState()
        lastTriggerDate = .distantPast
    }

    func start() {
        installFreshMonitors()
        isEnabled = true
        resetGestureState()
        lastTriggerDate = .distantPast
    }

    func stop() {
        isEnabled = false
        removeMonitors()
        resetGestureState()
        lastTriggerDate = .distantPast
    }

    private func installFreshMonitors() {
        removeMonitors()

        addMonitor(for: .leftMouseDown) { [weak self] event, screenPoint in
            self?.handleMouseDown(event, at: screenPoint)
        }
        addMonitor(for: .leftMouseDragged) { [weak self] _, screenPoint in
            self?.handleMouseDragged(at: screenPoint)
        }
        addMonitor(for: .leftMouseUp) { [weak self] event, screenPoint in
            self?.handleMouseUp(event, at: screenPoint)
        }
        addMonitor(for: .keyDown) { [weak self] event, screenPoint in
            self?.handleKeyDown(event, at: screenPoint)
        }
    }

    private func removeMonitors() {
        cancelPendingTrigger(resetThrottle: false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func resetGestureState() {
        dragStartPoint = nil
        hasDragged = false
        mouseDownClickCount = 0
    }

    private func addMonitor(for mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (NSEvent, NSPoint) -> Void) {
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            let screenPoint = NSEvent.mouseLocation
            Task { @MainActor in
                handler(event, screenPoint)
            }
        }) else {
            return
        }
        monitors.append(monitor)
    }

    private func handleMouseDown(_ event: NSEvent, at screenPoint: NSPoint) {
        guard isEnabled else {
            resetGestureState()
            return
        }

        dragStartPoint = screenPoint
        hasDragged = false
        mouseDownClickCount = event.clickCount
    }

    private func handleMouseDragged(at screenPoint: NSPoint) {
        guard isEnabled, let dragStartPoint else {
            return
        }

        let distance = hypot(screenPoint.x - dragStartPoint.x, screenPoint.y - dragStartPoint.y)
        if distance >= minimumDragDistance {
            hasDragged = true
        }
    }

    private func handleKeyDown(_ event: NSEvent, at screenPoint: NSPoint) {
        guard isEnabled,
              !SelectedTextService.isSyntheticShortcutEvent(event),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else {
            return
        }

        switch characters {
        case "a":
            let disallowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift]
            guard flags.intersection(disallowedModifiers).isEmpty,
                  !event.isARepeat else {
                return
            }
            guard enabledTriggerSources.contains(.selectAllShortcut) else {
                return
            }
            scheduleTrigger(source: .selectAllShortcut, at: screenPoint)
        case "c":
            let disallowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift]
            guard flags.intersection(disallowedModifiers).isEmpty else {
                return
            }
            SelectedTextService.noteUserCopyShortcut()
            cancelPendingTrigger(resetThrottle: true)
        default:
            break
        }
    }

    private func handleMouseUp(_ event: NSEvent, at screenPoint: NSPoint) {
        defer {
            dragStartPoint = nil
            hasDragged = false
            mouseDownClickCount = 0
        }

        guard isEnabled else {
            return
        }

        let source: SelectionActionTriggerSource?
        if event.clickCount >= 2 || mouseDownClickCount >= 2 {
            source = .doubleClick
        } else if hasDragged {
            source = .mouseDrag
        } else {
            source = nil
        }

        guard let source,
              enabledTriggerSources.contains(source) else {
            return
        }

        scheduleTrigger(source: source, at: screenPoint)
    }

    private func scheduleTrigger(source: SelectionActionTriggerSource, at screenPoint: NSPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerDate) >= minimumTriggerInterval else {
            return
        }
        lastTriggerDate = now

        cancelPendingTrigger(resetThrottle: false)
        pendingTriggerTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(selectionSettlingDelay * 1_000_000_000))
            guard !Task.isCancelled, isEnabled else {
                return
            }
            delegate?.selectionActionService(self, didTriggerSelectionAt: screenPoint, source: source)
            pendingTriggerTask = nil
        }
    }

    private func cancelPendingTrigger(resetThrottle: Bool) {
        pendingTriggerTask?.cancel()
        pendingTriggerTask = nil
        if resetThrottle {
            lastTriggerDate = .distantPast
        }
    }
}
