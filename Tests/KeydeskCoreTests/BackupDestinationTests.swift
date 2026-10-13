import Testing
import Foundation
import CryptoKit
@testable import KeydeskCore

struct BackupDestinationTests {
    private let fixtureHome = URL(fileURLWithPath: "/FixtureHomes/backup-fixture", isDirectory: true)

    @Test func legacySettingsDecodeWithoutDestination() throws {
        let data = Data(#"{"directory":"/Fixture/backups","lastSuccess":1234,"bookmark":"AQID"}"#.utf8)
        let settings = try JSONDecoder().decode(BackupSettings.self, from: data)
        #expect(settings.directory == "/Fixture/backups")
        #expect(settings.lastSuccess == Date(timeIntervalSinceReferenceDate: 1234))
        #expect(settings.bookmark == Data([1, 2, 3]))
        #expect(settings.destination == nil)
        #expect(try JSONDecoder().decode(BackupSettings.self, from: Data("{}".utf8)).destination == nil)
    }

    @Test func selectedDestinationSurvivesSettingsRoundTrip() throws {
        for destination in BackupDestination.allCases {
            let original = BackupSettings(directory: "/Fixture/chosen-location", lastSuccess: Date(timeIntervalSinceReferenceDate: 5678), bookmark: Data([4, 5]), destination: destination)
            let restored = try JSONDecoder().decode(BackupSettings.self, from: JSONEncoder().encode(original))
            #expect(restored.directory == original.directory)
            #expect(restored.lastSuccess == original.lastSuccess)
            #expect(restored.bookmark == original.bookmark)
            #expect(restored.destination == destination)
        }
    }

    @Test func iCloudClassificationRequiresCompleteRootComponents() {
        for path in [
            "Library/Mobile Documents/com~apple~CloudDocs",
            "Library/Mobile Documents/com~apple~CloudDocs/Cellar",
            "Library/Mobile Documents/com~apple~CloudDocs/Cellar/../Backups"
        ] {
            #expect(BackupLocation.destination(of: fixtureHome.appendingPathComponent(path), homeDirectory: fixtureHome) == .iCloud)
        }
        for path in [
            "Library/Mobile Documents",
            "Library/Mobile Documents/com~apple~CloudDocs-other/Cellar",
            "Library/Mobile Documents/com~apple~CloudDocs/../LocalBackups"
        ] {
            #expect(BackupLocation.destination(of: fixtureHome.appendingPathComponent(path), homeDirectory: fixtureHome) == .folder)
        }
        let differentHome = URL(fileURLWithPath: "/FixtureHomes/backup-fixture-other/Library/Mobile Documents/com~apple~CloudDocs/Cellar")
        #expect(BackupLocation.destination(of: differentHome, homeDirectory: fixtureHome) == .folder)
    }

    @Test func googleClassificationRequiresFirstFileProviderAccountSegment() {
        for path in [
            "Library/CloudStorage/GoogleDrive-fixture",
            "Library/CloudStorage/GoogleDrive-fixture/My Drive/Cellar",
            "Library/CloudStorage/GoogleDrive-second-account/Shared drives/Cellar"
        ] {
            #expect(BackupLocation.destination(of: fixtureHome.appendingPathComponent(path), homeDirectory: fixtureHome) == .googleDrive)
        }
        for path in [
            "Library/CloudStorage",
            "Library/CloudStorage/GoogleDrive-",
            "Library/CloudStorage/GoogleDrive/Cellar",
            "Library/CloudStorage/GoogleDriveOther-fixture/Cellar",
            "Library/CloudStorage/archive/GoogleDrive-fixture/Cellar",
            "Library/CloudStorage-other/GoogleDrive-fixture/Cellar",
            "Library/CloudStorage/GoogleDrive-fixture/../../LocalBackups",
            "Documents/GoogleDrive-fixture/Cellar"
        ] {
            #expect(BackupLocation.destination(of: fixtureHome.appendingPathComponent(path), homeDirectory: fixtureHome) == .folder)
        }
        let differentHome = URL(fileURLWithPath: "/FixtureHomes/backup-fixture-other/Library/CloudStorage/GoogleDrive-fixture/Cellar")
        #expect(BackupLocation.destination(of: differentHome, homeDirectory: fixtureHome) == .folder)
    }

    @Test func providerClassificationUsesResolvedSymlinkLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-provider-symlinks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let drive = home.appendingPathComponent("Library/CloudStorage/GoogleDrive-fixture")
        let ordinary = root.appendingPathComponent("ordinary")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ordinary, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("drive-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: drive)
        #expect(BackupLocation.destination(of: alias, homeDirectory: home) == .googleDrive)
        let outsideAlias = drive.appendingPathComponent("outside-alias")
        try FileManager.default.createSymbolicLink(at: outsideAlias, withDestinationURL: ordinary)
        #expect(BackupLocation.destination(of: outsideAlias, homeDirectory: home) == .folder)
        let homeAlias = root.appendingPathComponent("home-alias")
        try FileManager.default.createSymbolicLink(at: homeAlias, withDestinationURL: home)
        #expect(BackupLocation.destination(of: drive, homeDirectory: homeAlias) == .googleDrive)
    }

    @Test func googleFolderBackupRemainsEncryptedAndIndependentlyRecoverable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-google-backup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Library/CloudStorage/GoogleDrive-fixture/My Drive/Cellar")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var snapshot = VaultSnapshot()
        snapshot.credentials = [Credential(name: "Fixture", value: "GOOGLE_BACKUP_SECRET_FIXTURE", provider: "Fixture")]
        snapshot.backup = BackupSettings(directory: directory.path, destination: .googleDrive)
        let key = SymmetricKey(size: .bits256), recoveryKey = SymmetricKey(size: .bits256), header = VaultHeader()
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: recoveryKey, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let envelope = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key)
        let url = try BackupManager.save(envelope, key: key, directory: directory)
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("GOOGLE_BACKUP_SECRET_FIXTURE"))
        let backup = try VaultFileStore.read(at: url)
        let recoveredKey = try VaultCrypto.recover(backup, code: RecoveryCode.encode(recoveryKey))
        let restored = try VaultCrypto.open(backup, key: recoveredKey)
        #expect(restored.credentials.first?.currentValue == "GOOGLE_BACKUP_SECRET_FIXTURE")
        #expect(restored.backup?.destination == .googleDrive)
        #expect(BackupManager.latestBackup(in: directory)?.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
        // Saving to a Drive-shaped local folder cannot prove completion of Google's cloud sync.
        #expect(BackupLocation.cloudUpload(of: url) == .notCloud)
    }
}
