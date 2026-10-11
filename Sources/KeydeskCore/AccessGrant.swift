import Foundation

public struct AccessGrant: Identifiable, Sendable {
    public let id: String
    public let session: String
    public let projectID: UUID
    public let environment: EnvironmentName
    public let connectionID: UUID?
    public let operation: String
    public let resource: String?
    public let expiresAt: Date
    public let maximumCalls: Int
    public var usedCalls: Int
    public init(session: String, projectID: UUID, environment: EnvironmentName, connectionID: UUID?, operation: String, resource: String?, duration: TimeInterval = 600, maximumCalls: Int = 10, now: Date = Date()) {
        id = UUID().uuidString + UUID().uuidString; self.session = session; self.projectID = projectID; self.environment = environment
        self.connectionID = connectionID; self.operation = operation; self.resource = resource
        expiresAt = now.addingTimeInterval(min(max(duration, 1), 600)); self.maximumCalls = min(max(maximumCalls, 1), 20); usedCalls = 0
    }
    public mutating func reserve(session: String, projectID: UUID, environment: EnvironmentName, connectionID: UUID?, operation: String, resource: String?, now: Date = Date()) throws {
        guard self.session == session, self.projectID == projectID, self.environment == environment,
              self.connectionID == connectionID, self.operation == operation, self.resource == resource,
              now < expiresAt, usedCalls < maximumCalls else { throw VaultError.accessDenied }
        usedCalls += 1
    }
}
