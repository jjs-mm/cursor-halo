import Carbon
import Testing
@testable import CursorHalo

@Suite
@MainActor
struct GlobalShortcutTests {
    @Test
    func failedReplacementKeepsWorkingShortcutAndCallback() {
        let system = FakeHotKeySystem()
        let shortcut = GlobalShortcut(system: system)
        var toggles = 0
        shortcut.onToggle = { toggles += 1 }
        #expect(shortcut.register(.controlOptionH) == noErr)
        let original = system.registrations.keys.first!
        system.registrationStatus = OSStatus(eventHotKeyExistsErr)
        #expect(shortcut.register(.controlOptionC) == OSStatus(eventHotKeyExistsErr))
        #expect(shortcut.registeredShortcut == .controlOptionH)
        #expect(system.registrations[original] == .controlOptionH)
        #expect(system.removedIdentifiers.isEmpty)
        system.onPress?(original)
        #expect(toggles == 1)
    }

    @Test
    func successfulReplacementReleasesOldKeyAndIgnoresQueuedOldEvents() {
        let system = FakeHotKeySystem()
        let shortcut = GlobalShortcut(system: system)
        var toggles = 0
        shortcut.onToggle = { toggles += 1 }
        #expect(shortcut.register(.controlOptionH) == noErr)
        let original = system.registrations.keys.first!
        #expect(shortcut.register(.controlOptionC) == noErr)
        let replacement = system.registrations.keys.first!
        #expect(shortcut.registeredShortcut == .controlOptionC)
        #expect(system.removedIdentifiers == [original])
        system.onPress?(original)
        #expect(toggles == 0)
        system.onPress?(replacement)
        #expect(toggles == 1)
        #expect(shortcut.register(.controlOptionC) == noErr)
        #expect(system.registrationCalls == 2)
    }

    @Test
    func initialFailureAndHandlerFailureLeaveNoResourcesAndCanRetry() {
        let system = FakeHotKeySystem()
        let shortcut = GlobalShortcut(system: system)
        system.handlerStatus = OSStatus(eventNotHandledErr)
        #expect(shortcut.register(.controlOptionH) != noErr)
        #expect(system.registrationCalls == 0)
        #expect(shortcut.registeredShortcut == nil)

        system.handlerStatus = noErr
        system.registrationStatus = OSStatus(eventHotKeyExistsErr)
        #expect(shortcut.register(.controlOptionH) != noErr)
        #expect(system.onPress == nil)
        #expect(system.registrations.isEmpty)
        system.registrationStatus = noErr
        #expect(shortcut.register(.controlOptionH) == noErr)
        #expect(shortcut.registeredShortcut == .controlOptionH)
        shortcut.unregister()
        shortcut.unregister()
        #expect(system.registrations.isEmpty)
        #expect(system.onPress == nil)
        #expect(shortcut.registeredShortcut == nil)
    }
}

private final class FakeHotKeySystem: HotKeyRegistering {
    var handlerStatus: OSStatus = noErr
    var registrationStatus: OSStatus = noErr
    var onPress: ((UInt32) -> Void)?
    var registrations: [UInt32: ToggleShortcut] = [:]
    var removedIdentifiers: [UInt32] = []
    var registrationCalls = 0

    func installHandler(onPress: @escaping (UInt32) -> Void) -> OSStatus {
        if handlerStatus == noErr { self.onPress = onPress }
        return handlerStatus
    }
    func register(_ shortcut: ToggleShortcut, identifier: UInt32) -> OSStatus {
        registrationCalls += 1
        if registrationStatus == noErr { registrations[identifier] = shortcut }
        return registrationStatus
    }
    func unregister(identifier: UInt32) {
        registrations.removeValue(forKey: identifier)
        removedIdentifiers.append(identifier)
    }
    func removeHandler() { onPress = nil }
}
