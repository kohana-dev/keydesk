import SwiftUI
import KeydeskCore

struct BackupSettingsSection: View {
    @Bindable var model: VaultModel

    private var destinationName: String {
        switch model.backupDestination {
        case .iCloud: "iCloud Drive"
        case .googleDrive: "Google Drive"
        case .folder: L10n.tr("다른 폴더 / 외장 디스크", "Other folder / external disk")
        case nil: L10n.tr("설정되지 않음", "Not configured")
        }
    }

    var body: some View {
        GroupBox(L10n.tr("자동 암호화 백업", "Automatic encrypted backup")) {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent(L10n.tr("백업 위치", "Backup location"), value: destinationName)
                Text(model.backupDirectory?.path ?? L10n.tr("설정되지 않음 · Mac을 잃으면 복구할 수 없습니다", "Not configured · Recovery is unavailable if you lose this Mac"))
                    .font(.caption).textSelection(.enabled)
                Text(L10n.tr("변경할 때마다 몇 초 안에, 그리고 잠그거나 종료할 때 암호화 백업을 저장합니다. 최근 서로 다른 7개 날짜와 4개 주차의 최신 백업을 보존합니다.", "Encrypted backups are saved within a few seconds of each change, and when you lock or quit. The newest backups for the latest seven distinct dates and four distinct weeks are kept."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.backupDestination == .googleDrive {
                    Text(L10n.tr("데스크톱용 Google Drive가 동기화하는 폴더에 저장합니다. Cellar는 Google 계정에 로그인하지 않습니다. 실제 업로드 완료 여부는 Google Drive의 동기화 상태에서 확인하세요.", "Files are saved in a folder synced by Google Drive for desktop. Cellar does not sign in to your Google account. Check Google Drive’s sync status to confirm the upload has completed."))
                        .font(.caption).foregroundStyle(.secondary)
                    Link(L10n.tr("Google Drive 설치와 동기화 안내", "Google Drive setup and sync help"), destination: URL(string: "https://support.google.com/drive/answer/10838124")!)
                        .font(.caption)
                } else if let directory = model.backupDirectory, BackupLocation.isOnlyOnThisMac(directory) {
                    Label(L10n.tr("이 폴더는 이 Mac 안에만 있습니다. iCloud Drive, Google Drive 동기화 폴더 또는 외장 디스크를 선택하세요.", "This folder is only on this Mac. Choose iCloud Drive, a Google Drive sync folder, or an external disk."), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let date = model.lastBackupAt {
                    Text(L10n.tr("마지막 파일 저장·검증: \(date.formatted(Date.FormatStyle().locale(L10n.locale)))", "Last file save and verification: \(date.formatted(Date.FormatStyle().locale(L10n.locale)))"))
                        .font(.caption)
                }
                if model.backupDestination == .googleDrive, model.lastBackupAt != nil, model.backupFailure == nil {
                    Label(L10n.tr("Google Drive 폴더에 저장됨 · 클라우드 동기화는 Drive에서 확인", "Saved in Google Drive folder · Check cloud sync in Drive"), systemImage: "folder.badge.checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                cloudStatus
                if let error = model.backupFailure { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Menu(L10n.tr("백업 위치 선택", "Choose backup location")) {
                        Button("iCloud Drive") { chooseICloud() }
                            .disabled(model.availableICloudBackupDirectory == nil)
                        Button("Google Drive…") { chooseFolder(destination: .googleDrive) }
                        Button(L10n.tr("다른 폴더 / 외장 디스크…", "Other folder / external disk…")) { chooseFolder(destination: .folder) }
                    }
                    Button(L10n.tr("지금 백업", "Back up now")) { model.flushBackup(force: true) }
                        .disabled(model.backupDirectory == nil)
                    Button(L10n.tr("자동 백업 해제", "Turn off automatic backup")) {
                        do { try model.configureBackup(directory: nil) } catch { model.error = error.localizedDescription }
                    }.disabled(model.snapshot?.backup == nil)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
    }

    @ViewBuilder private var cloudStatus: some View {
        switch model.cloudUpload {
        case .failed:
            Label(L10n.tr("백업 파일이 iCloud에 올라가지 않았습니다. 시스템 설정의 Apple 계정에서 동의가 필요한 약관이나 iCloud 상태를 확인하세요. 해결 전에는 Mac을 잃으면 복구할 수 없습니다.", "The backup file has not uploaded to iCloud. Check your Apple Account in System Settings for terms that need acceptance or iCloud issues. Until this is resolved, recovery is unavailable if you lose this Mac."), systemImage: "exclamationmark.icloud")
                .font(.caption).foregroundStyle(.red)
        case .pending:
            Label(L10n.tr("iCloud 업로드를 기다리는 중입니다.", "Waiting for the iCloud upload."), systemImage: "icloud.and.arrow.up")
                .font(.caption).foregroundStyle(.orange)
        case .uploaded:
            Label(L10n.tr("최근 백업이 iCloud에 업로드됐습니다.", "The latest backup has uploaded to iCloud."), systemImage: "checkmark.icloud")
                .font(.caption).foregroundStyle(.green)
        case .notCloud: EmptyView()
        }
    }

    private func chooseICloud() {
        do { try model.configureICloudBackup() } catch { model.error = error.localizedDescription }
    }

    private func chooseFolder(destination: BackupDestination) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.tr("선택", "Choose")
        if destination == .googleDrive {
            panel.title = L10n.tr("Google Drive 백업 폴더 선택", "Choose Google Drive backup folder")
            panel.message = L10n.tr("먼저 데스크톱용 Google Drive에 로그인한 뒤 실제 동기화되는 전용 폴더를 선택하세요. 개인 My Drive 폴더를 권장합니다. 일반 로컬 폴더는 Google에 업로드되지 않습니다.", "Sign in to Google Drive for desktop first, then choose a dedicated folder that actually syncs. A private My Drive folder is recommended. An ordinary local folder will not upload to Google.")
            let cloudStorage = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage", isDirectory: true)
            if FileManager.default.fileExists(atPath: cloudStorage.path) { panel.directoryURL = cloudStorage }
        } else {
            panel.title = L10n.tr("백업 폴더 선택", "Choose backup folder")
        }
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            // A mirrored Google Drive folder can live anywhere; the user's explicit selection is
            // authoritative. Known cloud paths are still recognized for the general folder option.
            let detected = BackupLocation.destination(of: directory)
            try model.configureBackup(directory: directory, destination: destination == .googleDrive ? .googleDrive : detected)
        } catch { model.error = error.localizedDescription }
    }
}
