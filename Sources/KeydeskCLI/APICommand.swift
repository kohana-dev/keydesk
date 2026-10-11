import Foundation
import KeydeskCore

extension KeydeskCommand {
    static func apiRequest(_ args: [String]) throws -> Int32 {
        let request = try APIRequestParser.parse(args) { path in
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
            let data = try handle.read(upToCount: 262_145) ?? Data()
            guard data.count <= 262_144, let text = String(data: data, encoding: .utf8) else { throw VaultError.invalidData }
            return text
        }
        let connection = try ClientConnection(path: ProcessInfo.processInfo.environment["KEYDESK_SOCKET_PATH"] ?? SocketTransport.socketPath)
        defer { connection.closeConnection() }
        try connection.send(request)
        while let line = try SocketTransport.readLine(from: connection.fd, maximum: 2_100_000) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            switch event.kind {
            case "status": if let text = event.text { FileHandle.standardError.write(Data((text + "\n").utf8)) }
            case "stdout": if let data = event.data { FileHandle.standardOutput.write(data) }
            case "exit": return event.exitCode ?? 1
            case "error": FileHandle.standardError.write(Data(((event.text ?? "api_denied") + "\n").utf8)); return 1
            default: throw VaultError.invalidData
            }
        }
        return 1
    }
}
