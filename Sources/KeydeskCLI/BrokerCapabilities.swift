import Foundation
import KeydeskCore

enum BrokerCapabilities {
    /// Older apps ignore unknown Codable fields. Check support before sending a selector so
    /// they cannot silently execute the request as an ordinary whole-key invocation.
    static func requireFieldSelection() throws {
        let connection = try ClientConnection(path: ProcessInfo.processInfo.environment["KEYDESK_SOCKET_PATH"] ?? SocketTransport.socketPath)
        defer { connection.closeConnection() }
        try connection.send(ServiceRequest(kind: "status"))
        var supported = false
        while let line = try SocketTransport.readLine(from: connection.fd) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            if event.kind == "stdout", let data = event.data,
               let payload = try? JSONDecoder().decode(JSONValue.self, from: data),
               case .array(let capabilities) = payload["capabilities"] {
                supported = capabilities.contains(.string("field-selection-v1"))
            }
            if event.kind == "exit", event.exitCode == 0, supported { return }
            if event.kind == "error" || event.kind == "exit" { break }
        }
        throw NSError(domain: "Cellar", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("필드 선택을 사용하려면 Cellar 앱과 함께 제공되는 CLI를 0.7.20 이상으로 업데이트하세요.", "Update the Cellar app and its bundled CLI to 0.7.20 or later to select document fields.")])
    }
}
