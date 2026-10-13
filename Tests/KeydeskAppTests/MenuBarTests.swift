import Foundation
import AppKit
import Testing
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized) @MainActor
struct MenuBarTests {
    @Test func lockingClosesQuickAddAndDoesNotClaimBackupSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("menu-test-\(UUID())")
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: MemoryKeyStore(), serve: false, observeSystemEvents: false)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true)
        #expect(!model.hasPendingApproval)
        #expect(model.menuBarBackupStatus == L10n.tr("백업 폴더 없음", "No backup folder"))
        model.showQuickAdd = true
        model.lock()
        #expect(!model.showQuickAdd)
        #expect(model.menuBarBackupStatus == L10n.tr("백업 상태는 금고를 연 뒤 확인합니다", "Open the vault to check backup status"))
        #expect(!model.menuBarBackupStatus.contains(L10n.tr("백업됨", "Backed up")))
        await model.unlock()
        #expect(model.menuBarBackupStatus == L10n.tr("백업 폴더 없음", "No backup folder"))
    }
    @Test func ribbonIconIsTemplateAndRendersAtMenuBarSize() throws {
        let image = MenuBarIcon.image
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 20))
        let data = try #require(image.tiffRepresentation)
        let pixels = try #require(NSBitmapImageRep(data: data))
        #expect((0..<pixels.pixelsHigh).contains { y in
            (0..<pixels.pixelsWide).contains { x in (pixels.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        })
    }
}
