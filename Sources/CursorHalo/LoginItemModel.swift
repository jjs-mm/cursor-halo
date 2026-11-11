import Combine
import Foundation
import ServiceManagement

/// The system owns login-item state. This seam also lets tests exercise failures
/// and external changes without registering a real login item.
protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

private struct MainAppLoginItemService: LoginItemServicing {
    private let service = SMAppService.mainApp
    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}

final class LoginItemModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?
    private let service: LoginItemServicing

    init(service: LoginItemServicing? = nil) {
        self.service = service ?? MainAppLoginItemService()
        refresh()
    }

    func refresh() {
        precondition(Thread.isMainThread)
        let status = service.status
        // Pending approval is registered intent, so the switch stays on while
        // the UI explains that macOS approval is still needed.
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
        switch status {
        case .enabled, .notRegistered, .requiresApproval, .notFound:
            // A newly installed app can report notFound before its first
            // registration. Absence by itself is an ordinary off state.
            errorMessage = nil
        @unknown default:
            errorMessage = "macOS couldn’t determine the launch-at-login setting. Check Login Items in System Settings."
        }
    }

    func setEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        refresh()
        guard isEnabled != enabled else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refresh()
        } catch {
            // A failed request can still change system state (for example,
            // registration can become pending approval). Never optimistically
            // leave the switch at the requested value.
            refresh()
            let action = enabled ? "enable" : "disable"
            errorMessage = "Couldn’t \(action) launch at login. \(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        precondition(Thread.isMainThread)
        service.openLoginItemsSettings()
    }
}
