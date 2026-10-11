import Foundation

public struct BindingRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let environment: EnvironmentName
    public var variable: String
    public let credentialID: UUID
    public init(projectID: UUID, environment: EnvironmentName, variable: String, credentialID: UUID) {
        id = UUID(); self.projectID = projectID; self.environment = environment
        self.variable = variable; self.credentialID = credentialID
    }
}
