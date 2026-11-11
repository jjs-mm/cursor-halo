import AppKit
import SwiftUI

@main
enum CursorHaloApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showSettingsNotification = Notification.Name("local.personal.CursorHalo.showSettings")
    private let settings = SettingsModel()
    private let loginItem = LoginItemModel()
    private let overlay = OverlayController()
    private let keyboardActivity = KeyboardActivityController()
    private let shortcut = GlobalShortcut()
    private var instanceLock: SingleInstanceLock?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var pendingReveal = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Observe before claiming the lock so a simultaneous second launch
        // cannot send its reveal request before the winner is listening.
        DistributedNotificationCenter.default().addObserver(self,
            selector: #selector(revealSettings(_:)), name: Self.showSettingsNotification, object: nil)
        do {
            let lockURL = SingleInstanceLock.applicationLockURL
            if let lock = try SingleInstanceLock.acquire(at: lockURL) {
                instanceLock = lock
            } else {
                DistributedNotificationCenter.default().post(name: Self.showSettingsNotification, object: nil)
                // If the incumbent was already quitting, its observer may no
                // longer receive that request. Start this copy once it exits.
                guard let lock = try SingleInstanceLock.acquire(at: lockURL, waitingUpTo: 2) else {
                    NSApp.terminate(nil)
                    return
                }
                instanceLock = lock
                pendingReveal = true
            }
        } catch {
            NSApp.setActivationPolicy(.regular)
            let alert = NSAlert()
            alert.messageText = "Cursor Halo couldn’t start"
            alert.informativeText = "The app couldn’t secure its single-instance lock: \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Cursor Halo")
        }
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView:
            SettingsView(settings: settings, loginItem: loginItem,
                requestKeyboardPermission: { [weak self] in self?.keyboardActivity.requestPermission() },
                quit: { NSApp.terminate(nil) }))
        settings.onChange = { [weak self] in self?.applySettings() }
        overlay.onMonitoringError = { [weak self] in self?.settings.monitoringError = $0 }
        keyboardActivity.onMonitoringError = { [weak self] in self?.settings.keyboardMonitoringError = $0 }
        shortcut.onToggle = { [weak self] in self?.settings.isEnabled.toggle() }
        applySettings()

        if pendingReveal {
            pendingReveal = false
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }

        if !UserDefaults.standard.bool(forKey: "hasOpenedSettings") || CommandLine.arguments.contains("--show-settings") {
            UserDefaults.standard.set(true, forKey: "hasOpenedSettings")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItem.refresh()
        keyboardActivity.refreshPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        overlay.stop()
        keyboardActivity.stop()
        shortcut.unregister()
    }

    private func applySettings() {
        overlay.update(configuration: settings.configuration)
        keyboardActivity.update(enabled: settings.isEnabled && settings.showsKeyboardActivity)
        let requestedShortcut = settings.shortcut
        let status = shortcut.register(requestedShortcut)
        if status == noErr {
            settings.shortcutError = nil
        } else if let activeShortcut = shortcut.registeredShortcut {
            // Restore the picker and stored preference to the shortcut that
            // actually works. The nested change succeeds without re-registering.
            if settings.shortcut != activeShortcut { settings.shortcut = activeShortcut }
            settings.shortcutError = "\(requestedShortcut.title) is unavailable. Keeping \(activeShortcut.title). (\(status))"
        } else {
            settings.shortcutError = "Shortcut unavailable. Choose another combination. (\(status))"
        }
        let image = NSImage(systemSymbolName: settings.isEnabled ? "scope" : "circle.dashed", accessibilityDescription: "Cursor Halo")
        image?.isTemplate = true
        statusItem.button?.image = image
        let shortcutLabel = shortcut.registeredShortcut?.title ?? "Shortcut unavailable"
        statusItem.button?.toolTip = "Cursor Halo · \(settings.isEnabled ? "On" : "Paused") · \(shortcutLabel)"
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            settings.isEnabled.toggle()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showSettings()
        }
    }

    @objc private func revealSettings(_ notification: Notification) {
        if statusItem == nil { pendingReveal = true }
        else { showSettings() }
    }

    private func showSettings() {
        guard let button = statusItem?.button else { return }
        loginItem.refresh()
        keyboardActivity.refreshPermission()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.acceptsMouseMovedEvents = true
        popover.contentViewController?.view.window?.makeKey()
    }
}
