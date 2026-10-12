import SwiftUI
import KeydeskCore

struct SettingsView: View {
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var rotating = false
    @State private var showingRecovery = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("백업과 개발 도구 설정").font(.title2.bold())
            GroupBox("자동 암호화 백업") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.backupDirectory?.path ?? "설정되지 않음 · Mac을 잃으면 복구할 수 없습니다").font(.caption).textSelection(.enabled)
                    Text("변경할 때마다 몇 초 안에, 그리고 잠그거나 종료할 때 백업합니다. 최근 7일의 일별 및 최근 4주의 주별 마지막 백업을 보존합니다.").font(.caption).foregroundStyle(.secondary)
                    if let directory = model.backupDirectory, BackupLocation.isOnlyOnThisMac(directory) {
                        Label("이 폴더는 이 Mac 안에만 있습니다. iCloud Drive나 외장 디스크를 권장합니다.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                    if let date = model.lastBackupAt { Text("마지막 성공: \(date.formatted())").font(.caption) }
                    switch model.cloudUpload {
                    case .failed: Label("백업 파일이 iCloud에 올라가지 않았습니다. 시스템 설정의 Apple 계정에서 동의가 필요한 약관이나 iCloud 상태를 확인하세요. 해결 전에는 Mac을 잃으면 복구할 수 없습니다.", systemImage: "exclamationmark.icloud").font(.caption).foregroundStyle(.red)
                    case .pending: Label("iCloud 업로드를 기다리는 중입니다.", systemImage: "icloud.and.arrow.up").font(.caption).foregroundStyle(.orange)
                    case .uploaded: Label("최근 백업이 iCloud에 업로드됐습니다.", systemImage: "checkmark.icloud").font(.caption).foregroundStyle(.green)
                    case .notCloud: EmptyView()
                    }
                    if let error = model.backupFailure { Text(error).font(.caption).foregroundStyle(.red) }
                    HStack {
                        Button("백업 폴더 선택") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let url = panel.url { do { try model.configureBackup(directory: url) } catch { model.error = error.localizedDescription } }
                        }
                        Button("지금 백업") { model.flushBackup() }.disabled(model.backupDirectory == nil || !model.hasUnbackedChanges)
                        Button("자동 백업 해제") { do { try model.configureBackup(directory: nil) } catch { model.error = error.localizedDescription } }.disabled(model.snapshot?.backup == nil)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            GroupBox("복구 키") {
                VStack(alignment: .leading, spacing: 10) {
                    if model.recoveryKeySaved {
                        Label("iCloud 키체인에 저장됨", systemImage: "checkmark.icloud").foregroundStyle(.green).font(.callout)
                    } else {
                        Label("iCloud 키체인에 저장하지 못했습니다. 복구 키를 직접 보관하세요.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                    }
                    Text("같은 Apple 계정으로 로그인한 다른 Mac에서 Cellar를 열면 iCloud Drive 백업과 이 키로 자동 복원합니다.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("복구 키 보기", systemImage: "key") { showingRecovery = true }
                        Button("복구 키 / 데이터 키 교체", systemImage: "arrow.triangle.2.circlepath") { rotating = true }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            Picker("자동 잠금", selection: $model.autoLockMinutes) {
                Text("5분").tag(5); Text("15분").tag(15); Text("30분").tag(30); Text("60분").tag(60); Text("화면 잠금 시").tag(0)
            }
            Text("Mac 화면 잠금·잠자기에는 항상 금고가 잠깁니다.").font(.caption).foregroundStyle(.secondary)
            Button("기억한 명령 승인 해제") { model.clearDevelopmentApprovals(); model.notify("기억한 명령 승인을 해제했습니다.") }
            Divider()
            Text("개발 CLI").font(.headline)
            Text("CLI를 ~/.local/bin에 연결합니다. 셸 설정과 다른 프로그램은 덮어쓰지 않습니다.").font(.caption).foregroundStyle(.secondary)
            Button("CLI 설치 / 연결", systemImage: "terminal") {
                do { let target = try CLIInstaller.install(executable: model.cliURL); model.notify("CLI 설치: \(target.path). PATH에 ~/.local/bin을 추가하세요.") }
                catch { model.error = error.localizedDescription }
            }
            Button("승인된 실행 모두 종료", systemImage: "stop.circle") { model.stopRunning(); model.notify("실행 중인 개발 프로세스에 종료를 요청했습니다.") }
            HStack { Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 650)
        .sheet(isPresented: $rotating) { VaultKeyRotationView(model: model) }
        .sheet(isPresented: $showingRecovery) { RecoveryKeyView(model: model) }
    }
}
