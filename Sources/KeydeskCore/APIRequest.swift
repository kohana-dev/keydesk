import Foundation
import CryptoKit

/// No credential value or arbitrary authentication headers cross the client socket.
public struct APIRequest: Codable, Sendable, Equatable {
    public let kind: String
    public let project: String
    public let environment: EnvironmentName
    public let variable: String
    public let method: String
    public let url: String
    public let body: String?
    /// RFC 6901 pointer into a stored key-value or JSON document. Never contains its selected value.
    public let field: String?
    /// A fixed supported service, required for selected documents whose provider is Other.
    public let provider: String?
    public init(project: String, environment: EnvironmentName, variable: String, method: String, url: String, body: String? = nil, field: String? = nil, provider: String? = nil) {
        kind = "api-request"; self.project = project; self.environment = environment
        self.variable = variable; self.method = method; self.url = url; self.body = body
        self.field = field; self.provider = provider
    }
    public func validated() throws -> URLComponents {
        guard kind == "api-request", !project.isEmpty, project.count <= 128,
              VaultSnapshot.validVariable(variable), !VaultSnapshot.blockedVariable(variable),
              ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"].contains(method),
              url.utf8.count <= 8192, !url.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }),
              let c = URLComponents(string: url), c.scheme == "https", c.user == nil, c.password == nil,
              c.fragment == nil, c.port == nil || c.port == 443, let host = c.host,
              host == host.lowercased(), host.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil,
              c.url != nil, !c.percentEncodedPath.contains("\\"),
              !c.percentEncodedPath.lowercased().contains("%2f"), !c.percentEncodedPath.lowercased().contains("%5c"),
              !c.percentEncodedPath.lowercased().contains("%2e"),
              !c.path.split(separator: "/").contains(".."),
              body == nil || (method != "GET" && method != "HEAD") else { throw VaultError.accessDenied }
        if let field { _ = try SecretValueSelector.pointerTokens(field) }
        if let provider {
            guard field != nil, provider.utf8.count <= 64,
                  !provider.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  APIProvider.supported.contains(where: { $0.name == ProviderName.canonical(provider) }) else { throw VaultError.accessDenied }
        }
        if let body {
            guard body.utf8.count <= 262_144, !body.contains("\0"),
                  (try? JSONSerialization.jsonObject(with: Data(body.utf8), options: [.fragmentsAllowed])) != nil else { throw VaultError.invalidData }
        }
        return c
    }
    public var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}
