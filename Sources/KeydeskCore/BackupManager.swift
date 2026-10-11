import Foundation
import CryptoKit

public enum BackupManager {
    /// Most recent readable Keydesk backup in a folder, by save time then revision.
    public static func latestBackup(in directory: URL) -> (url: URL, envelope: VaultEnvelope)? {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return urls.filter { $0.lastPathComponent.hasPrefix("Keydesk-") && $0.pathExtension == "keydesk" }
            .compactMap { url -> (URL, VaultEnvelope, Date)? in
                guard let envelope = try? VaultFileStore.read(at: url),
                      let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
                return (url, envelope, date)
            }
            .max { ($0.2, $0.1.header.revision) < ($1.2, $1.1.header.revision) }
            .map { ($0.0, $0.1) }
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
        let prefix = "Keydesk-\(vaultID)-"
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let entries = try urls.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "keydesk" }.compactMap { url -> (URL, Date)? in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, let date = values.contentModificationDate, date <= now else { return nil }
            // Only prune authenticated-format backups belonging to this vault; unknown files stay untouched.
            guard let envelope = try? VaultFileStore.read(at: url), envelope.header.vaultID == vaultID,
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
        for (url, _) in entries where !keep.contains(url) { try FileManager.default.removeItem(at: url) }
    }
}
