import Foundation
import AppKit
import KeydeskCore

/// MCP is metadata-only: an approved AI session can learn which variable names exist for one
/// project and environment, so it can write `keydesk run --only NAME -- command`. Values never
/// leave the app through this path and the app makes no network requests on the AI's behalf.
extension VaultModel {
    func brokerError(_ channel: CLIChannel, _ code: String) {
        channel.sendValue(JSONValue.object(["error": .string(code)])); channel.finish()
    }
    func brokerResult(_ channel: CLIChannel, _ result: JSONValue) {
        channel.sendValue(JSONValue.object(["result": result])); channel.finish()
    }
    func expireGrants() {
        for id in grants.filter({ $0.value.expiresAt <= Date() }).map(\.key) { revokeGrant(id) }
    }
    func revokeAllGrants() { grants.removeAll() }
    func revokeGrant(_ id: String) { grants.removeValue(forKey: id) }
    func rejectBroker() {
        if let pending = brokerApproval { brokerError(pending.channel, "access_denied") }
        brokerApproval = nil
    }
    func acceptBroker() async {
        guard let pending = brokerApproval else { return }
        let token = generation
        do {
            if !isDemo && pending.request.environment == .production { _ = try await keys.authenticate(reason: "Production 키 이름 목록을 AI에 보여주기 위해 인증합니다.") }
            guard pending.channel.isConnected, pending.grant.expiresAt > Date(), token == generation, snapshot != nil, brokerApproval?.id == pending.id else { throw VaultError.locked }
            try mutate(invalidateGrants: false) { $0.record("AI 키 이름 조회 허가 · \(pending.request.environment.title)") }
            grants[pending.grant.id] = pending.grant
            brokerResult(pending.channel, .object(["grantId": .string(pending.grant.id), "expiresAt": .string(pending.grant.expiresAt.formatted(.iso8601)), "maximumCalls": .number(Double(pending.grant.maximumCalls))]))
            brokerApproval = nil
        } catch { brokerError(pending.channel, "access_denied"); brokerApproval = nil }
    }
    func receiveBroker(_ request: BrokerRequest, channel: CLIChannel) {
        expireGrants()
        guard let snapshot else { brokerError(channel, "vault_locked"); return }
        guard let projectID = UUID(uuidString: request.project), let project = snapshot.projects.first(where: { $0.id == projectID }), !request.session.isEmpty else { brokerError(channel, "access_denied"); return }
        let a = request.arguments
        do {
            switch request.tool {
            case "list_connections":
                guard a.isEmpty, let id = grants.first(where: { $0.value.session == request.session && $0.value.projectID == projectID && $0.value.environment == request.environment && $0.value.usedCalls < $0.value.maximumCalls })?.key else { throw VaultError.accessDenied }
                try grants[id]!.reserve(session: request.session, projectID: projectID, environment: request.environment, connectionID: nil, operation: "metadata", resource: nil)
                let variables = snapshot.bindings.filter { $0.projectID == projectID && $0.environment == request.environment }.sorted { $0.variable < $1.variable }.compactMap { binding -> JSONValue? in
                    guard let credential = snapshot.credentials.first(where: { $0.id == binding.credentialID }) else { return nil }
                    return .object(["variable": .string(binding.variable), "provider": .string(ProviderName.canonical(credential.provider)), "kind": .string(credential.currentFile == nil ? "value" : "file")])
                }
                let usage = "keydesk run --project \(projectID.uuidString) --env \(request.environment.rawValue) --only VARIABLE -- <command>"
                brokerResult(channel, .object(["variables": .array(variables), "usage": .string(usage), "fileUsage": .string("keydesk run --project \(projectID.uuidString) --env \(request.environment.rawValue) --files FILE_VARIABLE -- <command>"), "note": .string("Each run is approved by the user in the Keydesk app. Values are never returned here.")]))
            case "request_access":
                guard Set(a.keys).isSubset(of: ["operation", "duration", "maximumCalls"]), a["operation"] == nil || a["operation"]?.string == "metadata",
                      brokerApproval == nil, approval == nil, grants.count < 32 else { throw VaultError.accessDenied }
                let duration = a["duration"]?.number ?? 600, maximum = a["maximumCalls"]?.number ?? 10
                if a["duration"] != nil && a["duration"]?.number == nil { throw VaultError.accessDenied }
                if a["maximumCalls"] != nil && a["maximumCalls"]?.number == nil { throw VaultError.accessDenied }
                guard duration >= 1, duration <= 600, duration.rounded() == duration, maximum >= 1, maximum <= 20, maximum.rounded() == maximum else { throw VaultError.accessDenied }
                let grant = AccessGrant(session: request.session, projectID: projectID, environment: request.environment, connectionID: nil, operation: "metadata", resource: nil, duration: duration, maximumCalls: Int(maximum))
                let pending = BrokerApproval(request: request, channel: channel, grant: grant, projectName: project.name)
                brokerApproval = pending
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(60))
                    if self?.brokerApproval?.id == pending.id { self?.rejectBroker() }
                }
            case "revoke_access":
                guard Set(a.keys) == ["grantId"], let id = a["grantId"]?.string, let grant = grants[id], grant.session == request.session,
                      grant.projectID == projectID, grant.environment == request.environment else { throw VaultError.accessDenied }
                revokeGrant(id); brokerResult(channel, .object(["revoked": .bool(true)]))
            default: throw VaultError.accessDenied
            }
        } catch { brokerError(channel, "access_required_or_denied") }
    }
}
