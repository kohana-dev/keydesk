import Foundation
import KeydeskCore

final class MCPDispatcher: @unchecked Sendable {
    private let project: String
    private let environment: EnvironmentName
    private let session = UUID().uuidString
    private let outputLock = NSLock()
    private let lock = NSLock()
    private var connections: [String: ClientConnection] = [:]
    private var reserved = Set<String>()
    private var cancelled = Set<String>()
    private let group = DispatchGroup()
    init(project: String, environment: EnvironmentName) { self.project = project; self.environment = environment }
    private func identifier(_ id: JSONValue) -> String { String(decoding: (try? JSONEncoder().encode(id)) ?? Data(), as: UTF8.self) }
    private func send(_ value: JSONValue) {
        outputLock.lock(); defer { outputLock.unlock() }
        if let bytes = try? JSONEncoder().encode(value) { FileHandle.standardOutput.write(bytes + Data([10])) }
    }
    func result(_ id: JSONValue, _ result: JSONValue) { send(.object(["jsonrpc": .string("2.0"), "id": id, "result": result])) }
    func error(_ id: JSONValue, code: Double, message: String) { send(.object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(code), "message": .string(message)])])) }
    func call(_ id: JSONValue, name: String, arguments: [String: JSONValue]) {
        let identifier = identifier(id)
        lock.lock()
        guard reserved.count < 8, reserved.insert(identifier).inserted else { lock.unlock(); error(id, code: -32000, message: "Busy or duplicate request"); return }
        group.enter(); lock.unlock()
        DispatchQueue.global().async {
            defer { self.lock.lock(); self.reserved.remove(identifier); self.cancelled.remove(identifier); self.connections.removeValue(forKey: identifier)?.closeConnection(); self.lock.unlock(); self.group.leave() }
            do {
                if name == "request_http", arguments["field"] != nil { try BrokerCapabilities.requireFieldSelection() }
                let connection = try ClientConnection(path: ProcessInfo.processInfo.environment["KEYDESK_SOCKET_PATH"] ?? SocketTransport.socketPath)
                self.lock.lock()
                guard self.reserved.contains(identifier), !self.cancelled.contains(identifier) else { self.lock.unlock(); connection.closeConnection(); return }
                self.connections[identifier] = connection; self.lock.unlock()
                if name == "request_http" {
                    guard Set(arguments.keys).isSubset(of: ["key", "method", "url", "body", "field", "provider"]),
                          let key = arguments["key"]?.string, let method = arguments["method"]?.string, let url = arguments["url"]?.string,
                          arguments["body"] == nil || arguments["body"]?.string != nil,
                          arguments["field"] == nil || arguments["field"]?.string != nil,
                          arguments["provider"] == nil || arguments["provider"]?.string != nil else { throw VaultError.invalidData }
                    let request = APIRequest(project: self.project, environment: self.environment, variable: key, method: method, url: url, body: arguments["body"]?.string, field: arguments["field"]?.string, provider: arguments["provider"]?.string)
                    _ = try request.validated()
                    try connection.send(request)
                    var payload: JSONValue?, failure = false
                    while let data = try SocketTransport.readLine(from: connection.fd, maximum: 2_100_000) {
                        let event = try JSONDecoder().decode(CLIEvent.self, from: data)
                        if event.kind == "stdout", let bytes = event.data { payload = try JSONDecoder().decode(JSONValue.self, from: bytes) }
                        if event.kind == "error" { payload = .object(["error": .string(event.text ?? "api_denied")]); failure = true; break }
                        if event.kind == "exit" { failure = event.exitCode != 0; break }
                    }
                    guard let payload else { throw VaultError.locked }
                    self.toolResult(id, payload: payload, failure: failure); return
                }
                try connection.send(BrokerRequest(session: self.session, project: self.project, environment: self.environment, tool: name, arguments: arguments))
                guard let data = try SocketTransport.readLine(from: connection.fd) else { throw VaultError.locked }
                let response = try JSONDecoder().decode(JSONValue.self, from: data)
                let failure = response["error"] != nil
                let payload = response["result"] ?? .object(["error": response["error"] ?? .string("unavailable")])
                let text = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
                self.result(id, .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])]), "structuredContent": payload, "isError": .bool(failure)]))
            } catch { self.result(id, .object(["content": .array([.object(["type": .string("text"), "text": .string("앱 연결이 끊겼거나 금고가 잠겨 있습니다.")])]), "isError": .bool(true)])) }
        }
    }
    private func toolResult(_ id: JSONValue, payload: JSONValue, failure: Bool) {
        let text = String(decoding: (try? JSONEncoder().encode(payload)) ?? Data(), as: UTF8.self)
        result(id, .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])]), "structuredContent": payload, "isError": .bool(failure)]))
    }
    func cancel(_ id: JSONValue) {
        let identifier = identifier(id)
        lock.lock(); cancelled.insert(identifier); let connection = connections[identifier]; lock.unlock()
        connection?.closeConnection()
    }
    func cancelAll() {
        lock.lock(); reserved.removeAll(); let all = Array(connections.values); lock.unlock()
        all.forEach { $0.closeConnection() }; group.wait()
    }
}
