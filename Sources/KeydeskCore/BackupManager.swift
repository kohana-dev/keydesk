import Foundation
import CryptoKit
import Darwin

public enum BackupManager {
    /// Most recent locally readable backup. Automatic discovery never downloads cloud placeholders.
    public static func latestBackup(in directory: URL) -> (url: URL, envelope: VaultEnvelope)? {
        latestBackup(in: directory, locallyAvailable: isLocallyAvailable, read: VaultFileStore.read)
    }

    static func latestBackup(in directory: URL, locallyAvailable: (URL) -> Bool,
                             read: (URL) throws -> VaultEnvelope) -> (url: URL, envelope: VaultEnvelope)? {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let candidates = urls.filter { $0.lastPathComponent.hasPrefix("Keydesk-") && $0.pathExtension == "keydesk" }
            .compactMap { url -> (URL, Date)? in
                guard locallyAvailable(url),
                      let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
                return (url, date)
            }.sorted { $0.1 > $1.1 }
        var latest: (url: URL, envelope: VaultEnvelope, date: Date)?
        for (url, date) in candidates {
            if let latest, date < latest.date { break }
            guard locallyAvailable(url), let envelope = try? read(url) else { continue }
            if latest == nil || envelope.header.revision > latest!.envelope.header.revision {
                latest = (url, envelope, date)
            }
        }
        return latest.map { ($0.url, $0.envelope) }
    }

    static func isLocallyAvailable(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_flags & UInt32(SF_DATALESS) == 0,
              let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) else { return false }
        return values.ubiquitousItemDownloadingStatus != .notDownloaded
    }
    public static func save(_ envelope: VaultEnvelope, key: SymmetricKey, directory: URL, now: Date = Date()) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw VaultError.invalidData }
        // Keep each successful snapshot immutable. UTC calendar avoids DST and locale collisions.
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("Keydesk-\(envelope.header.vaultID)-\(stamp)-\(UUID()).keydesk")
        try VaultFileStore.atomicWrite(JSONEncoder().encode(envelope), to: url)
        let written = try VaultFileStore.read(at: url)
        _ = try VaultCrypto.open(written, key: key)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        try prune(directory: directory, vaultID: envelope.header.vaultID, key: key, now: now)
        return url
    }
    public static func prune(directory: URL, vaultID: UUID, key: SymmetricKey, now: Date) throws {
        try prune(directory: directory, vaultID: vaultID, key: key, now: now,
                  locallyAvailable: isLocallyAvailable, read: VaultFileStore.read)
    }

    static func prune(directory: URL, vaultID: UUID, key: SymmetricKey, now: Date,
                      locallyAvailable: (URL) -> Bool, read: (URL) throws -> VaultEnvelope) throws {
        let prefix = "Keydesk-\(vaultID)-"
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let entries = try urls.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "keydesk" }.compactMap { url -> (URL, Date)? in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, locallyAvailable(url), let date = values.contentModificationDate, date <= now else { return nil }
            // Only prune authenticated-format backups belonging to this vault; unknown files stay untouched.
            guard let envelope = try? read(url), envelope.header.vaultID == vaultID,
                  (try? VaultCrypto.open(envelope, key: key)) != nil else { return nil }
            return (url, date)
        }.sorted { $0.1 > $1.1 }
        var keep = Set<URL>(), days = Set<Date>(), weeks = Set<Date>()
        for (url, date) in entries {
            let day = calendar.startOfDay(for: date)
            let week = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            if days.count < 7 && !days.contains(day) { days.insert(day); keep.insert(url) }
            if weeks.count < 4 && !weeks.contains(week) { weeks.insert(week); keep.insert(url) }
        }
        for (url, _) in entries where !keep.contains(url) && locallyAvailable(url) { try FileManager.default.removeItem(at: url) }
    }
}
