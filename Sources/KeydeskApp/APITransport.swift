import Foundation
import Darwin
import KeydeskCore

protocol APITransport: Sendable {
    func execute(_ request: APIRequest, provider: APIProvider, secret: String) async throws -> APIResponse
}

/// Uses the system TLS client with a pinned public IPv4, original hostname/SNI and certificate checks.
/// Authentication and JSON are sent only through stdin, never argv, environment or temporary files.
struct CurlAPITransport: APITransport {
    static func publicAddress(host: String) throws -> String {
        var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &list) == 0, let first = list else { throw VaultError.accessDenied }
        defer { freeaddrinfo(first) }
        var pointer: UnsafeMutablePointer<addrinfo>? = first
        var addresses: [String] = []
        while let current = pointer {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { throw VaultError.accessDenied }
            let address = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard PublicIPv4.allowed(address) else { throw VaultError.accessDenied }
            addresses.append(address); pointer = current.pointee.ai_next
        }
        guard let result = addresses.first else { throw VaultError.accessDenied }
        return result
    }
    static func quoted(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
    static func configuration(_ request: APIRequest, provider: APIProvider, secret: String, address: String) throws -> String {
        let c = try request.validated()
        guard provider.hosts.contains(c.host ?? ""), PublicIPv4.allowed(address), !secret.isEmpty, secret.utf8.count <= 32768,
              !secret.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw VaultError.accessDenied }
        var lines = ["url = \(quoted(request.url))", "request = \(quoted(request.method))", "resolve = \(quoted("\(c.host!):443:\(address)"))",
                     "header = \(quoted("\(provider.header): \(provider.prefix)\(secret)"))", "header = \(quoted("Accept: application/json"))", "user-agent = \(quoted("Keydesk/0.7"))"]
        for (key, value) in provider.extraHeaders.sorted(by: { $0.key < $1.key }) { lines.append("header = \(quoted("\(key): \(value)"))") }
        if let body = request.body { lines += ["header = \(quoted("Content-Type: application/json"))", "data-raw = \(quoted(body))"] }
        if request.method == "HEAD" { lines.append("head") }
        return lines.joined(separator: "\n") + "\n"
    }
    func execute(_ request: APIRequest, provider: APIProvider, secret: String) async throws -> APIResponse {
        let control = APIProcessControl()
        return try await withTaskCancellationHandler {
            try await Task.detached {
                let c = try request.validated()
                let address = try Self.publicAddress(host: c.host!)
                guard !control.cancelled else { throw CancellationError() }
                let configuration = try Self.configuration(request, provider: provider, secret: secret, address: address)
                let process = Process(), input = Pipe(), output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                // -q must be first: ignore ~/.curlrc. No proxy, credentials from netrc, redirects or retries.
                process.arguments = ["-q", "--config", "-", "--silent", "--proto", "=https", "--proto-redir", "=https", "--noproxy", "*", "--proxy", "", "--ipv4", "--globoff", "--max-time", "30", "--connect-timeout", "10", "--max-filesize", "1048576", "--retry", "0", "--write-out", "\n%{http_code}"]
                process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
                process.standardInput = input; process.standardOutput = output
                let null = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null")); defer { try? null.close() }
                process.standardError = null
                try control.start(process)
                try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
                DispatchQueue.global().async {
                    try? input.fileHandleForWriting.write(contentsOf: Data(configuration.utf8))
                    try? input.fileHandleForWriting.close()
                }
                defer { try? output.fileHandleForReading.close(); control.finish() }
                var data = Data()
                do {
                    while let chunk = try output.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
                        guard data.count + chunk.count <= 1_048_580 else { control.cancel(); throw VaultError.accessDenied }
                        data.append(chunk)
                    }
                } catch { control.cancel(); process.waitUntilExit(); throw VaultError.accessDenied }
                process.waitUntilExit()
                guard !control.cancelled, process.terminationStatus == 0, data.count >= 4,
                      let text = String(data: data, encoding: .utf8), let newline = text.lastIndex(of: "\n"),
                      let status = Int(text[text.index(after: newline)...]) else { throw VaultError.accessDenied }
                let response = try APIResponse(status: status, body: String(text[..<newline])).validated(secret: secret)
                return request.method == "HEAD" ? APIResponse(status: status, body: "") : response
            }.value
        } onCancel: { control.cancel() }
    }
}
