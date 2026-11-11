import AppKit
import Carbon

protocol KeyboardEventMonitoring: AnyObject {
    var hasPermission: Bool { get }
    func requestPermission()
    func start(onShortcut: @escaping (String?) -> Void, onFailure: @escaping () -> Void) -> Bool
    func stop()
}

/// Produces one shortcut label, never a buffer of typed text. Option-only
/// printable combinations are text input on many Mac keyboard layouts.
enum KeyboardShortcutLabel {
    static func accepts(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(.command) || modifiers.contains(.control) ||
            // Option-Space inserts a nonbreaking space rather than a shortcut.
            (modifiers.contains(.option) && keyCode != 49 && specialKeys[keyCode] != nil)
    }

    static func make(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> String? {
        guard accepts(keyCode: keyCode, modifiers: modifiers) else { return nil }
        let key: String
        if let special = specialKeys[keyCode] {
            key = special
        } else {
            guard let characters, characters.count == 1,
                  characters.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0) &&
                      !CharacterSet.whitespacesAndNewlines.contains($0) &&
                      !(0xF700...0xF8FF).contains($0.value)
                  }) else { return nil }
            key = characters.uppercased()
        }
        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }
        return prefix + " " + key
    }

    private static let specialKeys: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20"
    ]
}

final class KeyboardActivityController {
    static let displayDuration: TimeInterval = 1.5
    var onMonitoringError: ((String?) -> Void)?
    private let monitoring: KeyboardEventMonitoring
    private let secureInputEnabled: () -> Bool
    private let screenFrame: () -> NSRect?
    private let panel = KeyboardActivityPanel()
    private let label = NSTextField(labelWithString: "")
    private var cleanup: DispatchSourceTimer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var enabled = false
    private var monitoringActive = false
    private var sleeping = false
    private var displaySleeping = false
    private var sessionActive = true
    private var stopped = false

    init(monitoring: KeyboardEventMonitoring = SystemKeyboardEventMonitoring(),
         secureInputEnabled: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         screenFrame: @escaping () -> NSRect? = {
             let pointer = NSEvent.mouseLocation
             return (NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main)?.visibleFrame
         }) {
        self.monitoring = monitoring
        self.secureInputEnabled = secureInputEnabled
        self.screenFrame = screenFrame
        let view = KeyboardActivityView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.84).cgColor
        view.layer?.cornerRadius = 14
        label.font = .systemFont(ofSize: 26, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.setAccessibilityElement(false)
        view.addSubview(label)
        panel.contentView = view
        observeLifecycle()
    }

    func update(enabled: Bool) {
        precondition(Thread.isMainThread)
        self.enabled = enabled
        reconcileActivity()
    }

    func refreshPermission() {
        precondition(Thread.isMainThread)
        reconcileActivity()
    }

    /// Only the explicit settings button calls this; enabling the preference or
    /// launching with it saved never opens an operating-system permission prompt.
    func requestPermission() {
        precondition(Thread.isMainThread)
        guard enabled && !stopped else { return }
        monitoring.requestPermission()
        reconcileActivity()
    }

    func stop() {
        precondition(Thread.isMainThread)
        stopped = true
        suspend()
        onMonitoringError?(nil)
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private var shouldMonitor: Bool {
        enabled && !stopped && !sleeping && !displaySleeping && sessionActive
    }

    private func reconcileActivity() {
        guard shouldMonitor else {
            suspend()
            onMonitoringError?(nil)
            return
        }
        guard monitoring.hasPermission else {
            suspend()
            onMonitoringError?("Allow Input Monitoring to show shortcuts. If you just granted access, quit and reopen Cursor Halo.")
            return
        }
        if !monitoringActive {
            monitoringActive = monitoring.start(onShortcut: { [weak self] text in
                self?.show(text)
            }, onFailure: { [weak self] in
                guard let self else { return }
                self.suspend()
                self.onMonitoringError?("Keyboard monitoring stopped. Check Input Monitoring, then turn this option off and on.")
            })
        }
        if monitoringActive {
            if secureInputEnabled() { clear() }
            onMonitoringError?(nil)
        } else {
            suspend()
            onMonitoringError?("Keyboard monitoring couldn’t start. Check Input Monitoring, then quit and reopen Cursor Halo.")
        }
    }

    private func suspend() {
        monitoring.stop()
        monitoringActive = false
        clear()
    }

    private func show(_ text: String?) {
        guard shouldMonitor, monitoringActive, !secureInputEnabled(), let text else {
            clear()
            return
        }
        // Permission can be revoked while the option is enabled.
        guard monitoring.hasPermission else { reconcileActivity(); return }
        label.stringValue = text
        label.sizeToFit()
        guard let visibleFrame = screenFrame() else {
            clear()
            return
        }
        let width = min(max(120, label.frame.width + 48), max(120, visibleFrame.width - 32))
        let height: CGFloat = 62
        panel.setFrame(NSRect(x: visibleFrame.midX - width / 2, y: visibleFrame.minY + 36,
                              width: width, height: height), display: false)
        label.frame = NSRect(x: 24, y: (height - label.frame.height) / 2,
                             width: width - 48, height: label.frame.height)
        panel.orderFrontRegardless()
        if cleanup == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.setEventHandler { [weak self] in self?.clear() }
            cleanup = timer
            timer.schedule(deadline: .now() + Self.displayDuration)
            timer.resume()
        } else {
            // Reschedule one timer rather than queueing work for every key repeat.
            cleanup?.schedule(deadline: .now() + Self.displayDuration)
        }
    }

    private func clear() {
        cleanup?.cancel()
        cleanup = nil
        label.stringValue = ""
        panel.orderOut(nil)
    }

    private func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.sleeping = true; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.sleeping = false; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaySleeping = false; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true; $0.reconcileActivity() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.clear() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.clear() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping (KeyboardActivityController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            action(self)
        }
        observers.append((center, token))
    }

    deinit {
        monitoring.stop()
        cleanup?.cancel()
        for (center, token) in observers { center.removeObserver(token) }
    }
}

private final class KeyboardActivityPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle]
        setAccessibilityElement(false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class KeyboardActivityView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class SystemKeyboardEventMonitoring: KeyboardEventMonitoring {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var onShortcut: ((String?) -> Void)?
    private var onFailure: (() -> Void)?
    var hasPermission: Bool { CGPreflightListenEventAccess() }

    func requestPermission() {
        if !CGRequestListenEventAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func start(onShortcut: @escaping (String?) -> Void, onFailure: @escaping () -> Void) -> Bool {
        stop()
        guard hasPermission else { return false }
        self.onShortcut = onShortcut
        self.onFailure = onFailure
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
            callback: { _, type, event, context in
                if let context {
                    Unmanaged<SystemKeyboardEventMonitoring>.fromOpaque(context).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: context),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            stop()
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else { stop(); return false }
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        onShortcut = nil
        onFailure = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout {
            if let tap, hasPermission {
                CGEvent.tapEnable(tap: tap, enable: true)
                if CGEvent.tapIsEnabled(tap: tap) { return }
            }
            onFailure?()
            return
        }
        if type == .tapDisabledByUserInput { onFailure?(); return }
        guard type == .keyDown else { return }
        guard !IsSecureEventInputEnabled() else { onShortcut?(nil); return }
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        // Reject regular typing before asking AppKit for a character label.
        guard KeyboardShortcutLabel.accepts(keyCode: keyCode, modifiers: modifiers) else { return }
        guard let label = KeyboardShortcutLabel.make(keyCode: keyCode, modifiers: modifiers,
            characters: NSEvent(cgEvent: event)?.charactersIgnoringModifiers) else { return }
        onShortcut?(label)
    }

    deinit { stop() }
}
