import Testing
import Foundation
import AppKit
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized) @MainActor
struct ProjectImageTests {
    @Test func imageIsNormalizedAndRejectsNonImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 768, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let url = root.appendingPathComponent("image.png")
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        let normalized = try ProjectImage.load(url)
        #expect(ProjectImage.valid(normalized))
        let decoded = try #require(NSBitmapImageRep(data: normalized))
        #expect(decoded.pixelsWide == 256 && decoded.pixelsHigh == 192)
        let invalid = root.appendingPathComponent("not-image.png")
        try Data("NOT_AN_IMAGE".utf8).write(to: invalid)
        #expect(throws: (any Error).self) { try ProjectImage.load(invalid) }
        #expect(!ProjectImage.valid(Data(repeating: 0, count: 512 * 1024 + 1)))
    }
    @Test func legacyProjectsDecodeAndImageSurvivesEncryptedReopen() async throws {
        let id = UUID()
        let legacy = Data("{\"id\":\"\(id)\",\"name\":\"legacy\",\"colorIndex\":0}".utf8)
        #expect(try JSONDecoder().decode(Project.self, from: legacy).iconPNG == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: MemoryKeyStore(), serve: false, observeSystemEvents: false)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun()
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try #require(rep.representation(using: .png, properties: [:]))
        try model.addProject("Image fixture", iconPNG: image)
        let project = try #require(model.snapshot?.projects.first)
        let backup = root.appendingPathComponent("image-backup.keydesk")
        let recovery = try #require(model.snapshot?.recoveryCode)
        try model.backup(to: backup)
        let envelope = try VaultFileStore.read(at: backup)
        let key = try VaultCrypto.recover(envelope, code: recovery)
        let restored = try VaultCrypto.open(envelope, key: key)
        #expect(restored.projects.first?.iconPNG == image)
        model.lock(); await model.unlock()
        #expect(model.snapshot?.projects.first?.iconPNG == image)
        try model.updateProject(project.id, name: "Renamed", iconPNG: nil)
        model.lock(); await model.unlock()
        #expect(model.snapshot?.projects.first?.id == project.id)
        #expect(model.snapshot?.projects.first?.name == "Renamed")
        #expect(model.snapshot?.projects.first?.iconPNG == nil)
    }
}
