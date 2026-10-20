import Foundation
import KeydeskCore

enum MCPServer {
    static let definitions: JSONValue = .array([
        tool("request_http", "Call a fixed official HTTPS API using a stored API key or one explicitly selected string field from a key-value/JSON item. field is an RFC 6901 JSON Pointer; provider is required for documents stored as Other. Human approval binds field and provider as well as the request. Returns API data, never authentication values or document contents. Weather providers support bodyless GET only; put location/options in the URL and omit all authentication parameters/placeholders. Cellar inserts query or header authentication internally. Files and SDK commands use keydesk run.", ["key": stringSchema, "field": .object(["type": .string("string"), "maxLength": .number(2048)]), "provider": .object(["type": .string("string"), "enum": .array(APIProvider.supported.map { .string($0.name) })]), "method": .object(["type": .string("string"), "enum": .array(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"].map(JSONValue.string))]), "url": .object(["type": .string("string"), "maxLength": .number(8192)]), "body": .object(["type": .string("string"), "maxLength": .number(262144)])], ["key", "method", "url"]),
        tool("list_connections", "List the environment variable names and provider names stored for this project and environment, plus the keydesk run command to use them. Never returns key values. Requires request_access first.", [:], []),
        tool("request_access", "Ask the user, in the Keydesk app, to allow this session to list variable names for a limited time and number of calls.", ["operation": .object(["type": .string("string"), "enum": .array([.string("metadata")])]), "duration": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(600)]), "maximumCalls": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(20)])], []),
        tool("revoke_access", "Revoke a name-listing permission granted to this session.", ["grantId": stringSchema], ["grantId"])
    ])
    static var stringSchema: JSONValue { .object(["type": .string("string"), "maxLength": .number(256)]) }
    static func tool(_ name: String, _ description: String, _ properties: [String: JSONValue], _ required: [String]) -> JSONValue {
        .object(["name": .string(name), "description": .string(description), "inputSchema": .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)])])
    }
    static func run(_ args: [String]) throws -> Int32 {
        var project: String?, environment = EnvironmentName.development, index = 0
        while index < args.count {
            guard index + 1 < args.count else { throw VaultError.invalidData }
            if args[index] == "--project" { project = args[index + 1] }
            else if args[index] == "--env", let value = EnvironmentName(rawValue: args[index + 1]) { environment = value }
            else { throw VaultError.invalidData }
            index += 2
        }
        guard let project, UUID(uuidString: project) != nil else { throw VaultError.invalidData }
        let dispatcher = MCPDispatcher(project: project, environment: environment)
        var initialized = false, ready = false
        while let line = try SocketTransport.readLine(from: 0, maximum: 65_536) {
            let message: JSONValue
            do { message = try JSONDecoder().decode(JSONValue.self, from: line) }
            catch { dispatcher.error(.null, code: -32700, message: "Invalid JSON"); continue }
            guard message["jsonrpc"] == .string("2.0"), let method = message["method"]?.string else {
                dispatcher.error(.null, code: -32600, message: "Invalid JSON-RPC request"); continue
            }
            let id = message["id"]
            if method == "notifications/initialized" { ready = initialized; continue }
            if method == "notifications/cancelled" { if let requestID = message["params"]?["requestId"] { dispatcher.cancel(requestID) }; continue }
            guard let id else { continue }
            switch id {
            case .string, .number: break
            default: dispatcher.error(.null, code: -32600, message: "Invalid request ID"); continue
            }
            switch method {
            case "initialize":
                guard !initialized else { dispatcher.error(id, code: -32600, message: "Already initialized"); continue }
                let requested = message["params"]?["protocolVersion"]?.string ?? ""
                let supported = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
                let version = supported.contains(requested) ? requested : "2025-11-25"
                dispatcher.result(id, .object(["protocolVersion": .string(version), "capabilities": .object(["tools": .object([:])]), "serverInfo": .object(["name": .string("keydesk"), "version": .string("0.7.21")]), "instructions": .string("Keydesk exposes metadata and request_http for one project. request_http can select a string field with field/provider and calls approved official APIs without giving keys to your process. Weather APIs use GET without a body. Supply only non-secret location/options in the URL; omit authentication query parameters and key placeholders. The app injects authentication internally. For SDK commands use keydesk run --select OUTPUT=SOURCE#/pointer; original files use --files. Initial approval is in the app; exact requests can reuse time-limited grants. Never try to print, encode or transmit key values." )]))
                initialized = true
            case "ping": dispatcher.result(id, .object([:]))
            case "tools/list":
                if ready { dispatcher.result(id, .object(["tools": definitions])) }
                else { dispatcher.error(id, code: -32000, message: "Not initialized") }
            case "tools/call":
                guard ready, let name = message["params"]?["name"]?.string,
                      let arguments = message["params"]?["arguments"]?.object else { dispatcher.error(id, code: -32602, message: "Invalid tool parameters"); continue }
                guard case .array(let tools) = definitions, let definition = tools.first(where: { $0["name"]?.string == name }),
                      let properties = definition["inputSchema"]?["properties"]?.object,
                      Set(arguments.keys).isSubset(of: Set(properties.keys)) else { dispatcher.error(id, code: -32602, message: "Unsupported tool or arguments"); continue }
                dispatcher.call(id, name: name, arguments: arguments)
            default: dispatcher.error(id, code: -32601, message: "Method not found")
            }
        }
        dispatcher.cancelAll()
        return 0
    }
}
