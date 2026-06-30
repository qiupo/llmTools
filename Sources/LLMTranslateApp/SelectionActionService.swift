import AppKit

@MainActor
protocol SelectionActionServiceDelegate: AnyObject {
    func selectionActionService(_ service: SelectionActionService, didFinishSelectionAt screenPoint: NSPoint)
}

@MainActor
final class SelectionActionService {
    weak var delegate: SelectionActionServiceDelegate?

    private var isEnabled = false
    private var monitors: [Any] = []
    private var dragStartPoint: NSPoint?
    private var hasDragged = false
    private var mouseDownClickCount = 0
    private var lastTriggerDate = Date.distantPast
    private let minimumDragDistance: CGFloat = 8
    private let minimumTriggerInterval: TimeInterval = 0.8
    private let selectionSettlingDelay: TimeInterval = 0.18

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
    }

    private func removeMonitors() {
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

    private func handleMouseUp(_ event: NSEvent, at screenPoint: NSPoint) {
        defer {
            dragStartPoint = nil
            hasDragged = false
            mouseDownClickCount = 0
        }

        guard isEnabled else {
            return
        }

        let triggeredBySelectionGesture = hasDragged || event.clickCount >= 2 || mouseDownClickCount >= 2
        guard triggeredBySelectionGesture else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerDate) >= minimumTriggerInterval else {
            return
        }
        lastTriggerDate = now

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(selectionSettlingDelay * 1_000_000_000))
            guard isEnabled else {
                return
            }
            delegate?.selectionActionService(self, didFinishSelectionAt: screenPoint)
        }
    }
}
