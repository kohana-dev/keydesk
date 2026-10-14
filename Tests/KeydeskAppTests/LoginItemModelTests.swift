import Foundation
import Testing
@testable import KeydeskApp

@MainActor
struct LoginItemModelTests {
    @Test func initializationAndRefreshNeverRegisterOrUnregister() {
        let service = TestLoginItemService(status: .notRegistered)
        let model = LoginItemModel(service: service)
        #expect(!model.launchAtLogin)
        #expect(model.status == .notRegistered)
        service.status = .enabled
        model.refresh()
        #expect(model.launchAtLogin)
        service.status = .notRegistered
        model.refresh()
        #expect(!model.launchAtLogin)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
    }

    @Test func enablingAndDisablingUseOSStateAndAreIdempotent() async {
        let service = TestLoginItemService(status: .notRegistered)
        let model = LoginItemModel(service: service)
        await model.setLaunchAtLogin(true)
        #expect(model.status == .enabled)
        #expect(model.launchAtLogin)
        #expect(service.registerCount == 1)
        await model.setLaunchAtLogin(true)
        #expect(service.registerCount == 1)
        await model.setLaunchAtLogin(false)
        #expect(model.status == .notRegistered)
        #expect(!model.launchAtLogin)
        #expect(service.unregisterCount == 1)
        await model.setLaunchAtLogin(false)
        #expect(service.unregisterCount == 1)
        #expect(!model.changeFailed)
        #expect(!model.isChanging)
    }

    @Test func deniedRegistrationShowsApprovalStateAndCanBeRemoved() async {
        let service = TestLoginItemService(status: .notRegistered)
        service.registrationOutcome = .requiresApproval
        service.failRegistration = true
        let model = LoginItemModel(service: service)
        await model.setLaunchAtLogin(true)
        #expect(model.status == .requiresApproval)
        #expect(model.launchAtLogin)
        #expect(!model.changeFailed)
        #expect(!model.statusMessage.isEmpty)
        model.openSystemSettings()
        #expect(service.openSettingsCount == 1)
        await model.setLaunchAtLogin(false)
        #expect(model.status == .notRegistered)
        #expect(!model.launchAtLogin)
        #expect(service.unregisterCount == 1)
    }

    @Test func failureKeepsActualOSStateAndAllowsRetry() async {
        let service = TestLoginItemService(status: .notRegistered)
        service.registrationOutcome = .notRegistered
        service.failRegistration = true
        let model = LoginItemModel(service: service)
        await model.setLaunchAtLogin(true)
        #expect(!model.launchAtLogin)
        #expect(model.changeFailed)
        #expect(!model.failureMessage.contains("private-error-details"))
        #expect(!model.isChanging)
        service.failRegistration = false
        service.registrationOutcome = .enabled
        await model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin)
        #expect(!model.changeFailed)
        service.unregistrationOutcome = .enabled
        service.failUnregistration = true
        await model.setLaunchAtLogin(false)
        #expect(model.launchAtLogin)
        #expect(model.changeFailed)
        service.failUnregistration = false
        service.unregistrationOutcome = .notRegistered
        await model.setLaunchAtLogin(false)
        #expect(!model.launchAtLogin)
        #expect(!model.changeFailed)
    }

    @Test func refreshBeforeActionRespectsExternalChange() async {
        let service = TestLoginItemService(status: .enabled)
        let model = LoginItemModel(service: service)
        service.status = .notRegistered
        await model.setLaunchAtLogin(true)
        #expect(service.registerCount == 1)
        #expect(model.status == .enabled)
        service.status = .notRegistered
        await model.setLaunchAtLogin(false)
        #expect(service.unregisterCount == 0)
        #expect(!model.launchAtLogin)
    }

    @Test func externalStateChangeClearsOutdatedFailure() async {
        let service = TestLoginItemService(status: .notRegistered)
        service.registrationOutcome = .notRegistered
        service.failRegistration = true
        let model = LoginItemModel(service: service)
        await model.setLaunchAtLogin(true)
        #expect(model.changeFailed)
        service.status = .enabled
        model.refresh()
        #expect(model.launchAtLogin)
        #expect(!model.changeFailed)
    }

    @Test func secondChangeIsIgnoredWhileUnregistrationIsPending() async {
        let service = TestLoginItemService(status: .enabled)
        service.suspendUnregistration = true
        let model = LoginItemModel(service: service)
        let firstChange = Task { await model.setLaunchAtLogin(false) }
        for _ in 0..<1_000 {
            if service.pendingUnregistration != nil { break }
            await Task.yield()
        }
        #expect(service.pendingUnregistration != nil)
        #expect(model.isChanging)
        #expect(!model.canChange)
        await model.setLaunchAtLogin(true)
        #expect(service.registerCount == 0)
        await model.setLaunchAtLogin(false)
        #expect(service.unregisterCount == 1)
        service.completeUnregistration()
        await firstChange.value
        #expect(!model.isChanging)
        #expect(model.status == .notRegistered)
    }

    @Test func unavailableServiceCannotBeChanged() async {
        let service = TestLoginItemService(status: .unavailable)
        let model = LoginItemModel(service: service)
        await model.setLaunchAtLogin(true)
        await model.setLaunchAtLogin(false)
        #expect(!model.canChange)
        #expect(!model.launchAtLogin)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
        #expect(!model.statusMessage.isEmpty)
    }

    @Test func missingRecordCanBeRegisteredAndFailureRemainsRetryable() async {
        let service = TestLoginItemService(status: .notFound)
        let model = LoginItemModel(service: service)
        #expect(model.canChange)
        #expect(!model.launchAtLogin)
        await model.setLaunchAtLogin(false)
        #expect(service.unregisterCount == 0)
        service.registrationOutcome = .notFound
        service.failRegistration = true
        await model.setLaunchAtLogin(true)
        #expect(model.status == .notFound)
        #expect(model.changeFailed)
        #expect(model.canChange)
        service.registrationOutcome = .enabled
        service.failRegistration = false
        await model.setLaunchAtLogin(true)
        #expect(service.registerCount == 2)
        #expect(model.status == .enabled)
        #expect(model.launchAtLogin)
        #expect(!model.changeFailed)
    }

    @Test func serviceReturningUnexpectedOSStateDoesNotPretendSuccess() async {
        let service = TestLoginItemService(status: .notRegistered)
        service.registrationOutcome = .notRegistered
        let model = LoginItemModel(service: service)
        await model.setLaunchAtLogin(true)
        #expect(!model.launchAtLogin)
        #expect(model.changeFailed)
    }

    @Test func onlyOfficialInstalledNonDemoBundleCanManageLoginItems() {
        let appURL = URL(fileURLWithPath: "/Applications/Cellar.app")
        #expect(SystemLoginItemService.canManageLoginItem(bundleIdentifier: "com.keydesk.local", bundleURL: appURL, arguments: []))
        for identifier in [nil, "com.keydesk.qa", "com.keydesk.local.qa", "org.swift.swiftpm"] {
            #expect(!SystemLoginItemService.canManageLoginItem(bundleIdentifier: identifier, bundleURL: appURL, arguments: []))
        }
        for arguments in [["Cellar", "--demo"], ["Cellar", "--keychain-self-test"]] {
            #expect(!SystemLoginItemService.canManageLoginItem(bundleIdentifier: "com.keydesk.local", bundleURL: appURL, arguments: arguments))
        }
        #expect(!SystemLoginItemService.canManageLoginItem(bundleIdentifier: "com.keydesk.local", bundleURL: URL(fileURLWithPath: "/tmp/KeydeskDesktop"), arguments: []))
        #expect(SystemLoginItemService().status == .unavailable)
    }
}

@MainActor
private final class TestLoginItemService: LoginItemService {
    var status: LoginItemStatus
    var registerCount = 0
    var unregisterCount = 0
    var openSettingsCount = 0
    var registrationOutcome: LoginItemStatus = .enabled
    var unregistrationOutcome: LoginItemStatus = .notRegistered
    var failRegistration = false
    var failUnregistration = false
    var suspendUnregistration = false
    var pendingUnregistration: CheckedContinuation<Void, Never>?

    init(status: LoginItemStatus) { self.status = status }

    func register() throws {
        registerCount += 1
        status = registrationOutcome
        if failRegistration { throw TestFailure() }
    }

    func unregister() async throws {
        unregisterCount += 1
        if suspendUnregistration {
            await withCheckedContinuation { pendingUnregistration = $0 }
        }
        status = unregistrationOutcome
        if failUnregistration { throw TestFailure() }
    }

    func completeUnregistration() {
        pendingUnregistration?.resume()
        pendingUnregistration = nil
    }

    func openSystemSettings() { openSettingsCount += 1 }

    private struct TestFailure: LocalizedError {
        var errorDescription: String? { "private-error-details" }
    }
}
