import AppKit
import Testing
@testable import CursorHalo

struct KeyboardShortcutLabelTests {
    @Test
    func ordinaryTypingAndOptionTextAreExcluded() {
        for flags: NSEvent.ModifierFlags in [[], [.shift], [.capsLock], [.option], [.option, .shift]] {
            #expect(KeyboardShortcutLabel.make(keyCode: 8, modifiers: flags, characters: "c") == nil)
        }
        #expect(KeyboardShortcutLabel.make(keyCode: 36, modifiers: [], characters: "\r") == nil)
        #expect(KeyboardShortcutLabel.make(keyCode: 49, modifiers: [.shift], characters: " ") == nil)
        #expect(KeyboardShortcutLabel.make(keyCode: 49, modifiers: [.option], characters: "\u{00A0}") == nil)
        #expect(KeyboardShortcutLabel.make(keyCode: 49, modifiers: [.option, .shift], characters: "\u{00A0}") == nil)
    }

    @Test
    func shortcutsIncludeStableModifierOrderAndCurrentLayoutCharacter() {
        #expect(KeyboardShortcutLabel.make(keyCode: 8, modifiers: [.command], characters: "c") == "⌘ C")
        #expect(KeyboardShortcutLabel.make(keyCode: 8, modifiers: [.control], characters: "c") == "⌃ C")
        #expect(KeyboardShortcutLabel.make(keyCode: 8, modifiers: [.command, .shift, .control, .option], characters: "c") == "⌃⌥⇧⌘ C")
        #expect(KeyboardShortcutLabel.make(keyCode: 0, modifiers: [.command], characters: "q") == "⌘ Q")
        #expect(KeyboardShortcutLabel.make(keyCode: 0, modifiers: [.command], characters: "é") == "⌘ É")
    }

    @Test
    func navigationAndFunctionKeysHaveReadableLabels() {
        #expect(KeyboardShortcutLabel.make(keyCode: 123, modifiers: [.option], characters: nil) == "⌥ ←")
        #expect(KeyboardShortcutLabel.make(keyCode: 49, modifiers: [.command], characters: " ") == "⌘ Space")
        #expect(KeyboardShortcutLabel.make(keyCode: 36, modifiers: [.control], characters: "\r") == "⌃ Return")
        #expect(KeyboardShortcutLabel.make(keyCode: 122, modifiers: [.command], characters: nil) == "⌘ F1")
    }

    @Test
    func unknownKeysCannotLeakMultipleCharactersOrControlText() {
        for characters: String? in [nil, "", "private text", "\u{0}", "\n", "\u{F700}", " "] {
            #expect(KeyboardShortcutLabel.make(keyCode: 255, modifiers: [.command], characters: characters) == nil)
        }
    }
}

@Suite(.serialized)
@MainActor
struct KeyboardActivityTests {
    private func makeController(_ monitoring: FakeKeyboardMonitoring,
                                secureInput: @escaping () -> Bool = { false }) throws -> (KeyboardActivityController, NSWindow) {
        _ = NSApplication.shared
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = KeyboardActivityController(monitoring: monitoring, secureInputEnabled: secureInput,
            screenFrame: { NSRect(x: -1920, y: 0, width: 1920, height: 1080) })
        let panel = try #require(NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) })
        return (controller, panel)
    }

    @Test
    func disabledFeatureDoesNotObserveOrRequestPermission() throws {
        let monitoring = FakeKeyboardMonitoring()
        let (controller, panel) = try makeController(monitoring)
        defer { controller.stop(); panel.close() }
        controller.update(enabled: false)
        controller.refreshPermission()
        controller.requestPermission()
        #expect(monitoring.startCount == 0)
        #expect(monitoring.requestCount == 0)
        #expect(!panel.isVisible)
    }

    @Test
    func permissionIsRequestedOnlyByExplicitActionAndRefreshCanRetry() throws {
        let monitoring = FakeKeyboardMonitoring()
        monitoring.hasPermission = false
        let (controller, panel) = try makeController(monitoring)
        defer { controller.stop(); panel.close() }
        var error: String?
        controller.onMonitoringError = { error = $0 }
        controller.update(enabled: true)
        controller.refreshPermission()
        #expect(monitoring.startCount == 0)
        #expect(monitoring.requestCount == 0)
        #expect(error?.contains("Input Monitoring") == true)
        controller.requestPermission()
        #expect(monitoring.requestCount == 1)
        #expect(monitoring.startCount == 0)

        monitoring.hasPermission = true
        controller.refreshPermission()
        #expect(monitoring.startCount == 1)
        #expect(error == nil)
        controller.refreshPermission()
        #expect(monitoring.startCount == 1)
    }

    @Test
    func overlayUsesOneClickThroughNonactivatingPanelAndDisappearsOnDisable() throws {
        let monitoring = FakeKeyboardMonitoring()
        let (controller, panel) = try makeController(monitoring)
        defer { controller.stop(); panel.close() }
        let windowCount = NSApp.windows.count
        let keyWindow = NSApp.keyWindow
        controller.update(enabled: true)
        monitoring.onShortcut?("⌘ C")
        #expect(panel.isVisible)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.isOpaque)
        #expect(panel.contentView?.hitTest(.zero) == nil)
        #expect(NSApp.keyWindow === keyWindow)
        #expect(panel.frame.midX == -960)
        #expect(panel.frame.minY == 36)
        for _ in 0..<100 { monitoring.onShortcut?("⌘ V") }
        #expect(NSApp.windows.count == windowCount)
        let staleDelivery = monitoring.onShortcut
        controller.update(enabled: false)
        #expect(!panel.isVisible)
        #expect(!monitoring.active)
        #expect((panel.contentView?.subviews.first as? NSTextField)?.stringValue == "")
        staleDelivery?("⌘ C")
        #expect(!panel.isVisible)
    }

    @Test
    func secureInputAndPermissionRevocationClearTheDisplay() throws {
        let monitoring = FakeKeyboardMonitoring()
        var secure = false
        let (controller, panel) = try makeController(monitoring, secureInput: { secure })
        defer { controller.stop(); panel.close() }
        controller.update(enabled: true)
        monitoring.onShortcut?("⌘ C")
        #expect(panel.isVisible)
        secure = true
        monitoring.onShortcut?("⌘ V")
        #expect(!panel.isVisible)
        secure = false
        monitoring.onShortcut?("⌘ V")
        #expect(panel.isVisible)
        monitoring.hasPermission = false
        monitoring.onShortcut?("⌘ V")
        #expect(!panel.isVisible)
        #expect(!monitoring.active)
    }

    @Test
    func secureInputTransitionClearsBadgeWithoutAnotherKeyEvent() async throws {
        let monitoring = FakeKeyboardMonitoring()
        var secure = false
        let (controller, panel) = try makeController(monitoring, secureInput: { secure })
        defer { controller.stop(); panel.close() }
        controller.update(enabled: true)
        monitoring.onShortcut?("⌘ C")
        #expect(panel.isVisible)

        secure = true
        try await Task.sleep(for: .milliseconds(300))
        #expect(!panel.isVisible)
        #expect((panel.contentView?.subviews.first as? NSTextField)?.stringValue == "")
    }

    @Test
    func permissionRevocationClearsBadgeWithoutAnotherKeyEvent() async throws {
        let monitoring = FakeKeyboardMonitoring()
        let (controller, panel) = try makeController(monitoring)
        defer { controller.stop(); panel.close() }
        controller.update(enabled: true)
        monitoring.onShortcut?("⌘ C")
        #expect(panel.isVisible)

        monitoring.hasPermission = false
        try await Task.sleep(for: .milliseconds(300))
        #expect(!panel.isVisible)
        #expect(!monitoring.active)
    }

    @Test
    func failureIsReportedAndCanBeRetried() throws {
        let monitoring = FakeKeyboardMonitoring()
        monitoring.shouldStart = false
        let (controller, panel) = try makeController(monitoring)
        defer { controller.stop(); panel.close() }
        var error: String?
        controller.onMonitoringError = { error = $0 }
        controller.update(enabled: true)
        #expect(error != nil)
        #expect(!panel.isVisible)
        monitoring.shouldStart = true
        controller.refreshPermission()
        #expect(error == nil)
        monitoring.onShortcut?("⌘ C")
        #expect(panel.isVisible)
        monitoring.onFailure?()
        #expect(!panel.isVisible)
        #expect(!monitoring.active)
        #expect(error?.contains("stopped") == true)
    }

    @Test
    func sessionAndDisplaySleepStopObservationUntilActiveAgain() throws {
        let monitoring = FakeKeyboardMonitoring()
        let (controller, panel) = try makeController(monitoring)
        defer { controller.stop(); panel.close() }
        let center = NSWorkspace.shared.notificationCenter
        controller.update(enabled: true)
        monitoring.onShortcut?("⌘ C")
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(!monitoring.active)
        #expect(!panel.isVisible)
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!monitoring.active)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(monitoring.active)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        #expect(!monitoring.active)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(monitoring.active)
        controller.stop()
        controller.update(enabled: true)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(!monitoring.active)
    }

    @Test
    func shortcutReplacementExtendsExpiryAndClearsLabel() async throws {
        let monitoring = FakeKeyboardMonitoring()
        let (controller, panel) = try makeController(monitoring)
        defer { controller.stop(); panel.close() }
        controller.update(enabled: true)
        monitoring.onShortcut?("⌘ C")
        #expect(panel.isVisible)
        try await Task.sleep(for: .seconds(0.8))
        monitoring.onShortcut?("⌘ V")
        try await Task.sleep(for: .seconds(0.8))
        #expect(panel.isVisible, "The old shortcut's deadline must not remove its replacement.")
        #expect((panel.contentView?.subviews.first as? NSTextField)?.stringValue == "⌘ V")
        try await Task.sleep(for: .seconds(0.9))
        #expect(!panel.isVisible)
        #expect((panel.contentView?.subviews.first as? NSTextField)?.stringValue == "")
    }
}

private final class FakeKeyboardMonitoring: KeyboardEventMonitoring {
    var hasPermission = true
    var shouldStart = true
    var active = false
    var startCount = 0
    var requestCount = 0
    var onShortcut: ((String?) -> Void)?
    var onFailure: (() -> Void)?
    func requestPermission() { requestCount += 1 }
    func start(onShortcut: @escaping (String?) -> Void, onFailure: @escaping () -> Void) -> Bool {
        startCount += 1
        self.onShortcut = onShortcut
        self.onFailure = onFailure
        active = shouldStart
        return shouldStart
    }
    func stop() {
        active = false
        onShortcut = nil
        onFailure = nil
    }
}
