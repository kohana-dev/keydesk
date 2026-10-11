import Foundation
import Darwin

public enum CLIInstaller {
    @discardableResult public static func install(executable: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let source = executable.standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: source.path) else { throw VaultError.invalidData }
        let directory = home.appendingPathComponent(".local/bin"), target = home.appendingPathComponent(".local/bin/keydesk")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: target.path) {
            if target.resolvingSymlinksInPath() == source { return target }
            // Relink only a symbolic link to the exact same executable bytes. Never
            // overwrite a regular file, broken link, or another program/version.
            guard attributes[.type] as? FileAttributeType == .typeSymbolicLink,
                  FileManager.default.isExecutableFile(atPath: target.path),
                  let oldSize = try? FileManager.default.attributesOfItem(atPath: target.resolvingSymlinksInPath().path)[.size] as? NSNumber,
                  let newSize = try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber,
                  oldSize == newSize, newSize.intValue <= 16 * 1024 * 1024,
                  try Data(contentsOf: target) == Data(contentsOf: source) else { throw VaultError.accessDenied }
            let temporary = directory.appendingPathComponent(".keydesk-install-\(UUID())")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.createSymbolicLink(at: temporary, withDestinationURL: source)
            guard rename(temporary.path, target.path) == 0 else { throw VaultError.accessDenied }
        } else { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source) }
        return target
    }
}
