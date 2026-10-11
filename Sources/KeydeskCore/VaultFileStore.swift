import Foundation
import Darwin

public struct VaultFileStore: Sendable {
    public let directory: URL
    public var vaultURL: URL { directory.appendingPathComponent("vault.keydesk") }
    public var previousURL: URL { directory.appendingPathComponent("previous.keydesk") }
    public init(directory: URL) { self.directory = directory }
    public func read() throws -> VaultEnvelope { try Self.read(at: vaultURL) }
    public static func read(at url: URL) throws -> VaultEnvelope {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw VaultError.invalidData }
        defer { close(fd) }
        var info = stat()
        let maximum = 32 * 1024 * 1024
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= maximum else { throw VaultError.invalidData }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw VaultError.invalidData }
            if count == 0 { break }
            guard data.count + count <= maximum else { throw VaultError.invalidData }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try JSONDecoder().decode(VaultEnvelope.self, from: data)
    }
    public static func preparePrivateDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw VaultError.accessDenied }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), fchmod(fd, 0o700) == 0 else { throw VaultError.accessDenied }
    }
    public func write(_ envelope: VaultEnvelope, expectedRevision: UInt64?) throws {
        try Self.preparePrivateDirectory(directory)
        let lockURL = directory.appendingPathComponent("writer.lock")
        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        if FileManager.default.fileExists(atPath: vaultURL.path) {
            let current = try read()
            guard expectedRevision == current.header.revision else { throw VaultError.staleRevision }
            try Self.atomicWrite(Data(contentsOf: vaultURL), to: previousURL)
        } else if expectedRevision != nil { throw VaultError.staleRevision }
        try Self.atomicWrite(JSONEncoder().encode(envelope), to: vaultURL)
    }
    public static func atomicWrite(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".keydesk-\(UUID()).tmp")
        let fd = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        defer { close(fd); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
        guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else { throw POSIXError(.EIO) }
        let directoryFD = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
        if directoryFD >= 0 { _ = fsync(directoryFD); close(directoryFD) }
    }
}
