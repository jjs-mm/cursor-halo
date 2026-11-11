import Foundation
import ServiceManagement
import Testing
@testable import CursorHalo

@Suite
@MainActor
struct LoginItemModelTests {
    @Test
    func initializationReadsStateWithoutRegistering() {
        for status in [SMAppService.Status.notRegistered, .enabled, .requiresApproval] {
            let service = FakeLoginItemService(status: status)
            let model = LoginItemModel(service: service)
            #expect(model.isEnabled == (status != .notRegistered))
            #expect(model.requiresApproval == (status == .requiresApproval))
            #expect(model.errorMessage == nil)
            #expect(service.registerCalls == 0)
            #expect(service.unregisterCalls == 0)
        }
    }

    @Test
    func enablingAndDisablingFollowConfirmedSystemState() {
        let service = FakeLoginItemService()
        let model = LoginItemModel(service: service)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(!model.requiresApproval)
        #expect(service.registerCalls == 1)

        model.setEnabled(false)
        #expect(!model.isEnabled)
        #expect(model.errorMessage == nil)
        #expect(service.unregisterCalls == 1)
    }

    @Test
    func pendingApprovalIsRegisteredIntentAndCanBeCancelled() {
        let service = FakeLoginItemService()
        service.registrationStatus = .requiresApproval
        let model = LoginItemModel(service: service)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.requiresApproval)

        model.setEnabled(true)
        #expect(service.registerCalls == 1, "Pending registration must not be repeatedly submitted.")
        model.setEnabled(false)
        #expect(!model.isEnabled)
        #expect(!model.requiresApproval)
        #expect(service.unregisterCalls == 1)
    }

    @Test
    func refreshTracksChangesMadeInSystemSettings() {
        let service = FakeLoginItemService(status: .enabled)
        let model = LoginItemModel(service: service)
        service.status = .requiresApproval
        model.refresh()
        #expect(model.isEnabled)
        #expect(model.requiresApproval)

        service.status = .notRegistered
        model.refresh()
        #expect(!model.isEnabled)
        #expect(!model.requiresApproval)
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
    }

    @Test
    func failedRegistrationAndUnregistrationRollBackToActualState() {
        let service = FakeLoginItemService()
        let model = LoginItemModel(service: service)
        service.registrationError = FakeLoginItemError()
        model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.errorMessage?.contains("Test operation denied") == true)

        service.registrationError = nil
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.errorMessage == nil)
        service.unregistrationError = FakeLoginItemError()
        model.setEnabled(false)
        #expect(model.isEnabled)
        #expect(model.errorMessage?.contains("Test operation denied") == true)
    }

    @Test
    func failedRegistrationStillReflectsPendingApprovalFromSystem() {
        let service = FakeLoginItemService()
        service.registrationError = FakeLoginItemError()
        service.statusOnRegistrationFailure = .requiresApproval
        let model = LoginItemModel(service: service)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.requiresApproval)
        #expect(model.errorMessage != nil)
    }

    @Test
    func coldInstallAbsenceIsNormalAndOnlyExplicitFailureShowsAnError() {
        let service = FakeLoginItemService(status: .notFound)
        let model = LoginItemModel(service: service)
        #expect(!model.isEnabled)
        #expect(!model.requiresApproval)
        #expect(model.errorMessage == nil)
        #expect(service.registerCalls == 0)

        service.registrationError = FakeLoginItemError()
        model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.errorMessage?.contains("Test operation denied") == true)
        service.status = .notRegistered
        model.refresh()
        #expect(model.errorMessage == nil)

        service.status = .notFound
        service.registrationError = nil
        model.setEnabled(true)
        #expect(model.isEnabled, "The first registration must work from the cold-install absence state.")
        #expect(model.errorMessage == nil)
    }

    @Test
    func openingSettingsDoesNotChangeRegistration() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let model = LoginItemModel(service: service)
        model.openLoginItemsSettings()
        #expect(service.settingsOpenCalls == 1)
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
        #expect(model.requiresApproval)
    }
}

private struct FakeLoginItemError: LocalizedError {
    var errorDescription: String? { "Test operation denied" }
}

private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    var registrationStatus: SMAppService.Status = .enabled
    var registrationError: Error?
    var unregistrationError: Error?
    var statusOnRegistrationFailure: SMAppService.Status?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var settingsOpenCalls = 0

    init(status: SMAppService.Status = .notRegistered) { self.status = status }

    func register() throws {
        registerCalls += 1
        if let registrationError {
            if let statusOnRegistrationFailure { status = statusOnRegistrationFailure }
            throw registrationError
        }
        status = registrationStatus
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }

    func openLoginItemsSettings() { settingsOpenCalls += 1 }
}
