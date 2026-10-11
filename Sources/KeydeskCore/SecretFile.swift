import Foundation
import Darwin

/// Raw file bytes are encoded only inside the encrypted vault/deposit payload.
public struct SecretFile: Codable, Equatable, Sendable {
    public static let maximumBytes = 1_048_576
    public let name: String
    public let data: Data
    public init(name: String, data: Data) throws {
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
              !name.contains("/"), !name.contains("\\"), !name.contains("\0"),
              data.count <= Self.maximumBytes else { throw VaultError.invalidData }
        self.name = name; self.data = data
    }
    public func validated() throws -> Self { try Self(name: name, data: data) }
    public static func read(at url: URL) throws -> Self {
        guard url.isFileURL else { throw VaultError.invalidData }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw VaultError.invalidData }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw VaultError.invalidData }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0, bytes.count + count <= maximumBytes else { throw VaultError.invalidData }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return try Self(name: url.lastPathComponent, data: bytes)
    }
}
