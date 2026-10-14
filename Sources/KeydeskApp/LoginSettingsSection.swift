import AppKit
import SwiftUI
import KeydeskCore

/// Login settings remain accessible while the vault is locked.
struct LoginSettingsSection: View {
    @State private var model: LoginItemModel
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue

    init(model: LoginItemModel = LoginItemModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        let _ = interfaceLanguage
        @Bindable var model = model
        GroupBox(L10n.tr("로그인 시 자동 실행", "Launch at login")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.tr("로그인 시 Cellar 자동 실행", "Open Cellar at login"), isOn: $model.launchAtLogin)
                    .disabled(!model.canChange)
                    .accessibilityIdentifier("launch-at-login")
                HStack(spacing: 10) {
                    if model.isChanging {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel(L10n.tr("로그인 설정 변경 중", "Changing login setting"))
                    }
                    Text(model.statusMessage)
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("launch-at-login-status")
                }
                if model.changeFailed {
                    Label(model.failureMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if model.status == .requiresApproval || model.changeFailed || model.status == .notFound {
                    Button(L10n.tr("로그인 항목 설정 열기", "Open Login Items Settings"), systemImage: "gear") {
                        model.openSystemSettings()
                    }
                    .accessibilityIdentifier("open-login-items-settings")
                }
                Text(L10n.tr("Mac에 로그인할 때 앱을 실행합니다. 금고는 자동으로 잠금 해제하지 않습니다.", "Opens the app when you sign in to your Mac. The vault is not unlocked automatically."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}
