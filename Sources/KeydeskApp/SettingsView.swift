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
            SupportSettingsSection()
            Divider()
            Text(L10n.tr("백업과 개발 도구 설정", "Backup and developer settings")).font(.title2.bold())
            GroupBox(L10n.tr("자동 암호화 백업", "Automatic encrypted backup")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.backupDirectory?.path ?? L10n.tr("설정되지 않음 · Mac을 잃으면 복구할 수 없습니다", "Not configured · Recovery is unavailable if you lose this Mac")).font(.caption).textSelection(.enabled)
                    Text(L10n.tr("변경할 때마다 몇 초 안에, 그리고 잠그거나 종료할 때 백업합니다. 최근 7일의 일별 및 최근 4주의 주별 마지막 백업을 보존합니다.", "Backups run within a few seconds of each change, and when you lock the vault or quit. The last daily backup for the past 7 days and the last weekly backup for the past 4 weeks are kept.")).font(.caption).foregroundStyle(.secondary)
                    if let directory = model.backupDirectory, BackupLocation.isOnlyOnThisMac(directory) {
                        Label(L10n.tr("이 폴더는 이 Mac 안에만 있습니다. iCloud Drive나 외장 디스크를 권장합니다.", "This folder is only on this Mac. iCloud Drive or an external disk is recommended."), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                    if let date = model.lastBackupAt { Text(L10n.tr("마지막 성공: \(date.formatted(Date.FormatStyle().locale(L10n.locale)))", "Last successful backup: \(date.formatted(Date.FormatStyle().locale(L10n.locale)))")).font(.caption) }
                    switch model.cloudUpload {
                    case .failed: Label(L10n.tr("백업 파일이 iCloud에 올라가지 않았습니다. 시스템 설정의 Apple 계정에서 동의가 필요한 약관이나 iCloud 상태를 확인하세요. 해결 전에는 Mac을 잃으면 복구할 수 없습니다.", "The backup file has not uploaded to iCloud. Check your Apple Account in System Settings for terms that need acceptance or iCloud issues. Until this is resolved, recovery is unavailable if you lose this Mac."), systemImage: "exclamationmark.icloud").font(.caption).foregroundStyle(.red)
                    case .pending: Label(L10n.tr("iCloud 업로드를 기다리는 중입니다.", "Waiting for the iCloud upload."), systemImage: "icloud.and.arrow.up").font(.caption).foregroundStyle(.orange)
                    case .uploaded: Label(L10n.tr("최근 백업이 iCloud에 업로드됐습니다.", "The latest backup has uploaded to iCloud."), systemImage: "checkmark.icloud").font(.caption).foregroundStyle(.green)
                    case .notCloud: EmptyView()
                    }
                    if let error = model.backupFailure { Text(error).font(.caption).foregroundStyle(.red) }
                    HStack {
                        Button(L10n.tr("백업 폴더 선택", "Choose backup folder")) {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let url = panel.url { do { try model.configureBackup(directory: url) } catch { model.error = error.localizedDescription } }
                        }
                        Button(L10n.tr("지금 백업", "Back up now")) { model.flushBackup() }.disabled(model.backupDirectory == nil || !model.hasUnbackedChanges)
                        Button(L10n.tr("자동 백업 해제", "Turn off automatic backup")) { do { try model.configureBackup(directory: nil) } catch { model.error = error.localizedDescription } }.disabled(model.snapshot?.backup == nil)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            GroupBox(L10n.tr("복구 키", "Recovery key")) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.recoveryKeySaved {
                        Label(L10n.tr("iCloud 키체인에 저장됨", "Saved in iCloud Keychain"), systemImage: "checkmark.icloud").foregroundStyle(.green).font(.callout)
                    } else {
                        Label(L10n.tr("iCloud 키체인에 저장하지 못했습니다. 복구 키를 직접 보관하세요.", "Could not save to iCloud Keychain. Keep your own copy of the recovery key."), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                    }
                    Text(L10n.tr("같은 Apple 계정으로 로그인한 다른 Mac에서 Cellar를 열면 iCloud Drive 백업과 이 키로 자동 복원합니다.", "When you open Cellar on another Mac signed in to the same Apple Account, it automatically restores using the iCloud Drive backup and this key.")).font(.caption).foregroundStyle(.secondary)
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
