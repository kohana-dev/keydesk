import Foundation
import CryptoKit
import KeydeskCore

extension VaultModel {
    private var depositPublicURL: URL { store.directory.appendingPathComponent("deposit-public.key") }
    private var depositDirectory: URL { store.directory.appendingPathComponent("deposits") }

    func prepareDeposits() throws {
        guard let snapshot else { throw VaultError.locked }
        if snapshot.depositPrivateKey == nil {
            let generated = P256.KeyAgreement.PrivateKey().rawRepresentation
            try mutate { $0.depositPrivateKey = generated; $0.record("잠금 중 키 접수 준비") }
        }
        guard let raw = self.snapshot?.depositPrivateKey else { throw VaultError.locked }
        let publicKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: raw).publicKey.rawRepresentation
        let vaultID = try store.read().header.vaultID
        try keys.saveDepositPublicKey(publicKey, vaultID: vaultID)
        try VaultFileStore.atomicWrite(publicKey, to: depositPublicURL)
        try VaultFileStore.preparePrivateDirectory(depositDirectory)
        let urls = try FileManager.default.contentsOfDirectory(at: depositDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "deposit" }
        var rejected = 0
        for url in urls {
            do {
                let bytes = try Data(contentsOf: url)
                guard bytes.count <= 2_100_000 else { throw VaultError.invalidData }
                let deposit = try JSONDecoder().decode(SealedDeposit.self, from: bytes).open(privateKey: raw)
                try mutate { $0 = try deposit.adding(to: $0); $0.record("맡긴 키 금고 편입") }
                try FileManager.default.removeItem(at: url)
            } catch { rejected += 1 }
        }
        flushBackup()
        if rejected > 0 { notify("접수한 키 \(rejected)개가 중복 또는 검증 오류로 대기 중입니다. 기존 키는 변경하지 않았습니다.") }
    }

    func deposit(_ deposit: SecretDeposit) throws -> String {
        _ = try deposit.validated()
        // Existing vault content is never needed to seal a locked deposit.
        if snapshot != nil {
            try prepareDeposits()
            try mutate { $0 = try deposit.adding(to: $0); $0.record("CLI 새 키 저장") }
            flushBackup()
            return "stored · 금고 저장 완료. iCloud 업로드 완료 여부는 앱에서 확인하세요."
        }
        let publicKey = try keys.loadDepositPublicKey(vaultID: store.read().header.vaultID)
        guard publicKey.count == 64 else { throw VaultError.invalidData }
        try VaultFileStore.preparePrivateDirectory(depositDirectory)
        let pending = try FileManager.default.contentsOfDirectory(at: depositDirectory, includingPropertiesForKeys: nil)
        guard pending.count < 128 else { throw VaultError.accessDenied }
        let sealed = try SealedDeposit.seal(deposit, publicKey: publicKey)
        try VaultFileStore.atomicWrite(JSONEncoder().encode(sealed), to: depositDirectory.appendingPathComponent("\(deposit.id).deposit"))
        return "queued · 잠금 상태에서 암호화 접수 완료. 이 Mac에만 보관됩니다. 다음 잠금 해제 때 금고 편입·iCloud 백업됩니다."
    }

    func receiveService(_ request: ServiceRequest, channel: CLIChannel) async {
        defer { channel.finish() }
        do {
            switch request.kind {
            case "revoke-runs":
                clearDevelopmentApprovals()
                channel.send(CLIEvent(kind: "status", text: "기억한 실행 승인을 모두 해제했습니다. 이미 실행 중인 프로세스는 유지됩니다. 종료하려면 금고를 잠그세요."))
                channel.send(CLIEvent(kind: "exit", exitCode: 0))
            case "status":
                // Signed local clients can inspect readiness, never vault metadata or values.
                refreshCloudUpload()
                let pending = (try? FileManager.default.contentsOfDirectory(at: depositDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "deposit" }.count) ?? 0
                let report: JSONValue = .object([
                    "locked": .bool(snapshot == nil), "busy": .bool(busy),
                    "pendingDeposits": .number(Double(pending)),
                    "backup": .string(snapshot == nil ? "unknown_locked" : (backupFailure != nil ? "failed" : (hasUnbackedChanges ? "pending" : "verified"))),
                    "cloudUpload": .string(snapshot == nil ? "unknown_locked" : String(describing: cloudUpload))
                ])
                channel.send(CLIEvent(kind: "stdout", data: try JSONEncoder().encode(report) + Data([10])))
                channel.send(CLIEvent(kind: "exit", exitCode: 0))
            case "delete-project":
                guard let current = snapshot, let project = request.project else { throw VaultError.locked }
                let result = try current.deletingProject(project)
                try mutate { next in next = result.snapshot; next.record("프로젝트와 전용 키 삭제 · 과거 백업과 제공사 키는 별도") }
                if !result.snapshot.projects.contains(where: { $0.id == selectedProject }) { selectedProject = nil }
                if !result.snapshot.credentials.contains(where: { $0.id == selectedCredential }) { selectedCredential = nil }
                flushBackup()
                channel.send(CLIEvent(kind: "stdout", data: try JSONEncoder().encode(result.report) + Data([10])))
                channel.send(CLIEvent(kind: "exit", exitCode: 0))
            case "store", "store-file":
                guard (request.kind == "store-file") == (request.file != nil), let project = request.project, let environment = request.environment, let variable = request.variable else { throw VaultError.invalidData }
                let message = try deposit(SecretDeposit(project: project, environment: environment, variable: variable, value: request.value ?? "", file: request.file))
                channel.send(CLIEvent(kind: "status", text: message)); channel.send(CLIEvent(kind: "exit", exitCode: 0))
            case "lock":
                lock()
                channel.send(CLIEvent(kind: "status", text: "금고를 잠갔습니다."))
                channel.send(CLIEvent(kind: "exit", exitCode: 0))
            case "verify-recovery":
                let report = try await verifyCloudRecovery()
                channel.send(CLIEvent(kind: "stdout", data: try JSONEncoder().encode(report) + Data([10])))
                channel.send(CLIEvent(kind: "exit", exitCode: 0))
            default: throw VaultError.invalidData
            }
        } catch {
            // Never include the request or the key value in an error.
            channel.send(CLIEvent(kind: "error", text: "작업 실패: 준비되지 않은 접수 키, 중복 변수, 인증 취소 또는 백업 검증 오류입니다. 앱에서 상태를 확인하세요."))
        }
    }
}
