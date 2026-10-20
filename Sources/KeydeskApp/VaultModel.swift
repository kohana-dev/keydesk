import Foundation
import Observation
import AppKit
import CryptoKit
import KeydeskCore

/// What the app shows before a vault exists on this Mac.
enum FirstRunState: Equatable {
    case checking
    /// An empty iCloud folder does not rule out a Google Drive or manually kept backup.
    case readyToCreate
    /// An iCloud copy may predate a switch to Google Drive, so restore needs a choice.
    case backupFound(URL)
    /// iCloud Keychain knows an earlier vault but its backup has not reached iCloud Drive here yet.
    case waitingForBackup
    /// A backup exists but its recovery key has not synced to this Mac.
    case needsRecoveryCode(URL)
    /// Automatic restore stopped, usually because OS authentication was cancelled.
    case restoreStopped(URL, String)
    case failed(String)
}

@MainActor @Observable
final class VaultModel {
    private(set) var snapshot: VaultSnapshot?
    private(set) var exists = false
    private(set) var busy = false
    private(set) var isDemo: Bool
    var selectedProject: UUID?
    var environment = EnvironmentName.development
    var selectedCredential: UUID?
    var search = ""
    var favoritesOnly = false
    var showQuickAdd = false
    var notice: String?
    var error: String?
    var approval: CLIApproval? { didSet { onApprovalChange?() } }
    var autoLockMinutes = 30 {
        didSet {
            if !isDemo { UserDefaults.standard.set(autoLockMinutes, forKey: "autoLockMinutes") }
            activity()
        }
    }
    var apiApproval: APIApproval? { didSet { onApprovalChange?() } }
    var apiApprovals = APIApprovalCache()
    var apiTasks: [UUID: Task<Void, Never>] = [:]
    var apiRunning: [UUID: APIRequest] = [:]
    let apiTransport: any APITransport
    private var developmentApprovals = DevelopmentApprovalCache()
    @ObservationIgnored private(set) var reusingDevelopmentApproval = false
    var cliAvailable = false
    /// Called when a CLI or AI approval request appears or ends.
    @ObservationIgnored var onApprovalChange: (() -> Void)?
    @ObservationIgnored private var approvalPresenter: ApprovalPanelController?
    var brokerApproval: BrokerApproval? { didSet { onApprovalChange?() } }
    var grants: [String: AccessGrant] = [:]
    private(set) var timedApprovalExpiresAt: Date?
    private(set) var timedApprovalStarting = false
    private var timedApprovalSession: TimedApprovalSession?
    @ObservationIgnored private var timedApprovalExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var timedApprovalAttemptID = UUID()
    var backupFailure: String?
    private(set) var backedUpRevision: UInt64?
    private(set) var lastBackupAt: Date?
    private(set) var lastBackupFile: URL?
    private(set) var cloudUpload = BackupLocation.CloudUpload.notCloud
    private var backupTask: Task<Void, Never>?
    var revealID: UUID?
    var revealedValue: String?
    private(set) var firstRun: FirstRunState?
    /// False when the recovery key could not be written to iCloud Keychain; the user must keep it.
    private(set) var recoveryKeySaved = true
    let keys: any VaultKeyStore
    let defaultBackupDirectory: URL?
    private var key: SymmetricKey?
    private var envelope: VaultEnvelope?
    let store: VaultFileStore
    private let clipboard = ClipboardService()
    private let server: CLIServer
    private var revealTimer: Timer?
    private var idleTimer: Timer?
    private var lastActivity = Date()
    var generation = UUID()
    var runningInvocations: [UUID: CLIRequest] = [:]
    private var runningProcesses = [UUID: RunningCommand]()
    private var observers = [NSObjectProtocol]()

    /// iCloud Drive's `Keydesk` folder, when iCloud Drive is turned on for this macOS account.
    static var iCloudBackupDirectory: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: drive.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return drive.appendingPathComponent("Keydesk", isDirectory: true)
    }

    init(demo: Bool = false, demoSocket: String? = nil, directory: URL? = nil, defaultBackupDirectory: URL? = VaultModel.iCloudBackupDirectory,
         keys: (any VaultKeyStore)? = nil, apiTransport: any APITransport = CurlAPITransport(), serve: Bool = true, observeSystemEvents: Bool = true) {
        self.apiTransport = apiTransport
        isDemo = demo
        let storedMinutes = UserDefaults.standard.object(forKey: "autoLockMinutes") as? Int
        autoLockMinutes = !demo && [0, 5, 15, 30, 60].contains(storedMinutes ?? -1) ? storedMinutes! : 30
        self.keys = keys ?? (demo ? DemoKeyStore() : SystemKeyStore())
        self.defaultBackupDirectory = demo ? nil : defaultBackupDirectory
        server = CLIServer(path: demoSocket ?? SocketTransport.socketPath, trustedHelper: demo ? nil : Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/keydesk"))
        let directory = directory ?? (demo ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Keydesk-demo-\(UUID())") : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Keydesk"))
        store = VaultFileStore(directory: directory)
        exists = FileManager.default.fileExists(atPath: store.vaultURL.path)
        if demo { loadDemo(); try? prepareDeposits() }
        if serve && (!demo || demoSocket != nil) {
            do {
                try server.start(deliver: { [weak self] approval in
                    Task { @MainActor in self?.receive(approval) }
                }, broker: { [weak self] request, channel in
                    Task { @MainActor in self?.receiveBroker(request, channel: channel) }
                }, api: { [weak self] request, channel in
                    Task { @MainActor in self?.receiveAPI(request, channel: channel) }
                }, service: { [weak self] request, channel in
                    Task { @MainActor in await self?.receiveService(request, channel: channel) }
                })
                cliAvailable = true
                if !demo { TemporarySecretFiles.cleanupOrphans() }
            } catch { self.error = error.localizedDescription }
        }
        if serve {
            let presenter = ApprovalPanelController()
            approvalPresenter = presenter
            presenter.attach(self)
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.expireGrants()
                self?.expireTimedApproval()
                self?.lockIfIdle()
                self?.refreshCloudUpload()
            }
        }
        if observeSystemEvents {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
        }
    }

    var credentials: [Credential] {
        guard let snapshot else { return [] }
        let ids = selectedProject.map { project in Set(snapshot.bindings.filter { $0.projectID == project && $0.environment == environment }.map(\.credentialID)) }
        return snapshot.credentials.filter { credential in
            (ids == nil || ids!.contains(credential.id)) && (!favoritesOnly || credential.favorite)
            && (search.isEmpty || "\(credential.name) \(credential.provider) \(credential.account)".localizedCaseInsensitiveContains(search))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var hasPendingApproval: Bool { approval != nil || brokerApproval != nil || apiApproval != nil }
    var menuBarBackupStatus: String {
        guard snapshot != nil else { return L10n.tr("백업 상태는 금고를 연 뒤 확인합니다", "Open the vault to check backup status") }
        if isDemo { return L10n.tr("데모 · 가상 키만 사용", "Demo · Sample keys only") }
        if !recoveryKeySaved { return L10n.tr("복구 키 직접 보관 필요", "Keep a separate copy of your recovery key") }
        if backupFailure != nil { return L10n.tr("백업 실패", "Backup failed") }
        if backupDirectory == nil { return L10n.tr("백업 폴더 없음", "No backup folder") }
        if hasUnbackedChanges { return L10n.tr("백업 대기 중", "Backup pending") }
        if backupDestination == .googleDrive {
            return L10n.tr("Google Drive 폴더에 저장됨 · 동기화 확인 필요", "Saved in Google Drive folder · Check sync")
        }
        switch cloudUpload {
        case .uploaded: return L10n.tr("iCloud까지 백업됨", "Backed up to iCloud")
        case .pending: return L10n.tr("iCloud 업로드 대기 중", "iCloud upload pending")
        case .failed: return L10n.tr("iCloud 업로드 안 됨", "Not uploaded to iCloud")
        case .notCloud: return L10n.tr("모든 변경 백업됨", "All changes backed up")
        }
    }
    var detail: Credential? { snapshot?.credentials.first { $0.id == selectedCredential } }
    func languageDidChange() { approvalPresenter?.refreshLanguage() }
    var timedApprovalIsActive: Bool {
        // Read the observable date too, so status views update when consent changes.
        timedApprovalExpiresAt != nil && snapshot != nil && timedApprovalSession?.isActive() == true
    }
    func currentTimedApprovalID() -> UUID? {
        expireTimedApproval()
        guard snapshot != nil, let session = timedApprovalSession, session.isActive() else { return nil }
        return session.id
    }
    func timedApprovalAllows(_ id: UUID) -> Bool {
        currentTimedApprovalID() == id
    }
    func expireTimedApproval(now: Date = Date(), instant: ContinuousClock.Instant = ContinuousClock().now) {
        guard let session = timedApprovalSession, !session.isActive(now: now, instant: instant) else { return }
        stopTimedApproval()
    }
    func stopTimedApproval() {
        timedApprovalAttemptID = UUID()
        timedApprovalStarting = false
        timedApprovalExpiryTask?.cancel(); timedApprovalExpiryTask = nil
        timedApprovalSession = nil; timedApprovalExpiresAt = nil
        // Nothing approved under this window may become a longer-lived remembered grant.
        clearDevelopmentApprovals(); apiApprovals.clear(); revokeAllGrants()
    }
    func startTimedApproval(minutes: Int) async {
        guard (1...480).contains(minutes) else {
            error = L10n.tr("허용 시간은 1분부터 480분까지 설정할 수 있습니다.", "Choose an approval duration between 1 and 480 minutes.")
            return
        }
        guard snapshot != nil, !busy, !timedApprovalStarting else {
            error = L10n.tr("금고를 연 뒤 현재 작업이 끝나면 다시 시도해 주세요.", "Open the vault and wait for the current operation to finish, then try again.")
            return
        }
        let token = generation, attempt = UUID()
        timedApprovalAttemptID = attempt; timedApprovalStarting = true
        defer { if timedApprovalAttemptID == attempt { timedApprovalStarting = false } }
        do {
            if !isDemo {
                _ = try await keys.authenticate(reason: L10n.tr("\(minutes)분 동안 Production을 포함한 모든 CLI·API·MCP 요청을 자동 허용하기 위해 인증합니다.", "Authenticate to automatically allow all CLI, API, and MCP requests, including Production, for \(minutes) minutes."))
            }
            guard token == generation, snapshot != nil, !busy, timedApprovalAttemptID == attempt else { return }
            try mutate(invalidateGrants: false) { $0.record("모든 요청 자동 허용 시작 · \(minutes)분 · Production 포함") }
            clearDevelopmentApprovals(); apiApprovals.clear(); revokeAllGrants()
            timedApprovalExpiryTask?.cancel()
            let session = TimedApprovalSession(minutes: minutes)
            timedApprovalSession = session; timedApprovalExpiresAt = session.expiresAt
            timedApprovalExpiryTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(until: session.deadline, clock: .continuous) }
                catch { return }
                guard self?.timedApprovalSession?.id == session.id else { return }
                self?.stopTimedApproval()
            }
            notify(L10n.tr("\(minutes)분 동안 모든 요청을 자동 허용합니다. 금고를 잠그면 즉시 종료됩니다.", "All requests are automatically allowed for \(minutes) minutes. Locking the vault ends this immediately."))
            // Keep an already displayed request while clearing old grants, then fulfill it.
            if approval != nil { await acceptCLI(timedSessionID: session.id) }
            else if apiApproval != nil { await acceptAPI(remember: false, timedSessionID: session.id) }
            else if brokerApproval != nil { await acceptBroker(timedSessionID: session.id) }
        } catch {
            if token == generation, timedApprovalAttemptID == attempt { self.error = error.localizedDescription }
        }
    }
    func lockIfIdle(now: Date = Date()) {
        if autoLockMinutes > 0, snapshot != nil, now.timeIntervalSince(lastActivity) >= Double(autoLockMinutes * 60) { lock() }
    }
    func activity() { lastActivity = Date() }
    func hideValue() { revealTimer?.invalidate(); revealID = nil; revealedValue = nil }
    func notify(_ text: String) { notice = text; activity() }
    func lock() {
        // Never drop the key while changes exist only on this Mac.
        flushBackup()
        stopTimedApproval()
        generation = UUID(); revokeAllAPI(); developmentApprovals.clear(); hideValue(); clipboard.clearOwned()
        if let approval { approval.channel.send(CLIEvent(kind: "error", text: L10n.tr("금고가 잠겼습니다.", "The vault has been locked."))); approval.channel.finish() }
        approval = nil
        rejectBroker(); revokeAllGrants()
        for process in runningProcesses.values where process.isRunning && !process.keepRunning { process.terminate() }
        runningProcesses = runningProcesses.filter { $0.value.keepRunning && $0.value.isRunning }
        runningInvocations = runningInvocations.filter { runningProcesses[$0.key] != nil }
        showQuickAdd = false
        snapshot = nil; key = nil; envelope = nil; selectedCredential = nil; selectedProject = nil
        backedUpRevision = nil; lastBackupAt = nil; lastBackupFile = nil; cloudUpload = .notCloud
        search = ""; notice = nil; error = nil; busy = false
    }
    func stopRunning() { for process in runningProcesses.values { process.terminate() }; runningProcesses.removeAll(); runningInvocations.removeAll() }
    func shutdown() {
        idleTimer?.invalidate(); idleTimer = nil
        stopRunning(); lock(); server.stop()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        if isDemo { try? FileManager.default.removeItem(at: store.directory) }
    }
    func unlock() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let token = generation
        do {
            if isDemo { loadDemo(); try prepareDeposits(); return }
            let context = try await keys.authenticate(reason: L10n.tr("Cellar 금고를 열기 위해 인증합니다.", "Authenticate to unlock your Cellar vault."))
            guard token == generation else { return }
            let envelope = try store.read()
            let key = try keys.loadDeviceKey(envelope: envelope, context: context)
            let snapshot = try VaultCrypto.open(envelope, key: key)
            self.envelope = envelope; self.key = key; self.snapshot = snapshot; activity()
            loadBackupStatus()
            scheduleBackup()
            ensureRecoveryKeySaved()
            try prepareDeposits()
        } catch { self.error = error.localizedDescription }
    }
    /// Finds iCloud backups without replacing the choice to restore a newer Google Drive copy.
    /// Restore or creating a vault begins only after the user's choice.
    func prepareFirstRun(startNew: Bool = false, restoreExisting: Bool = false) async {
        guard !exists, !isDemo, !busy, snapshot == nil else { return }
        firstRun = .checking
        let directory = defaultBackupDirectory
        if !startNew, let directory, let latest = BackupManager.latestBackup(in: directory) {
            guard let recovery = keys.loadRecoveryKey(vaultID: latest.envelope.header.vaultID) else { firstRun = .needsRecoveryCode(latest.url); return }
            guard restoreExisting else { firstRun = .backupFound(latest.url); return }
            do { try await restore(at: latest.url, code: RecoveryCode.encode(recovery)); firstRun = nil }
            catch { firstRun = .restoreStopped(latest.url, error.localizedDescription) }
            return
        }
        if !startNew && !keys.knownRecoveryVaults().isEmpty { firstRun = .waitingForBackup; return }
        if !startNew { firstRun = .readyToCreate; return }
        do { try createAutomatically(backupDirectory: directory); firstRun = nil }
        catch { firstRun = .failed(error.localizedDescription) }
    }
    /// An empty vault needs no confirmation to create; OS authentication is required from the next unlock.
    private func createAutomatically(backupDirectory: URL?) throws {
        guard !exists, !busy else { throw VaultError.invalidData }
        let recovery = SymmetricKey(size: .bits256), key = SymmetricKey(size: .bits256), header = VaultHeader()
        var snapshot = VaultSnapshot()
        snapshot.depositPrivateKey = P256.KeyAgreement.PrivateKey().rawRepresentation
        snapshot.recoveryCode = RecoveryCode.encode(recovery)
        if let backupDirectory {
            try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            snapshot.backup = BackupSettings(directory: backupDirectory.path, bookmark: try? backupDirectory.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), destination: .iCloud)
        }
        snapshot.record("금고 생성")
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let envelope = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key)
        try keys.saveDeviceKey(key, id: header.vaultID, epoch: header.keyEpoch)
        do { try store.write(envelope, expectedRevision: nil) }
        catch { keys.removeDeviceKey(id: header.vaultID, epoch: header.keyEpoch); throw error }
        self.key = key; self.envelope = envelope; self.snapshot = snapshot; exists = true; activity()
        recoveryKeySaved = keys.saveRecoveryKey(recovery, vaultID: header.vaultID)
        try prepareDeposits()
        flushBackup()
        notify(backupDirectory == nil ? L10n.tr("금고를 만들었습니다. iCloud Drive가 꺼져 있어 백업 폴더를 직접 정해야 합니다.", "Your vault has been created. iCloud Drive is off, so choose a backup folder manually.") : L10n.tr("금고를 만들었습니다. 변경 내용은 iCloud Drive의 Keydesk 폴더에 자동으로 백업됩니다.", "Your vault has been created. Changes are backed up automatically to the Keydesk folder in iCloud Drive."))
    }
    /// Keeps iCloud Keychain's copy matching the vault, re-adding it if the item was removed.
    private func ensureRecoveryKeySaved() {
        guard !isDemo, let envelope, let code = snapshot?.recoveryCode, let recovery = try? RecoveryCode.decode(code) else { recoveryKeySaved = true; return }
        if keys.loadRecoveryKey(vaultID: envelope.header.vaultID)?.rawData == recovery.rawData { recoveryKeySaved = true; return }
        recoveryKeySaved = keys.saveRecoveryKey(recovery, vaultID: envelope.header.vaultID)
    }
    /// Shows the recovery key again after OS authentication.
    func authenticatedRecoveryCode() async throws -> String? {
        guard snapshot != nil else { throw VaultError.locked }
        let token = generation
        if !isDemo { _ = try await keys.authenticate(reason: L10n.tr("복구 키를 보기 위해 인증합니다.", "Authenticate to view your recovery key.")) }
        guard token == generation else { throw VaultError.locked }
        return snapshot?.recoveryCode
    }
    func mutate(invalidateGrants: Bool = true, _ body: (inout VaultSnapshot) throws -> Void) throws {
        guard var next = snapshot, let key, let envelope else { throw VaultError.locked }
        try body(&next); next.revision += 1
        var header = envelope.header; header.revision = next.revision
        let sealed = try VaultCrypto.seal(next, header: header, wrappedKey: envelope.recoveryWrappedKey, key: key)
        try store.write(sealed, expectedRevision: envelope.header.revision)
        self.snapshot = next; self.envelope = sealed; activity()
        if invalidateGrants { revokeAllAPI(); developmentApprovals.clear(); rejectBroker(); revokeAllGrants(); rejectCLI() }
        scheduleBackup()
    }
    func addProject(_ name: String, iconPNG: Data? = nil) throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 100 else { throw VaultError.invalidData }
        guard iconPNG.map(ProjectImage.valid) ?? true else { throw VaultError.invalidData }
        let project = Project(name: cleaned, colorIndex: snapshot?.projects.count ?? 0, iconPNG: iconPNG)
        try mutate { $0.projects.append(project); $0.record("프로젝트 추가") }
        selectedProject = project.id; selectedCredential = nil
    }
    func updateProject(_ id: UUID, name: String, iconPNG: Data?) throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 100, iconPNG.map(ProjectImage.valid) ?? true else { throw VaultError.invalidData }
        try mutate(invalidateGrants: snapshot?.projects.first(where: { $0.id == id })?.name != cleaned) { next in
            guard let index = next.projects.firstIndex(where: { $0.id == id }) else { throw VaultError.invalidData }
            next.projects[index].name = cleaned
            next.projects[index].iconPNG = iconPNG
            next.record("프로젝트 정보 수정")
        }
    }
    func addCredential(name: String, value: String, provider: String, account: String, note: String, variable: String, existingID: UUID? = nil, file: SecretFile? = nil, format: SecretFormat = .apiKey) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaultError.invalidData }
        if existingID == nil, file == nil {
            guard format != .apiKey || !value.isEmpty else { throw VaultError.invalidData }
            try SecretContent.validate(value, format: format)
        }
        let credential = try file.map { Credential(name: name, file: try $0.validated(), provider: provider, account: account, note: note) } ?? Credential(name: name, value: value, format: format, provider: provider, account: account, note: note)
        let id = existingID ?? credential.id
        try mutate { next in
            if existingID == nil { next.credentials.append(credential) }
            if let project = selectedProject {
                guard VaultSnapshot.validVariable(variable) else { throw VaultError.invalidData }
                next.bindings.append(BindingRecord(projectID: project, environment: environment, variable: variable, credentialID: id))
            } else if existingID != nil { throw VaultError.invalidData }
            next.record(existingID == nil ? "항목 등록" : "기존 항목 연결")
        }
        selectedCredential = id; notify(L10n.tr("저장했습니다.", "Saved."))
    }
    func toggleFavorite(_ id: UUID) {
        do { try mutate { next in if let i = next.credentials.firstIndex(where: { $0.id == id }) { next.credentials[i].favorite.toggle() } } }
        catch { self.error = error.localizedDescription }
    }
    func rotate(_ id: UUID, value: String, format: SecretFormat? = nil, expectedVersionID: UUID? = nil) throws {
        guard let credential = snapshot?.credentials.first(where: { $0.id == id }) else { throw VaultError.locked }
        let nextFormat = format ?? (credential.currentFormat == .file ? .apiKey : credential.currentFormat)
        guard nextFormat != .apiKey || !value.isEmpty else { throw VaultError.invalidData }
        try SecretContent.validate(value, format: nextFormat)
        try mutate { next in
            guard let i = next.credentials.firstIndex(where: { $0.id == id }) else { throw VaultError.invalidData }
            if let expectedVersionID, next.credentials[i].currentVersionID != expectedVersionID { throw VaultError.staleRevision }
            next.credentials[i].rotate(to: value, format: nextFormat); next.record("항목 새 버전 저장")
        }
        hideValue(); notify(L10n.tr("새 버전을 저장했습니다. 실행 중인 앱과 외부 배포 반영은 별도입니다.", "The new version has been saved. Updating running apps and external deployments is separate."))
    }
    func unlink(_ id: UUID) throws {
        guard let project = selectedProject else { throw VaultError.invalidData }
        try mutate { next in next.bindings.removeAll { $0.projectID == project && $0.environment == environment && $0.credentialID == id }; next.record("프로젝트 연결 해제") }
        selectedCredential = nil
    }
    func delete(_ id: UUID) throws {
        try mutate { next in next.bindings.removeAll { $0.credentialID == id }; next.credentials.removeAll { $0.id == id }; next.record("금고에서 키 삭제 · 과거 백업과 제공사 키는 별도") }
        hideValue(); selectedCredential = nil
    }
    private func sensitiveAccess(_ id: UUID) async throws {
        guard snapshot != nil else { throw VaultError.locked }
        let token = generation
        if !isDemo, snapshot?.bindings.contains(where: { $0.credentialID == id && $0.environment == .production }) == true {
            _ = try await keys.authenticate(reason: L10n.tr("Production에 연결된 키를 사용하기 위해 인증합니다.", "Authenticate to use a key connected to Production."))
        }
        guard token == generation, snapshot != nil else { throw VaultError.locked }
    }
    /// Loading stored content into an editor exposes it, so every real-vault edit starts with OS authentication.
    func authenticatedContentForEditing(_ id: UUID, versionID: UUID) async throws -> String {
        try Task.checkCancellation()
        guard let credential = snapshot?.credentials.first(where: { $0.id == id }), credential.currentVersionID == versionID,
              credential.currentFormat != .file else { throw VaultError.accessDenied }
        let token = generation
        if !isDemo { _ = try await keys.authenticate(reason: L10n.tr("저장된 내용을 편집하기 위해 인증합니다.", "Authenticate to edit stored content.")) }
        try Task.checkCancellation()
        guard token == generation, snapshot != nil else { throw VaultError.locked }
        guard let current = snapshot?.credentials.first(where: { $0.id == id }), current.currentVersionID == versionID,
              let value = current.currentText else { throw VaultError.staleRevision }
        activity()
        return value
    }
    func copyValue(_ id: UUID) async {
        do {
            try await sensitiveAccess(id)
            guard let value = snapshot?.credentials.first(where: { $0.id == id })?.currentText else { throw VaultError.invalidData }
            clipboard.copy(value, secret: true); notify(L10n.tr("내용을 복사했습니다. 30초 후 자동 삭제됩니다.", "The content has been copied. It will be cleared from the clipboard automatically after 30 seconds."))
        } catch { self.error = error.localizedDescription }
    }
    func reveal(_ id: UUID) async {
        do {
            try await sensitiveAccess(id)
            guard selectedCredential == id, let value = snapshot?.credentials.first(where: { $0.id == id })?.currentText else { return }
            hideValue(); revealID = id; revealedValue = value; activity()
            revealTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.hideValue() } }
        } catch { self.error = error.localizedDescription }
    }
    func copyText(_ text: String) { clipboard.copy(text, secret: false); notify(L10n.tr("복사했습니다.", "Copied.")) }
    func copyRecovery(_ text: String) { clipboard.copy(text, secret: true) }
    func backup(to url: URL) throws {
        guard let envelope, snapshot != nil else { throw VaultError.locked }
        guard url.standardizedFileURL != store.vaultURL.standardizedFileURL, url.standardizedFileURL != store.previousURL.standardizedFileURL else { throw VaultError.invalidData }
        try VaultFileStore.atomicWrite(JSONEncoder().encode(envelope), to: url)
        let check = try VaultFileStore.read(at: url)
        guard let key else { throw VaultError.locked }
        _ = try VaultCrypto.open(check, key: key)
        notify(L10n.tr("암호화 백업을 저장하고 검증했습니다.", "The encrypted backup has been saved and verified."))
    }
    func validateRecovery(at url: URL, code: String) throws -> Int {
        let envelope = try VaultFileStore.read(at: url)
        let key = try VaultCrypto.recover(envelope, code: code)
        return try VaultCrypto.open(envelope, key: key).credentials.count
    }
    func recoverDeviceAccess(at url: URL, code: String) async throws {
        guard exists, !busy else { throw VaultError.invalidData }
        busy = true; defer { busy = false }
        let token = generation
        let backup = try VaultFileStore.read(at: url), current = try store.read()
        guard backup.header.vaultID == current.header.vaultID, backup.header.keyEpoch == current.header.keyEpoch else { throw VaultError.invalidData }
        let recovered = try VaultCrypto.recover(backup, code: code)
        let snapshot = try VaultCrypto.open(current, key: recovered)
        let context = try await keys.authenticate(reason: L10n.tr("복구 키로 이 Mac의 금고 접근을 복구하기 위해 인증합니다.", "Authenticate to restore vault access on this Mac using your recovery key."))
        guard token == generation else { throw VaultError.locked }
        try keys.restoreDeviceKey(recovered, id: current.header.vaultID, epoch: current.header.keyEpoch, context: context)
        _ = try keys.loadDeviceKey(envelope: current, context: context)
        self.key = recovered; self.envelope = current; self.snapshot = snapshot; activity()
        loadBackupStatus(); scheduleBackup(); ensureRecoveryKeySaved()
        notify(L10n.tr("기기 접근을 복구했습니다. 현재 금고 파일은 덮어쓰지 않았습니다.", "Device access has been restored. The current vault file has not been overwritten."))
    }
    func restore(at url: URL, code: String) async throws {
        guard !exists, !busy else { throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("기존 금고를 덮어쓰지 않습니다. 별도 Mac 또는 사용자 계정에서 복원하세요. 현재 앱에서는 복구 검증을 사용할 수 있습니다.", "The existing vault will not be overwritten. Restore on a separate Mac or user account. You can verify recovery in the current app.") ]) }
        busy = true; defer { busy = false }
        let token = generation
        let imported = try VaultFileStore.read(at: url)
        let recovered = try VaultCrypto.recover(imported, code: code)
        var snapshot = try VaultCrypto.open(imported, key: recovered)
        _ = try await keys.authenticate(reason: L10n.tr("암호화 백업에서 Cellar 금고를 복원하기 위해 인증합니다.", "Authenticate to restore your Cellar vault from an encrypted backup."))
        guard token == generation, !exists else { throw VaultError.locked }
        // A fresh local vault identity avoids altering existing Keychain entries.
        var header = VaultHeader(); header.revision = snapshot.revision + 1
        snapshot.revision = header.revision; snapshot.record("백업 복원 · 제공사 유효성 재확인 필요")
        // A Google Drive path/bookmark belongs to the old Mac. Require a new selection rather than
        // silently switching the user's chosen provider to iCloud or writing to the old location.
        let wasGoogleDrive = snapshot.backup?.destination == .googleDrive
            || BackupLocation.destination(of: url.deletingLastPathComponent()) == .googleDrive
        snapshot.backup = nil
        if !wasGoogleDrive, let directory = defaultBackupDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            snapshot.backup = BackupSettings(directory: directory.path, bookmark: try? directory.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), destination: .iCloud)
        }
        let recovery = try RecoveryCode.decode(code)
        snapshot.recoveryCode = RecoveryCode.encode(recovery)
        let wrapped = try VaultCrypto.wrap(recovered, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let envelope = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: recovered)
        try keys.saveDeviceKey(recovered, id: header.vaultID, epoch: header.keyEpoch)
        do { try store.write(envelope, expectedRevision: nil) } catch { keys.removeDeviceKey(id: header.vaultID, epoch: header.keyEpoch); throw error }
        self.envelope = envelope; self.key = recovered; self.snapshot = snapshot; exists = true; activity()
        firstRun = nil
        recoveryKeySaved = keys.saveRecoveryKey(recovery, vaultID: header.vaultID)
        flushBackup()
        try prepareDeposits()
        notify(wasGoogleDrive
            ? L10n.tr("금고를 복원했습니다. 백업·CLI 설정에서 이 Mac의 Google Drive 백업 폴더를 다시 선택하세요.", "Your vault has been restored. Select this Mac’s Google Drive backup folder again in Backup & CLI settings.")
            : L10n.tr("암호화 백업에서 금고를 복원했습니다.", "The vault has been restored from an encrypted backup."))
    }
    func importRows(_ rows: [DotenvRow], replace: Bool) throws {
        guard let project = selectedProject else { throw VaultError.invalidData }
        try mutate { next in
            for row in rows where row.error == nil {
                if let i = next.bindings.firstIndex(where: { $0.projectID == project && $0.environment == environment && $0.variable == row.name }) {
                    if !replace { continue }
                    // Replace this binding with a new credential; never rotate a shared credential implicitly.
                    let credential = Credential(name: row.name, value: row.value, provider: ProviderCatalog.inferredProvider(for: row.name))
                    next.credentials.append(credential)
                    next.bindings[i] = BindingRecord(projectID: project, environment: environment, variable: row.name, credentialID: credential.id)
                } else {
                    let match = next.credentials.first(where: { $0.currentAPIKey == row.value && !row.value.isEmpty })
                    let credential = match ?? Credential(name: row.name, value: row.value, provider: ProviderCatalog.inferredProvider(for: row.name))
                    if match == nil { next.credentials.append(credential) }
                    next.bindings.append(BindingRecord(projectID: project, environment: environment, variable: row.name, credentialID: credential.id))
                }
            }
            next.record("dotenv 가져오기")
        }
        notify(L10n.tr("유효한 행을 가져왔습니다. 원본 파일은 변경하지 않았습니다.", "Valid rows have been imported. The original file has not been changed."))
    }
    func showPendingApproval() { approvalPresenter?.update() }

    func receive(_ request: CLIApproval) {
        let timedSessionID = currentTimedApprovalID()
        guard snapshot != nil, !busy, approval == nil, brokerApproval == nil, apiApproval == nil, runningProcesses.count < 4 else {
            request.channel.send(CLIEvent(kind: "error", text: L10n.tr("금고가 잠겨 있거나 다른 승인을 처리 중입니다.", "The vault is locked or another approval is being processed."))); request.channel.finish(); return
        }
        if let timedSessionID {
            request.channel.send(CLIEvent(kind: "status", text: L10n.tr("모든 요청 자동 허용 시간 안에 실행합니다.", "Running during the allow-all requests window.")))
            // Do not publish a pending approval: that would open and focus an approval panel.
            Task { @MainActor [weak self] in
                await self?.executeCLI(request, remember: false, timedSessionID: timedSessionID, requiresPending: false)
            }
            return
        }
        reusingDevelopmentApproval = developmentApprovals.allows(request.request, executable: request.executable)
        request.channel.send(CLIEvent(kind: "status", text: reusingDevelopmentApproval ? L10n.tr("기억한 명령 승인으로 실행합니다.", "Running with a remembered command approval.") : developmentApprovals.approvalReason(request.request, executable: request.executable) + L10n.tr(" Cellar에서 실행을 승인해 주세요.", " Approve the run in Cellar.")))
        approval = request
        if reusingDevelopmentApproval {
            Task { @MainActor [weak self] in await self?.acceptCLI() }
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            if self?.approval?.id == request.id {
                request.channel.send(CLIEvent(kind: "error", text: L10n.tr("승인 대기 60초가 지나 실행하지 않았습니다. 다시 요청해 주세요.", "The 60-second approval wait expired, so nothing was run. Send a new request.")))
                request.channel.finish(); self?.approval = nil
            }
        }
    }
    func rejectCLI() {
        approval?.channel.send(CLIEvent(kind: "error", text: L10n.tr("실행을 취소했습니다.", "The run has been cancelled."))); approval?.channel.finish(); approval = nil
    }
    var rememberedRuns: [DevelopmentApprovalCache.Entry] { developmentApprovals.active() }
    var runningCommands: [(UUID, RunningCommand)] { runningProcesses.map { ($0.key, $0.value) } }
    func revokeRun(_ id: UUID) { developmentApprovals.revoke(id) }
    func terminateRun(_ id: UUID) { runningProcesses[id]?.terminate() }
    func clearDevelopmentApprovals() { developmentApprovals.clear() }

    func acceptCLI(remember: Bool = false, timedSessionID: UUID? = nil) async {
        defer { reusingDevelopmentApproval = false }
        guard let approval else { return }
        await executeCLI(approval, remember: remember, timedSessionID: timedSessionID ?? currentTimedApprovalID(), requiresPending: true)
    }
    private func executeCLI(_ approval: CLIApproval, remember: Bool, timedSessionID: UUID?, requiresPending: Bool) async {
        let token = generation
        do {
            if let timedSessionID, !timedApprovalAllows(timedSessionID) { throw VaultError.accessDenied }
            let timed = timedSessionID != nil
            let reuse = !timed && reusingDevelopmentApproval && developmentApprovals.consume(approval.request, executable: approval.executable)
            if !timed && reusingDevelopmentApproval && !reuse { throw VaultError.accessDenied }
            if approval.request.environment == .production && !isDemo && !reuse && !timed {
                _ = try await keys.authenticate(reason: L10n.tr("Production 키를 CLI에 전달하기 위해 인증합니다.", "Authenticate to pass Production keys to the CLI."))
            }
            guard approval.channel.isConnected, token == generation, let snapshot, !busy,
                  runningProcesses.count < 4, !requiresPending || self.approval?.id == approval.id else { throw VaultError.locked }
            if let timedSessionID, !timedApprovalAllows(timedSessionID) { throw VaultError.accessDenied }
            let matches = snapshot.projects.filter { $0.name == approval.request.project || $0.id.uuidString.lowercased() == approval.request.project.lowercased() }
            guard matches.count == 1 else { throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("프로젝트가 없거나 이름이 중복됩니다. 프로젝트 UUID를 사용하세요.", "The project is missing or its name is duplicated. Use the project UUID.")]) }
            let files = try approval.request.selectedFiles(from: snapshot.files(projectID: matches[0].id, environment: approval.request.environment))
            let secrets = try approval.request.selectedSecrets(from: snapshot.environment(projectID: matches[0].id, environment: approval.request.environment, selections: approval.request.selections ?? []))
            try mutate(invalidateGrants: false) { $0.record("CLI 실행 승인 · \(approval.request.environment.title) · \(timed ? "시간 지정 자동 허용" : (reuse ? "기억한 승인" : "새 승인"))") }
            let id = approval.id
            if remember && !timed { try? developmentApprovals.remember(approval.request, executable: approval.executable) }
            if let timedSessionID, !timedApprovalAllows(timedSessionID) { throw VaultError.accessDenied }
            let process = try CommandRunner.start(approval.request, secrets: secrets, channel: approval.channel, approvedExecutable: approval.executable, files: files) { [weak self] in
                Task { @MainActor in self?.runningProcesses.removeValue(forKey: id); self?.runningInvocations.removeValue(forKey: id) }
            }
            runningInvocations[id] = approval.request
            runningProcesses[id] = process
            if self.approval?.id == approval.id { self.approval = nil }
            activity()
            notify(L10n.tr("CLI를 실행했습니다. 실행 코드는 전달된 키를 읽을 수 있습니다.", "The CLI has been started. The running code can read the keys passed to it."))
        } catch {
            approval.channel.send(CLIEvent(kind: "error", text: error.localizedDescription)); approval.channel.finish()
            if self.approval?.id == approval.id { self.approval = nil }
        }
    }
    var cliURL: URL {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/keydesk")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return (Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL).appendingPathComponent("keydesk")
    }
    func configureBackup(directory: URL?, destination: BackupDestination? = nil) throws {
        if let directory {
            let path = directory.resolvingSymlinksInPath().standardizedFileURL.path
            let vaultPath = store.directory.resolvingSymlinksInPath().standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
                  path != vaultPath, !path.hasPrefix(vaultPath + "/") else { throw VaultError.invalidData }
        }
        try mutate { next in
            let bookmark = try directory?.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            next.backup = directory.map { BackupSettings(directory: $0.path, bookmark: bookmark, destination: destination ?? BackupLocation.destination(of: $0)) }
            next.record(directory == nil ? "자동 백업 해제" : "자동 백업 설정")
        }
        backedUpRevision = nil; lastBackupAt = nil; lastBackupFile = nil; cloudUpload = .notCloud; backupFailure = nil
        flushBackup()
    }
    var backupDestination: BackupDestination? {
        guard let directory = backupDirectory else { return nil }
        return snapshot?.backup?.destination ?? BackupLocation.destination(of: directory)
    }
    var availableICloudBackupDirectory: URL? {
        defaultBackupDirectory ?? (isDemo ? nil : Self.iCloudBackupDirectory)
    }
    func configureICloudBackup() throws {
        guard let directory = availableICloudBackupDirectory else { throw VaultError.invalidData }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try configureBackup(directory: directory, destination: .iCloud)
    }
    var backupDirectory: URL? {
        guard let settings = snapshot?.backup, let path = settings.directory else { return nil }
        if let bookmark = settings.bookmark {
            var stale = false
            // A stale bookmark still resolves to the moved folder; prefer it over the old path.
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    /// True when the current vault revision exists only on this Mac.
    var hasUnbackedChanges: Bool {
        guard let envelope else { return false }
        return backupDirectory == nil || backedUpRevision != envelope.header.revision
    }
    private var backupStatusURL: URL { store.directory.appendingPathComponent("backup-status.json") }
    private func loadBackupStatus() {
        lastBackupFile = backupDirectory.flatMap { BackupManager.latestBackup(in: $0)?.url }
        refreshCloudUpload()
        guard let envelope, let status = BackupStatus.read(at: backupStatusURL, vaultID: envelope.header.vaultID),
              let lastBackupFile, let backup = try? VaultFileStore.read(at: lastBackupFile),
              backup.header.vaultID == status.vaultID, backup.header.revision == status.revision else { backedUpRevision = nil; lastBackupAt = nil; return }
        backedUpRevision = status.revision; lastBackupAt = status.date
    }
    func refreshCloudUpload() {
        cloudUpload = backupDestination == .googleDrive ? .notCloud : (lastBackupFile.map(BackupLocation.cloudUpload(of:)) ?? .notCloud)
    }
    private func recordBackup(revision: UInt64, vaultID: UUID) {
        let now = Date()
        backedUpRevision = revision; lastBackupAt = now; backupFailure = nil
        try? BackupStatus(vaultID: vaultID, revision: revision, date: now).write(to: backupStatusURL)
    }
    /// Batches quick successive edits; lock, quit and settings changes flush immediately.
    private func scheduleBackup() {
        guard hasUnbackedChanges, backupDirectory != nil else { return }
        backupTask?.cancel()
        let token = generation
        backupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, token == self.generation else { return }
            self.flushBackup()
        }
    }
    func flushBackup(force: Bool = false) {
        backupTask?.cancel(); backupTask = nil
        guard let envelope, let key, let directory = backupDirectory, force || backedUpRevision != envelope.header.revision else { return }
        do {
            lastBackupFile = try BackupManager.save(envelope, key: key, directory: directory)
            recordBackup(revision: envelope.header.revision, vaultID: envelope.header.vaultID)
            refreshCloudUpload()
        } catch { backupFailure = L10n.tr("자동 백업에 실패했습니다. 백업 폴더가 연결되어 있는지, 권한과 저장 공간을 확인하세요.", "Automatic backup failed. Check that the backup folder is connected and that permissions and storage space are available.") }
    }
    /// Replaces the recovery key (and optionally the data key). The new state is backed up and checked
    /// with the new recovery key before the local vault changes; iCloud Keychain then gets the new key.
    func rotateVaultKeys(code: String, dataKey: Bool, backupDirectory: URL? = nil) async throws {
        guard !busy, var snapshot, let current = envelope, let currentKey = key else { throw VaultError.locked }
        guard let directory = backupDirectory ?? self.backupDirectory else { throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("먼저 백업 폴더를 정하세요.", "Choose a backup folder first.")]) }
        busy = true; defer { busy = false }
        let token = generation
        if !isDemo { _ = try await keys.authenticate(reason: L10n.tr("금고 암호화 키를 교체하기 위해 인증합니다.", "Authenticate to rotate the vault encryption key.")) }
        guard token == generation else { throw VaultError.locked }
        snapshot.recoveryCode = code
        let (updated, newKey) = try KeyRotation.rotate(snapshot, current: current, newRecoveryCode: code, rotateDataKey: dataKey, currentKey: currentKey)
        let verified = try BackupManager.save(updated, key: newKey, directory: directory)
        _ = try VaultCrypto.recover(VaultFileStore.read(at: verified), code: code)
        if directory == self.backupDirectory { lastBackupFile = verified; refreshCloudUpload() }
        // Stage a separate epoch key before committing the file. The old key remains valid until commit.
        if dataKey && !isDemo { try keys.saveDeviceKey(newKey, id: updated.header.vaultID, epoch: updated.header.keyEpoch) }
        do { try store.write(updated, expectedRevision: current.header.revision) }
        catch { if dataKey && !isDemo { keys.removeDeviceKey(id: updated.header.vaultID, epoch: updated.header.keyEpoch) }; throw error }
        if dataKey && !isDemo { keys.removeDeviceKey(id: current.header.vaultID, epoch: current.header.keyEpoch) }
        self.key = newKey; self.envelope = updated; self.snapshot = try VaultCrypto.open(updated, key: newKey)
        if directory == self.backupDirectory { recordBackup(revision: updated.header.revision, vaultID: updated.header.vaultID) } else { scheduleBackup() }
        ensureRecoveryKeySaved()
        revokeAllGrants(); hideValue(); notify(L10n.tr("키 교체와 새 백업 검증이 완료됐습니다.", "Key rotation and verification of the new backup are complete."))
    }
    private func loadDemo() {
        do {
            let key = SymmetricKey(size: .bits256), recovery = SymmetricKey(size: .bits256), header = VaultHeader()
            var snapshot = VaultSnapshot()
            let project = Project(name: "Studio Notes", colorIndex: 0), other = Project(name: "Daylight", colorIndex: 1)
            snapshot.projects = [project, other]
            for (name, provider, variable) in [(L10n.tr("OpenAI 개발 키", "OpenAI development key"), "OpenAI", "OPENAI_API_KEY"), (L10n.tr("Supabase 서버 키", "Supabase server key"), "Supabase", "SUPABASE_SERVICE_ROLE_KEY"), (L10n.tr("테스트 메일", "Test email"), "Resend", "RESEND_API_KEY"), (L10n.tr("Stripe 테스트", "Stripe test"), "Stripe", "STRIPE_SECRET_KEY")] {
                let credential = Credential(name: name, value: "DEMO_ONLY_\(provider)_not_a_real_credential", provider: provider, account: L10n.tr("개발 계정", "Development account"))
                snapshot.credentials.append(credential)
                snapshot.bindings.append(BindingRecord(projectID: project.id, environment: .development, variable: variable, credentialID: credential.id))
            }
            let wrapped = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
            let envelope = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key)
            let old = FileManager.default.fileExists(atPath: store.vaultURL.path) ? try store.read().header.revision : nil
            try store.write(envelope, expectedRevision: old)
            self.key = key; self.envelope = envelope; self.snapshot = snapshot; selectedProject = project.id
            selectedCredential = snapshot.credentials.first?.id; exists = true; activity()
        } catch { self.error = L10n.tr("데모 금고를 만들지 못했습니다.", "The demo vault could not be created.") }
    }
}
