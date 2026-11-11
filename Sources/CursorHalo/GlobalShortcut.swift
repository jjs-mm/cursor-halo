import Carbon

/// A small seam isolates operating-system registration from replacement logic.
protocol HotKeyRegistering: AnyObject {
    func installHandler(onPress: @escaping (UInt32) -> Void) -> OSStatus
    func register(_ shortcut: ToggleShortcut, identifier: UInt32) -> OSStatus
    func unregister(identifier: UInt32)
    func removeHandler()
}

/// Registers only the chosen shortcut. It does not monitor typed keys.
final class GlobalShortcut {
    private let system: HotKeyRegistering
    private var hasHandler = false
    private var activeIdentifier: UInt32?
    private var nextIdentifier: UInt32 = 1
    private(set) var registeredShortcut: ToggleShortcut?
    var onToggle: (() -> Void)?

    init(system: HotKeyRegistering = CarbonHotKeySystem()) {
        self.system = system
    }

    func register(_ shortcut: ToggleShortcut) -> OSStatus {
        if registeredShortcut == shortcut, activeIdentifier != nil { return noErr }
        if !hasHandler {
            let status = system.installHandler { [weak self] identifier in
                guard let self, identifier == self.activeIdentifier else { return }
                self.onToggle?()
            }
            guard status == noErr else { return status }
            hasHandler = true
        }
        let candidate = nextIdentifier
        nextIdentifier = nextIdentifier == UInt32.max ? 1 : nextIdentifier + 1
        let status = system.register(shortcut, identifier: candidate)
        guard status == noErr else {
            // Keep a previously working shortcut registered when the new choice
            // is occupied by another application.
            if activeIdentifier == nil {
                system.removeHandler()
                hasHandler = false
            }
            return status
        }
        let previous = activeIdentifier
        activeIdentifier = candidate
        registeredShortcut = shortcut
        if let previous { system.unregister(identifier: previous) }
        return noErr
    }

    func unregister() {
        if let activeIdentifier { system.unregister(identifier: activeIdentifier) }
        activeIdentifier = nil
        registeredShortcut = nil
        if hasHandler { system.removeHandler() }
        hasHandler = false
    }

    deinit { unregister() }
}

private final class CarbonHotKeySystem: HotKeyRegistering {
    private static let signature: OSType = 0x48414C4F
    private var handler: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var onPress: ((UInt32) -> Void)?

    func installHandler(onPress: @escaping (UInt32) -> Void) -> OSStatus {
        self.onPress = onPress
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == CarbonHotKeySystem.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let owner = Unmanaged<CarbonHotKeySystem>.fromOpaque(context).takeUnretainedValue()
            owner.onPress?(hotKeyID.id)
            return noErr
        }, 1, &eventType, context, &handler)
    }

    func register(_ shortcut: ToggleShortcut, identifier: UInt32) -> OSStatus {
        let key = shortcut == .controlOptionC ? kVK_ANSI_C : kVK_ANSI_H
        let modifiers = controlKey | (shortcut == .controlShiftH ? shiftKey : optionKey)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers),
            EventHotKeyID(signature: Self.signature, id: identifier), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &reference)
        if status == noErr, let reference { registrations[identifier] = reference }
        return status
    }

    func unregister(identifier: UInt32) {
        if let reference = registrations.removeValue(forKey: identifier) { UnregisterEventHotKey(reference) }
    }

    func removeHandler() {
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        onPress = nil
    }

    deinit {
        for reference in registrations.values { UnregisterEventHotKey(reference) }
        removeHandler()
    }
}
