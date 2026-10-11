import Foundation

public struct APIApprovalGrant: Identifiable, Sendable {
    public let id: UUID
    public let request: APIRequest
    public let credentialID: UUID
    public let versionID: UUID
    public let expiresAt: Date
    public var remainingUses: Int
}

/// Exact method, URL (including query), JSON body, project, key and key version.
/// Non-idempotent requests are never retried by the transport.
public struct APIApprovalCache {
    private var entries: [APIApprovalGrant] = []
    public init() {}
    public func active(now: Date = Date()) -> [APIApprovalGrant] { entries.filter { $0.expiresAt > now && $0.remainingUses > 0 } }
    public mutating func remember(_ request: APIRequest, credentialID: UUID, versionID: UUID, now: Date = Date()) {
        entries.removeAll { $0.expiresAt <= now || $0.remainingUses <= 0 || $0.request == request }
        if entries.count >= 32 { entries.removeFirst() }
        entries.append(APIApprovalGrant(id: UUID(), request: request, credentialID: credentialID, versionID: versionID,
            expiresAt: now.addingTimeInterval(request.environment == .production ? 300 : 1800), remainingUses: request.environment == .production ? 10 : 100))
    }
    public mutating func consume(_ request: APIRequest, credentialID: UUID, versionID: UUID, now: Date = Date()) -> UUID? {
        guard let i = entries.firstIndex(where: { $0.request == request && $0.credentialID == credentialID && $0.versionID == versionID && $0.expiresAt > now && $0.remainingUses > 0 }) else { return nil }
        entries[i].remainingUses -= 1
        return entries[i].id
    }
    public mutating func revoke(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func clear() { entries.removeAll() }
}
