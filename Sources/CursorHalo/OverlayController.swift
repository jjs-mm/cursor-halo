import AppKit
import QuartzCore

protocol PointerEventMonitoring {
    func addGlobal(handler: @escaping (NSEvent) -> Void) -> Any?
    func addLocal(handler: @escaping (NSEvent) -> NSEvent?) -> Any?
    func remove(_ monitor: Any)
}

private struct SystemPointerEventMonitoring: PointerEventMonitoring {
    private static let events: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .leftMouseDown, .rightMouseDown, .otherMouseDown
    ]
    func addGlobal(handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: Self.events, handler: handler)
    }
    func addLocal(handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: Self.events, handler: handler)
    }
    func remove(_ monitor: Any) { NSEvent.removeMonitor(monitor) }
}

/// A small click-through window follows the pointer. Mouse events drive updates;
/// Core Animation animates click feedback without a display timer or input tap.
final class OverlayController {
    private let monitoring: PointerEventMonitoring
    var onMonitoringError: ((String?) -> Void)?
    private var configuration = OverlayConfiguration()
    private let haloPanel = PointerPanel()
    private let haloView = HaloView()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pulses: [UUID: ClickPulse] = [:]
    private var pulseOrder: [UUID] = []
    private var sleeping = false
    private var sessionActive = true
    private var displaySleeping = false
    private var stopped = false

    init(monitoring: PointerEventMonitoring = SystemPointerEventMonitoring()) {
        self.monitoring = monitoring
        haloPanel.contentView = haloView
        observeLifecycle()
    }

    func update(configuration: OverlayConfiguration) {
        precondition(Thread.isMainThread)
        self.configuration = configuration.validated
        haloView.configuration = self.configuration
        if !configuration.showsClicks { removePulses() }
        reconcileActivity()
    }

    func stop() {
        precondition(Thread.isMainThread)
        stopped = true
        removeMonitors()
        haloPanel.orderOut(nil)
        removePulses()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private var shouldShow: Bool {
        configuration.isEnabled && !sleeping && sessionActive && !displaySleeping && !stopped
    }

    private func reconcileActivity() {
        if shouldShow {
            if installMonitors() {
                onMonitoringError?(nil)
                moveHalo()
            } else {
                haloPanel.orderOut(nil)
                removePulses()
                onMonitoringError?("Pointer monitoring couldn’t start. Turn highlighting off and on to retry.")
            }
        } else {
            removeMonitors()
            haloPanel.orderOut(nil)
            removePulses()
            onMonitoringError?(nil)
        }
    }

    private func installMonitors() -> Bool {
        if globalMonitor != nil && localMonitor != nil { return true }
        removeMonitors()
        globalMonitor = monitoring.addGlobal { [weak self] event in
            self?.handle(event)
        }
        localMonitor = monitoring.addLocal { [weak self] event in
            self?.handle(event)
            return event // Always deliver the original event to its intended control.
        }
        guard globalMonitor != nil && localMonitor != nil else {
            removeMonitors()
            return false
        }
        return true
    }

    private func removeMonitors() {
        if let globalMonitor { monitoring.remove(globalMonitor) }
        if let localMonitor { monitoring.remove(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard shouldShow else { return }
        // AppKit's mouseLocation and window frames use the same bottom-left
        // coordinate space, including displays above or left of the main display.
        let location = NSEvent.mouseLocation
        moveHalo(to: location)
        if configuration.showsClicks && [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            // Preserve the click's own location even if the pointer has moved by
            // the time the asynchronous global monitor delivers its event.
            let clickLocation = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            showPulse(at: clickLocation, secondary: event.type != .leftMouseDown)
        }
    }

    private func moveHalo(to location: NSPoint = NSEvent.mouseLocation) {
        guard shouldShow, globalMonitor != nil, localMonitor != nil else { return }
        let side = min(max(configuration.diameter, 24), 160) + 16
        let frame = NSRect(x: location.x - side / 2, y: location.y - side / 2, width: side, height: side)
        haloPanel.setFrame(frame, display: false)
        if !haloPanel.isVisible { haloPanel.orderFrontRegardless() }
    }

    private func showPulse(at location: NSPoint, secondary: Bool) {
        // Bound both the number of windows and pending cleanup work during fast clicks.
        if pulseOrder.count >= 8, let oldest = pulseOrder.first { removePulse(oldest) }
        let id = UUID()
        let pulse = ClickPulse(location: location, configuration: configuration, secondary: secondary)
        let cleanup = DispatchWorkItem { [weak self] in self?.removePulse(id) }
        pulse.cleanup = cleanup
        pulses[id] = pulse
        pulseOrder.append(id)
        pulse.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + ClickPulse.duration, execute: cleanup)
    }

    private func removePulse(_ id: UUID) {
        guard let pulse = pulses.removeValue(forKey: id) else { return }
        pulse.cleanup?.cancel()
        pulse.panel.orderOut(nil)
        pulse.panel.close()
        pulseOrder.removeAll { $0 == id }
    }

    private func removePulses() {
        for id in pulseOrder { removePulse(id) }
    }

    private func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.sleeping = true; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.sleeping = false; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaySleeping = false; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.removePulses(); $0.moveHalo() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.removePulses(); $0.moveHalo() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping (OverlayController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            action(self)
        }
        observers.append((center, token))
    }

    deinit {
        if let globalMonitor { monitoring.remove(globalMonitor) }
        if let localMonitor { monitoring.remove(localMonitor) }
        for (center, token) in observers { center.removeObserver(token) }
        for pulse in pulses.values { pulse.cleanup?.cancel() }
    }
}

private final class PointerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle]
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Avoid AppKit moving the halo inward at an edge or into another display.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class HaloView: NSView {
    var configuration = OverlayConfiguration() {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        let diameter = min(max(configuration.diameter, 24), 160)
        let lineWidth = min(max(configuration.lineWidth, 1), 10)
        let opacity = min(max(configuration.opacity, 0.1), 1)
        let circle = NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                            width: diameter, height: diameter).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = NSBezierPath(ovalIn: circle)
        if configuration.style == .disc {
            configuration.color.nsColor.withAlphaComponent(opacity * 0.24).setFill()
            path.fill()
        }
        NSColor.black.withAlphaComponent(opacity * 0.65).setStroke()
        path.lineWidth = lineWidth + 2
        path.stroke()
        configuration.color.nsColor.withAlphaComponent(opacity).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

private final class ClickPulse {
    static let duration: TimeInterval = 0.45
    let panel = PointerPanel()
    var cleanup: DispatchWorkItem?
    private let ring = CAShapeLayer()
    private let outline = CAShapeLayer()

    init(location: NSPoint, configuration: OverlayConfiguration, secondary: Bool) {
        let diameter = min(max(configuration.diameter, 24), 160)
        let side = diameter * 2 + 16
        panel.setFrame(NSRect(x: location.x - side / 2, y: location.y - side / 2, width: side, height: side), display: false)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        view.layer = CALayer()
        view.setAccessibilityElement(false)
        panel.contentView = view
        let secondaryColor: NSColor = configuration.color == .pink ? .systemCyan : .systemPink
        let color = secondary ? secondaryColor : configuration.color.nsColor
        for shape in [outline, ring] {
            shape.frame = view.bounds
            shape.path = CGPath(ellipseIn: view.bounds.insetBy(dx: 6, dy: 6), transform: nil)
            shape.fillColor = NSColor.clear.cgColor
            shape.opacity = 0
            shape.contentsScale = panel.backingScaleFactor
            view.layer?.addSublayer(shape)
        }
        outline.strokeColor = NSColor.black.withAlphaComponent(0.5).cgColor
        outline.lineWidth = 5
        ring.strokeColor = color.withAlphaComponent(configuration.opacity).cgColor
        ring.lineWidth = secondary ? 3.5 : 2.5
    }

    func start() {
        panel.orderFrontRegardless()
        // Read the preference for each click, so changes in System Settings take
        // effect immediately without asking for additional permissions.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for shape in [outline, ring] {
            if reduceMotion {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                shape.transform = CATransform3DMakeScale(0.6, 0.6, 1)
                shape.opacity = 0.9
                CATransaction.commit()
                continue
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            let expand = CABasicAnimation(keyPath: "transform.scale")
            expand.fromValue = 0.25
            expand.toValue = 1
            let group = CAAnimationGroup()
            group.animations = [fade, expand]
            group.duration = Self.duration
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shape.add(group, forKey: "click")
        }
    }
}
