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
            start()
        } else {
            stop()
        }
    }

    func start() {
        isEnabled = true
        resetGestureState()
        lastTriggerDate = .distantPast

        guard monitors.isEmpty else {
            return
        }

        addMonitor(for: .leftMouseDown) { [weak self] event in
            self?.handleMouseDown(event)
        }
        addMonitor(for: .leftMouseDragged) { [weak self] event in
            self?.handleMouseDragged(event)
        }
        addMonitor(for: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
        }
    }

    func stop() {
        isEnabled = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        resetGestureState()
        lastTriggerDate = .distantPast
    }

    private func resetGestureState() {
        dragStartPoint = nil
        hasDragged = false
        mouseDownClickCount = 0
    }

    private func addMonitor(for mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (NSEvent) -> Void) {
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            Task { @MainActor in
                handler(event)
            }
        }) else {
            return
        }
        monitors.append(monitor)
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard isEnabled else {
            resetGestureState()
            return
        }

        dragStartPoint = NSEvent.mouseLocation
        hasDragged = false
        mouseDownClickCount = event.clickCount
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard isEnabled, let dragStartPoint else {
            return
        }

        let currentPoint = NSEvent.mouseLocation
        let distance = hypot(currentPoint.x - dragStartPoint.x, currentPoint.y - dragStartPoint.y)
        if distance >= minimumDragDistance {
            hasDragged = true
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
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

        let point = NSEvent.mouseLocation
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(selectionSettlingDelay * 1_000_000_000))
            guard isEnabled else {
                return
            }
            delegate?.selectionActionService(self, didFinishSelectionAt: point)
        }
    }
}
