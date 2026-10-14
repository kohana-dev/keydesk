import SwiftUI
import KeydeskCore

struct SettingsView: View {
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var rotating = false
    @State private var showingRecovery = false
    @AppStorage("Cellar.interfaceLanguage") private var interfaceLanguage = "system"
    var body: some View {
        let _ = interfaceLanguage
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Picker(L10n.tr("언어", "Language"), selection: $interfaceLanguage) {
                Text(L10n.tr("시스템", "System")).tag("system")
                Text("한국어").tag("ko")
                Text("English").tag("en")
            }
            Text(L10n.tr("언어 변경은 즉시 적용됩니다.", "Language changes apply immediately.")).font(.caption).foregroundStyle(.secondary)
            Divider()
            LoginSettingsSection()
            Divider()
            SupportSettingsSection()
            Divider()
            Text(L10n.tr("백업과 개발 도구 설정", "Backup and developer settings")).font(.title2.bold())
            BackupSettingsSection(model: model)
            GroupBox(L10n.tr("복구 키", "Recovery key")) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.recoveryKeySaved {
                        Label(L10n.tr("iCloud 키체인에 저장됨", "Saved in iCloud Keychain"), systemImage: "checkmark.icloud").foregroundStyle(.green).font(.callout)
                    } else {
                        Label(L10n.tr("iCloud 키체인에 저장하지 못했습니다. 복구 키를 직접 보관하세요.", "Could not save to iCloud Keychain. Keep your own copy of the recovery key."), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                    }
                    Text(model.backupDestination == .iCloud
                        ? L10n.tr("같은 Apple 계정으로 로그인한 다른 Mac에서 iCloud Drive 백업이 내려오면 복원을 선택할 수 있습니다. 다른 위치에 더 최근 백업이 있는지도 확인하세요.", "On another Mac signed in to the same Apple Account, you can choose to restore after the iCloud Drive backup downloads. Check whether you have a newer backup elsewhere, too.")
                        : L10n.tr("백업을 복원할 때는 내려받은 .keydesk 파일과 복구 키가 필요합니다. 복구 키는 백업 폴더에 함께 올리지 않고 직접 안전하게 보관하세요. Google Drive 백업 복원 후 이 Mac의 백업 폴더를 다시 선택합니다.", "To restore a backup, use the downloaded .keydesk file and your recovery key. Keep the recovery key safely and separately from the backup folder. Select this Mac’s backup folder again after restoring a Google Drive backup.")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.tr("복구 키 보기", "Show recovery key"), systemImage: "key") { showingRecovery = true }
                        Button(L10n.tr("복구 키 / 데이터 키 교체", "Rotate recovery / data keys"), systemImage: "arrow.triangle.2.circlepath") { rotating = true }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            Picker(L10n.tr("자동 잠금", "Auto-lock"), selection: $model.autoLockMinutes) {
                Text(L10n.tr("5분", "5 minutes")).tag(5); Text(L10n.tr("15분", "15 minutes")).tag(15); Text(L10n.tr("30분", "30 minutes")).tag(30); Text(L10n.tr("60분", "60 minutes")).tag(60); Text(L10n.tr("화면 잠금 시", "When the screen locks")).tag(0)
            }
            Text(L10n.tr("Mac 화면 잠금·잠자기에는 항상 금고가 잠깁니다.", "The vault always locks when the Mac screen locks or the Mac sleeps.")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.tr("기억한 명령 승인 해제", "Clear remembered command approvals")) { model.clearDevelopmentApprovals(); model.notify(L10n.tr("기억한 명령 승인을 해제했습니다.", "Remembered command approvals have been cleared.")) }
            Divider()
            Text(L10n.tr("개발 CLI", "Developer CLI")).font(.headline)
            Text(L10n.tr("CLI를 ~/.local/bin에 연결합니다. 셸 설정과 다른 프로그램은 덮어쓰지 않습니다.", "Link the CLI in ~/.local/bin. Shell settings and other programs are not overwritten.")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.tr("CLI 설치 / 연결", "Install / link CLI"), systemImage: "terminal") {
                do { let target = try CLIInstaller.install(executable: model.cliURL); model.notify(L10n.tr("CLI 설치: \(target.path). PATH에 ~/.local/bin을 추가하세요.", "CLI installed: \(target.path). Add ~/.local/bin to your PATH.")) }
                catch { model.error = error.localizedDescription }
            }
            Button(L10n.tr("승인된 실행 모두 종료", "Stop all approved runs"), systemImage: "stop.circle") { model.stopRunning(); model.notify(L10n.tr("실행 중인 개발 프로세스에 종료를 요청했습니다.", "Requested termination of the running developer processes.")) }
            HStack { Spacer(); Button(L10n.tr("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction) }
          }.padding(28)
        }.frame(width: 650).frame(maxHeight: 720)
        .sheet(isPresented: $rotating) { VaultKeyRotationView(model: model) }
        .sheet(isPresented: $showingRecovery) { RecoveryKeyView(model: model) }
    }
}
