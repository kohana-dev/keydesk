import Testing
import Foundation
import Darwin
import KeydeskCore
@testable import KeydeskApp

private final class SelectionReadGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let resume = DispatchSemaphore(value: 0)
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    func release() { resume.signal() }
    func read(_ url: URL) throws -> String {
        #expect(!Thread.isMainThread, "Selected cloud files must be read off the UI thread")
        entered.signal()
        guard resume.wait(timeout: .now() + 5) == .success else { throw VaultError.accessDenied }
        return url.lastPathComponent
    }
}

@Suite(.serialized) @MainActor
struct FileSelectionLoaderTests {
    @Test func delayedReadLeavesMainActorResponsive() async throws {
        let gate = SelectionReadGate()
        let loader = FileSelectionLoader<String>(read: gate.read)
        let result = loader.load(URL(fileURLWithPath: "/synthetic/slow-file"))
        defer { gate.release() }
        try #require(try await BlockingRunnerTestSupport.run { gate.waitUntilEntered() })
        #expect(loader.isLoading && !loader.failed)
        gate.release()
        #expect(await result.value == "slow-file")
        #expect(!loader.isLoading && !loader.failed)
    }

    @Test func cancellingSelectionRejectsLateCompletion() async throws {
        let gate = SelectionReadGate()
        let loader = FileSelectionLoader<String>(read: gate.read)
        var published = false
        let result = loader.load(URL(fileURLWithPath: "/synthetic/old-file")) { _ in published = true }
        defer { gate.release() }
        try #require(try await BlockingRunnerTestSupport.run { gate.waitUntilEntered() })
        loader.cancel()
        #expect(!loader.isLoading && !loader.failed)
        gate.release()
        #expect(await result.value == nil)
        #expect(!published && !loader.isLoading && !loader.failed)
    }

    @Test func replacementSelectionWinsOverOlderCompletion() async throws {
        let gate = SelectionReadGate()
        let loader = FileSelectionLoader<String> { url in
            if url.lastPathComponent == "old" { return try gate.read(url) }
            return url.lastPathComponent
        }
        var published: String?
        let old = loader.load(URL(fileURLWithPath: "/synthetic/old")) { published = $0 }
        defer { gate.release() }
        try #require(try await BlockingRunnerTestSupport.run { gate.waitUntilEntered() })
        let replacement = loader.load(URL(fileURLWithPath: "/synthetic/new")) { published = $0 }
        #expect(await replacement.value == "new")
        gate.release()
        #expect(await old.value == nil)
        #expect(published == "new" && !loader.isLoading && !loader.failed)
    }

    @Test func errorsRemainRecoverableAndDoNotReturnFileContent() async {
        let loader = FileSelectionLoader<String> { url in
            if url.lastPathComponent == "bad" { throw VaultError.invalidData }
            return "synthetic-value"
        }
        #expect(await loader.load(URL(fileURLWithPath: "/synthetic/bad")).value == nil)
        #expect(loader.failed && !loader.isLoading)
        #expect(await loader.load(URL(fileURLWithPath: "/synthetic/good")).value == "synthetic-value")
        #expect(!loader.failed && !loader.isLoading)
    }

    @Test func dotenvReaderAcceptsHiddenUTF8FileAndRejectsPipesLinksAndOversizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-file-input-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(".env")
        try Data("SYNTHETIC_TOKEN=fictional-value\n".utf8).write(to: file)
        let loaded = try DotenvFileSelection.read(at: file)
        #expect(loaded.name == ".env" && loaded.rows.count == 1 && loaded.rows[0].name == "SYNTHETIC_TOKEN")
        let pipe = root.appendingPathComponent("pipe.env")
        try #require(mkfifo(pipe.path, 0o600) == 0)
        #expect(throws: (any Error).self) { try DotenvFileSelection.read(at: pipe) }
        let link = root.appendingPathComponent("link.env")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: (any Error).self) { try DotenvFileSelection.read(at: link) }
        try Data(repeating: 65, count: SecretFile.maximumBytes + 1).write(to: file)
        #expect(throws: (any Error).self) { try DotenvFileSelection.read(at: file) }
        try Data([0xff, 0xfe]).write(to: file)
        #expect(throws: (any Error).self) { try DotenvFileSelection.read(at: file) }
    }
}
