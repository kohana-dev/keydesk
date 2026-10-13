import Foundation
import KeydeskCore

extension VaultModel {
    private func resolveAPI(_ request: APIRequest, channel: CLIChannel) throws -> APIApproval {
        guard let snapshot else { throw VaultError.locked }
        let matches = snapshot.projects.filter { $0.name == request.project || $0.id.uuidString.lowercased() == request.project.lowercased() }
        guard matches.count == 1,
              let binding = snapshot.bindings.first(where: { $0.projectID == matches[0].id && $0.environment == request.environment && $0.variable == request.variable }),
              let credential = snapshot.credentials.first(where: { $0.id == binding.credentialID }),
              credential.currentFile == nil, let secret = credential.currentValue, !secret.isEmpty else { throw VaultError.accessDenied }
        let canonical = APIRequest(project: matches[0].id.uuidString, environment: request.environment, variable: request.variable, method: request.method, url: request.url, body: request.body)
        let provider = try APIProvider.resolve(provider: credential.provider, request: canonical)
        return APIApproval(request: canonical, projectName: matches[0].name, credentialID: credential.id,
                           versionID: credential.currentVersionID, provider: provider, channel: channel)
    }
    func receiveAPI(_ request: APIRequest, channel: CLIChannel) {
        do {
            guard !busy, approval == nil, brokerApproval == nil, apiApproval == nil, apiTasks.count < 4 else { throw VaultError.accessDenied }
            let pending = try resolveAPI(request, channel: channel)
            if apiApprovals.consume(pending.request, credentialID: pending.credentialID, versionID: pending.versionID) != nil {
                channel.send(CLIEvent(kind: "status", text: L10n.tr("기억한 API 승인으로 요청합니다.", "Sending the request with a remembered API approval.")))
                startAPI(pending, reused: true)
                return
            }
            channel.send(CLIEvent(kind: "status", text: L10n.tr("새 요청, 요청 내용 변경, 만료 또는 횟수 소진: Cellar에서 API 사용을 승인해 주세요.", "New request, changed request details, expired approval, or no uses left: approve API access in Cellar.")))
            apiApproval = pending
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(60))
                if self?.apiApproval?.id == pending.id { self?.rejectAPI() }
            }
        } catch { apiFailure(channel, code: snapshot == nil ? "vault_locked" : "api_request_denied") }
    }
    func rejectAPI() {
        if let pending = apiApproval { apiFailure(pending.channel, code: "api_approval_denied_or_timeout") }
        apiApproval = nil
    }
    func acceptAPI(remember: Bool) async {
        guard let pending = apiApproval else { return }
        let token = generation
        do {
            if pending.request.environment == .production && !isDemo {
                _ = try await keys.authenticate(reason: L10n.tr("Production 키로 지정한 API 요청을 실행하기 위해 인증합니다.", "Authenticate to execute the specified API request with a Production key."))
            }
            guard generation == token, apiApproval?.id == pending.id, pending.channel.isConnected else { throw VaultError.locked }
            let current = try resolveAPI(pending.request, channel: pending.channel)
            guard current.credentialID == pending.credentialID, current.versionID == pending.versionID else { throw VaultError.accessDenied }
            if remember { apiApprovals.remember(pending.request, credentialID: pending.credentialID, versionID: pending.versionID) }
            apiApproval = nil
            startAPI(pending, reused: false)
        } catch { apiFailure(pending.channel, code: "api_approval_denied"); apiApproval = nil }
    }
    private func startAPI(_ pending: APIApproval, reused: Bool) {
        guard let secret = snapshot?.credentials.first(where: { $0.id == pending.credentialID && $0.currentVersionID == pending.versionID })?.currentValue,
              pending.channel.isConnected else { apiFailure(pending.channel, code: "api_request_denied"); return }
        let token = generation, id = pending.id, transport = apiTransport
        apiRunning[id] = pending.request
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let watcher = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    if !pending.channel.isConnected { self?.apiTasks[id]?.cancel(); return }
                }
            }
            defer { watcher.cancel(); self.apiTasks.removeValue(forKey: id); self.apiRunning.removeValue(forKey: id); pending.channel.finish() }
            do {
                try self.mutate(invalidateGrants: false) { $0.record("API 시작 · \(id.uuidString) · \(pending.request.environment.title) · \(reused ? "승인 재사용" : "새 승인")") }
                let response = try await transport.execute(pending.request, provider: pending.provider, secret: secret).validated(secret: secret)
                try Task.checkCancellation()
                guard token == self.generation, self.snapshot != nil, pending.channel.isConnected else { throw VaultError.locked }
                try self.mutate(invalidateGrants: false) { $0.record("API 완료 · \(id.uuidString) · HTTP \(response.status)") }
                let report: JSONValue = .object(["requestId": .string(id.uuidString), "status": .number(Double(response.status)),
                    "body": .string(response.body), "approval": .string(reused ? "reused" : "new"), "credentialDelivery": .string("broker_only")])
                pending.channel.send(CLIEvent(kind: "stdout", data: try JSONEncoder().encode(report) + Data([10])))
                pending.channel.send(CLIEvent(kind: "exit", exitCode: response.status >= 400 ? 2 : 0))
                self.activity()
            } catch {
                // No upstream error string, URL, auth header, or response content in failure logs.
                if token == self.generation && self.snapshot != nil { try? self.mutate(invalidateGrants: false) { $0.record("API 중단 또는 결과 미확인 · \(id.uuidString)") } }
                self.apiFailure(pending.channel, code: "api_failed_or_cancelled_no_automatic_retry")
            }
        }
        apiTasks[id] = task
    }
    private func apiFailure(_ channel: CLIChannel, code: String) {
        channel.send(CLIEvent(kind: "error", text: code)); channel.finish()
    }
    func revokeAPI(_ id: UUID) { apiApprovals.revoke(id) }
    func revokeAllAPI() {
        apiApprovals.clear(); rejectAPI()
        for task in apiTasks.values { task.cancel() }
    }
    func revokeAllPermissions() { clearDevelopmentApprovals(); revokeAllGrants(); apiApprovals.clear() }
    func cancelAPI(_ id: UUID) { apiTasks[id]?.cancel() }
}
