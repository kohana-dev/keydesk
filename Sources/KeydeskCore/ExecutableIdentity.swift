import Foundation
import CryptoKit
import Darwin

public struct ExecutableIdentity: Sendable {
    public let path: String
    public let digest: Data
    public static var searchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }
    public static func capture(command: String, directory: String) throws -> Self {
        guard !command.isEmpty, !command.contains("\0") else { throw VaultError.accessDenied }
        let candidate: String
        if command.hasPrefix("/") { candidate = command }
        else if command.contains("/") { candidate = URL(fileURLWithPath: directory).appendingPathComponent(command).path }
        else {
            guard let found = searchPath.split(separator: ":").map({ "\($0)/\(command)" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw VaultError.accessDenied }
            candidate = found
        }
        let path = URL(fileURLWithPath: candidate).standardizedFileURL.resolvingSymlinksInPath().path
        guard FileManager.default.isExecutableFile(atPath: path) else { throw VaultError.accessDenied }
        return Self(path: path, digest: try hashFile(path))
    }
    public func validate() throws {
        guard FileManager.default.isExecutableFile(atPath: path), try Self.hashFile(path) == digest else {
            throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("승인할 실행 파일이 변경되었습니다. 새 요청을 보내 주세요.", "The executable to approve has changed. Send a new request.")])
        }
    }
    static func hashFile(_ path: String) throws -> Data {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw VaultError.accessDenied }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= 256 * 1024 * 1024 else { throw VaultError.accessDenied }
        var hash = SHA256(), buffer = [UInt8](repeating: 0, count: 65_536), total = 0
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw VaultError.accessDenied }
            if count == 0 { break }
            total += count
            guard total <= 256 * 1024 * 1024 else { throw VaultError.accessDenied }
            hash.update(data: Data(buffer.prefix(count)))
        }
        guard total == info.st_size else { throw VaultError.accessDenied }
        return Data(hash.finalize())
    }
}
