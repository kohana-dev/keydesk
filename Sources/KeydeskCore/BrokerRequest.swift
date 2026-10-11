import Foundation

public struct BrokerRequest: Codable, Sendable {
    public let kind: String
    public let session: String
    public let project: String
    public let environment: EnvironmentName
    public let tool: String
    public let arguments: [String: JSONValue]
    public init(session: String, project: String, environment: EnvironmentName, tool: String, arguments: [String: JSONValue]) {
        kind = "mcp"; self.session = session; self.project = project; self.environment = environment; self.tool = tool; self.arguments = arguments
    }
}
