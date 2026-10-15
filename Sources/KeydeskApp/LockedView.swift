import SwiftUI
import KeydeskCore

struct LockedView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = AppLanguage.system.rawValue
    @Bindable var model: VaultModel
    @State private var recovering = false
    @State private var depositing = false
    @State private var recoveryURL: URL?
    var body: some View {
        let _ = interfaceLanguage
        VStack(spacing: 22) {
            CellarMark(size: 116)
            Text("Cellar").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
            if model.exists || model.isDemo { lockedContent } else { firstRunContent }
            if model.busy { ProgressView().controlSize(.small) }
            Text(L10n.tr("로컬 보관 · iCloud / Google Drive 암호화 백업 · CLI 연결", "Local storage · Encrypted iCloud / Google Drive backup · CLI access")).font(.caption).foregroundStyle(.secondary).padding(.top, 20)
        }
        .frame(maxWidth: 560).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas)
        .task(id: model.exists) { if !model.exists { await model.prepareFirstRun() } }
        .sheet(isPresented: $depositing) { DepositView(model: model) }
        .sheet(isPresented: $recovering) { RecoveryView(model: model, initialURL: recoveryURL) }
    }
    @ViewBuilder private var lockedContent: some View {
        Text(L10n.tr("금고가 잠겨 있습니다", "Your vault is locked")).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.ink)
        Text(L10n.tr("인증 후 프로젝트와 키를 확인할 수 있습니다.", "Authenticate to view your projects and keys.")).foregroundStyle(.secondary)
        VStack(spacing: 8) {
            Button(L10n.tr("금고 열기", "Unlock vault"), systemImage: "touchid") { Task { await model.unlock() } }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
            CapsLockIndicator()
        }
        Button(L10n.tr("새 키 맡기기", "Deposit a new key"), systemImage: "tray.and.arrow.down") { depositing = true }
        Button(L10n.tr("백업 복구 검증", "Verify backup recovery"), systemImage: "arrow.counterclockwise") { recoveryURL = nil; recovering = true }
    }
    @ViewBuilder private var firstRunContent: some View {
        switch model.firstRun {
        case .backupFound:
            message(L10n.tr("iCloud 백업을 찾았습니다", "iCloud backup found"), L10n.tr("이 백업을 복원하거나 Google Drive 등에서 내려받은 다른 백업 파일을 선택하세요. 다른 위치에 더 최근 백업이 있는지 먼저 확인하세요.", "Restore this backup, or choose another backup file downloaded from Google Drive or another location. Check whether you have a newer backup elsewhere first."))
            retryButtons(primary: L10n.tr("이 iCloud 백업 복원", "Restore this iCloud backup"), restoreExisting: true)
        case .readyToCreate:
            message(L10n.tr("Cellar 시작하기", "Get started with Cellar"), L10n.tr("새 금고를 만들거나 Google Drive 등에서 내려받은 암호화 백업을 복원하세요. 복원에는 .keydesk 파일과 복구 키가 필요합니다.", "Create a new vault, or restore an encrypted backup downloaded from Google Drive or another location. You’ll need the .keydesk file and its recovery key."))
            Button(L10n.tr("새 금고로 시작", "Start a new vault")) { Task { await model.prepareFirstRun(startNew: true) } }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
            restoreFileButton
        case .waitingForBackup:
            message(L10n.tr("이전 금고의 백업을 기다리는 중", "Waiting for your previous vault backup"), L10n.tr("iCloud 키체인에 이전 금고의 복구 키가 있습니다. iCloud Drive의 Keydesk 폴더가 내려온 뒤 복원을 선택할 수 있습니다. Google Drive나 다른 위치의 백업은 파일을 선택해 복원하세요.", "iCloud Keychain contains the recovery key for your previous vault. You can choose to restore after the Keydesk folder downloads from iCloud Drive. To restore a Google Drive or other backup, choose the file below."))
            retryButtons(primary: L10n.tr("다시 확인", "Check again"))
        case .needsRecoveryCode(let url):
            message(L10n.tr("iCloud 백업을 찾았습니다", "iCloud backup found"), L10n.tr("이 백업의 복구 키가 아직 이 Mac의 iCloud 키체인에 없습니다. 잠시 후 다시 확인하거나, 따로 보관한 복구 키를 입력하세요.", "The recovery key for this backup is not yet in iCloud Keychain on this Mac. Check again shortly, or enter the recovery key you kept separately."))
            retryButtons(primary: L10n.tr("다시 확인", "Check again"), manual: url)
        case .restoreStopped(let url, let reason):
            message(L10n.tr("복원을 마치지 못했습니다", "Restore could not be completed"), reason)
            retryButtons(primary: L10n.tr("다시 복원", "Retry restore"), manual: url, restoreExisting: true)
        case .failed(let reason):
            message(L10n.tr("금고를 준비하지 못했습니다", "Could not prepare the vault"), reason)
            Button(L10n.tr("다시 시도", "Try again")) { Task { await model.prepareFirstRun() } }.buttonStyle(.borderedProminent).controlSize(.large)
            restoreFileButton
        case .checking, nil:
            message(L10n.tr("금고를 준비하는 중", "Preparing your vault"), L10n.tr("iCloud Drive에서 기존 백업을 확인합니다.", "Checking iCloud Drive for an existing backup."))
        }
    }
    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 28, weight: .semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
    private func retryButtons(primary: String, manual: URL? = nil, restoreExisting: Bool = false) -> some View {
        VStack(spacing: 12) {
            Button(primary) { Task { await model.prepareFirstRun(restoreExisting: restoreExisting) } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
            HStack(spacing: 16) {
                if let manual { Button(L10n.tr("복구 키 직접 입력", "Enter recovery key")) { recoveryURL = manual; recovering = true } }
                Button(L10n.tr("새 금고로 시작", "Start a new vault")) { Task { await model.prepareFirstRun(startNew: true) } }.disabled(model.busy)
            }
            restoreFileButton
        }
    }
    private var restoreFileButton: some View {
        Button(L10n.tr("암호화 백업 파일 복원", "Restore encrypted backup file"), systemImage: "doc.badge.arrow.up") {
            recoveryURL = nil; recovering = true
        }.disabled(model.busy)
    }
}
