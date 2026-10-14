import Foundation
import Observation
import KeydeskCore

@MainActor @Observable
final class LoginItemModel {
    private(set) var status: LoginItemStatus
    private(set) var isChanging = false
    private(set) var changeFailed = false
    @ObservationIgnored private let service: any LoginItemService

    init(service: any LoginItemService = SystemLoginItemService()) {
        self.service = service
        status = service.status
    }

    /// Reflects the OS registration, including an item awaiting macOS approval.
    /// This value is never persisted separately or automatically enabled at launch.
    var launchAtLogin: Bool {
        get { status.isRegistered }
        set { Task { await setLaunchAtLogin(newValue) } }
    }

    // A valid main app can register even when macOS cannot find an old record.
    // Only unsupported demo/test contexts and an in-flight change block actions.
    var canChange: Bool { status != .unavailable && !isChanging }

    var statusMessage: String {
        switch status {
        case .notRegistered:
            L10n.tr("꺼짐 · 로그인 후 Cellar를 직접 실행합니다.", "Off · Open Cellar manually after signing in.")
        case .enabled:
            L10n.tr("켜짐 · 다음 로그인부터 Cellar가 자동으로 실행됩니다.", "On · Cellar will open automatically when you next sign in.")
        case .requiresApproval:
            L10n.tr("macOS의 승인이 필요합니다. 시스템 설정에서 Cellar를 허용해야 자동 실행됩니다.", "macOS approval is required. Allow Cellar in System Settings before it can open at login.")
        case .notFound:
            L10n.tr("등록된 로그인 항목을 찾지 못했습니다. 자동 실행을 켜서 Cellar를 다시 등록할 수 있습니다.", "A registered login item could not be found. Turn on launch at login to register Cellar again.")
        case .unavailable:
            L10n.tr("설치된 Cellar 앱에서 사용할 수 있습니다. 데모 및 별도 테스트 빌드에서는 로그인 항목을 변경하지 않습니다.", "Available in the installed Cellar app. Demo and separate test builds do not change login items.")
        }
    }

    var failureMessage: String {
        L10n.tr("로그인 자동 실행 설정을 변경하지 못했습니다. 시스템 설정의 로그인 항목을 확인한 뒤 다시 시도하세요.", "Could not change the login setting. Check Login Items in System Settings and try again.")
    }

    func refresh() {
        let current = service.status
        if status != current && !isChanging { changeFailed = false }
        status = current
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        guard !isChanging else { return }
        refresh()
        guard canChange else { return }
        changeFailed = false
        guard enabled != status.isRegistered else { return }
        isChanging = true
        defer {
            refresh()
            isChanging = false
        }
        do {
            if enabled {
                try service.register()
            } else {
                try await service.unregister()
            }
        } catch {
            // The current OS state remains authoritative, even after a failed call.
            // Do not expose raw system error details in the interface.
        }
        let current = service.status
        changeFailed = enabled ? !current.isRegistered : current.isRegistered
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
