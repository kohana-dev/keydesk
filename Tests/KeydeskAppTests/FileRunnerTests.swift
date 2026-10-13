import Testing
import Foundation
import Darwin
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized)
struct FileRunnerTests {
    @Test func approvedFilePathContainsOriginalBytesThenDisappearsForPipeAndTTY() throws {
        for interactive in [false, true] {
            let (channel, client) = try RunnerTests().sockets(); defer { close(client) }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: output) }
            let file = try SecretFile(name: "fixture.p12", data: Data([0,255,13,10,10]))
            let program = "import os,pathlib; p=pathlib.Path(os.environ['FILE']); pathlib.Path(\"\(output.path)\").write_text(str(p)); print('MATCH='+str(p.read_bytes()==bytes([0,255,13,10,10]))); print('EXTRA='+str('UNSELECTED' in os.environ))"
            let request = CLIRequest(project: "fixture", environment: .development, command: ["/usr/bin/python3","-c",program], directory: "/tmp", stdinKey: nil, interactive: interactive, fileVariables: ["FILE"])
            let running = try CommandRunner.start(request, secrets: [:], channel: channel, files: ["FILE":file,"UNSELECTED":file], completion: {})
            defer { running.terminate(); channel.finish() }
            var bytes = Data(), exit: Int32?
            while let line = try SocketTransport.readLine(from: client) {
                let event = try JSONDecoder().decode(CLIEvent.self, from: line)
                if let data = event.data { bytes += data }
                if event.kind == "exit" { exit = event.exitCode; break }
            }
            #expect(exit == 0)
            let text = String(decoding: bytes, as: UTF8.self)
            #expect(text.contains("MATCH=True") && text.contains("EXTRA=False"))
            let path = try String(contentsOf: output, encoding: .utf8)
            #expect(!FileManager.default.fileExists(atPath: path))
        }
    }
    @Test func terminationRemovesFileImmediately() throws {
        let (channel, client) = try RunnerTests().sockets(); defer { close(client) }
        let file = try SecretFile(name: "fixture.pem", data: Data("FAKE_FILE_SECRET".utf8))
        let request = CLIRequest(project: "fixture", environment: .development, command: ["/bin/sh","-c","printf '%s\\n' \"$FILE\"; exec sleep 30"], directory: "/tmp", stdinKey: nil, fileVariables: ["FILE"])
        let running = try CommandRunner.start(request, secrets: [:], channel: channel, files: ["FILE":file], completion: {})
        defer { running.terminate(); channel.finish() }
        var path: String?
        while let line = try SocketTransport.readLine(from: client) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            if let data = event.data { path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines); break }
        }
        let actual = try #require(path)
        #expect(FileManager.default.fileExists(atPath: actual))
        #expect(running.isRunning)
        running.terminate()
        #expect(!FileManager.default.fileExists(atPath: actual))
    }
    @MainActor @Test func lockedFileDepositMergesAndBacksUpWithoutReadingValue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = root.appendingPathComponent("backup")
        let model = VaultModel(directory: root.appendingPathComponent("vault"), defaultBackupDirectory: backup, keys: MemoryKeyStore(), serve: false, observeSystemEvents: false)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true); model.lock()
        let file = try SecretFile(name: "key.p12", data: Data([0,255,13,10]))
        #expect(try model.deposit(SecretDeposit(project: "fixture", environment: .development, variable: "FILE", file: file)).hasPrefix("queued"))
        await model.unlock()
        #expect(model.snapshot?.credentials.first?.currentFile == file)
        #expect(!model.hasUnbackedChanges)
        #expect(try model.store.read().header.format == 2)
    }
}
