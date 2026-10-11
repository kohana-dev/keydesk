import Foundation
import Darwin

/// Same-user programs are not sandboxed. Files are scoped to one approved run.
public final class TemporarySecretFiles: @unchecked Sendable {
    public static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Keydesk-run-files-\(getuid())", isDirectory: true) }
    public let directory: URL
    public private(set) var paths = [String: String]()
    private let lock = NSLock()
    private var removed = false
    public init(files: [String: SecretFile], root: URL = TemporarySecretFiles.root) throws {
        try VaultFileStore.preparePrivateDirectory(root)
        directory = root.appendingPathComponent("\(getpid())-\(UUID())", isDirectory: true)
        try VaultFileStore.preparePrivateDirectory(directory)
        do {
            for (variable, file) in files {
                _ = try file.validated()
                guard VaultSnapshot.validVariable(variable), !VaultSnapshot.blockedVariable(variable) else { throw VaultError.unsafeEnvironment }
                let folder = directory.appendingPathComponent(variable, isDirectory: true)
                try VaultFileStore.preparePrivateDirectory(folder)
                let url = folder.appendingPathComponent(file.name)
                try VaultFileStore.atomicWrite(file.data, to: url)
                paths[variable] = url.path
            }
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    public func cleanup() {
        lock.lock(); defer { lock.unlock() }
        guard !removed else { return }
        removed = true; try? FileManager.default.removeItem(at: directory)
    }
    deinit { cleanup() }
    public static func cleanupOrphans(root: URL = TemporarySecretFiles.root) {
        guard (try? VaultFileStore.preparePrivateDirectory(root)) != nil,
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            let pieces = folder.lastPathComponent.split(separator: "-", maxSplits: 1)
            guard pieces.count == 2, let pid = Int32(pieces[0]), pid > 0,
                  UUID(uuidString: String(pieces[1])) != nil,
                  kill(pid, 0) != 0, errno == ESRCH else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
