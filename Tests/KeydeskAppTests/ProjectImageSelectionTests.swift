import Testing
import Foundation
import AppKit
@testable import KeydeskApp

@Suite(.serialized) @MainActor
struct ProjectImageSelectionTests {
    @Test func selectedImageIsDecodedOnWorkerAndPublishesNormalizedThumbnail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-image-selection-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 320,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let source = root.appendingPathComponent("synthetic.png")
        try #require(rep.representation(using: .png, properties: [:])).write(to: source)
        let loader = FileSelectionLoader<Data> { url in
            #expect(!Thread.isMainThread)
            return try ProjectImage.load(url)
        }
        var displayed: Data?
        let task = loader.load(source) { displayed = $0 }
        #expect(loader.isLoading)
        let normalized = try #require(await task.value)
        #expect(displayed == normalized && ProjectImage.valid(normalized))
        let thumbnail = try #require(NSBitmapImageRep(data: normalized))
        #expect(thumbnail.pixelsWide == 256 && thumbnail.pixelsHigh == 128)
        #expect(!loader.isLoading && !loader.failed)
    }

    @Test func cancellingImageBeforeWorkerCompletesKeepsPreviewUnchanged() async throws {
        let started = ImageReadGate()
        let original = Data("synthetic-existing-preview".utf8)
        var displayed = original
        let loader = FileSelectionLoader<Data>(read: started.read)
        let task = loader.load(URL(fileURLWithPath: "/synthetic/pending.png")) { displayed = $0 }
        defer { started.release() }
        try #require(try await BlockingRunnerTestSupport.run { started.waitUntilEntered() })
        loader.cancel() // Selecting another image, removing it, or closing the sheet invalidates this read.
        started.release()
        #expect(await task.value == nil)
        #expect(displayed == original && !loader.isLoading && !loader.failed)
    }
}

private final class ImageReadGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let resume = DispatchSemaphore(value: 0)
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    func release() { resume.signal() }
    func read(_ url: URL) throws -> Data {
        #expect(!Thread.isMainThread)
        entered.signal()
        guard resume.wait(timeout: .now() + 5) == .success else { throw ProjectImageError.invalid }
        return Data("synthetic-completed-image".utf8)
    }
}
