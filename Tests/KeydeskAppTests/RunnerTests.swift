import Testing
import Foundation
import Darwin
import AppKit
import CryptoKit
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized)
struct RunnerTests {
    func sockets() throws -> (CLIChannel, Int32) {
        var fds = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw VaultError.invalidData }
        for fd in fds {
            var timeout = timeval(tv_sec: 5, tv_usec: 0), noSig: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout<Int32>.size))
        }
        return (CLIChannel(fd: fds[0]), fds[1])
    }
    @Test func promptAndInputAreDeliveredBeforeExitForPipeAndPTY() throws {
        for interactive in [false, true] {
            let (channel, client) = try sockets(); defer { close(client) }
            let request = CLIRequest(project: "fixture", environment: .development, command: ["/bin/sh", "-c", "printf 'prompt: '; read value; printf '%s\\n' \"$value\"; printf '%s\\n' \"$KEY\"; exit 7"], directory: "/tmp", stdinKey: nil, variables: ["KEY"], interactive: interactive)
            let running = try CommandRunner.start(request, secrets: ["KEY": "SENTINEL_SECRET"], channel: channel, completion: {})
            defer { running.terminate(); channel.finish() }
            let first = try JSONDecoder().decode(CLIEvent.self, from: #require(try SocketTransport.readLine(from: client)))
            #expect(first.kind == "started")
            let prompt = try JSONDecoder().decode(CLIEvent.self, from: #require(try SocketTransport.readLine(from: client)))
            #expect(String(decoding: prompt.data ?? Data(), as: UTF8.self).contains("prompt: "))
            try SocketTransport.send(CLIInput(kind: "stdin", data: Data("hello\n".utf8)), to: client)
            var output = Data(), exitCode: Int32?
            while let line = try SocketTransport.readLine(from: client) {
                let event = try JSONDecoder().decode(CLIEvent.self, from: line)
                if let data = event.data { output += data }
                if event.kind == "exit" { exitCode = event.exitCode; break }
            }
            #expect(exitCode == 7)
            let text = String(decoding: output, as: UTF8.self)
            #expect(text.contains("hello") && text.contains("[REDACTED]"))
            #expect(!text.contains("SENTINEL_SECRET"))
        }
    }
    @Test @MainActor func demoBrokerDeniesUnapprovedRequestsAndRevokesOnLock() async throws {
        let model = VaultModel(demo: true)
        defer { model.shutdown() }
        let project = try #require(model.snapshot?.projects.first)
        let (channel, client) = try sockets(); defer { close(client) }
        model.receiveBroker(BrokerRequest(session: "fixture", project: project.id.uuidString, environment: .development, tool: "list_connections", arguments: [:]), channel: channel)
        let denied = try JSONDecoder().decode(JSONValue.self, from: #require(try SocketTransport.readLine(from: client)))
        #expect(denied["error"] != nil)
        let (grantChannel, grantClient) = try sockets(); defer { close(grantClient) }
        model.receiveBroker(BrokerRequest(session: "fixture", project: project.id.uuidString, environment: .development, tool: "request_access", arguments: ["operation": .string("metadata"), "maximumCalls": .number(1)]), channel: grantChannel)
        #expect(model.brokerApproval != nil)
        await model.acceptBroker()
        #expect(model.grants.count == 1)
        let (listChannel, listClient) = try sockets(); defer { close(listClient) }
        model.receiveBroker(BrokerRequest(session: "fixture", project: project.id.uuidString, environment: .development, tool: "list_connections", arguments: [:]), channel: listChannel)
        let result = try JSONDecoder().decode(JSONValue.self, from: #require(try SocketTransport.readLine(from: listClient)))
        guard case .array(let variables) = result["result"]?["variables"] else { Issue.record("missing variables"); return }
        #expect(variables.count == 4 && variables.allSatisfy { $0["variable"]?.string != nil })
        #expect(!String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains("DEMO_ONLY_"))
        let (renewChannel, renewClient) = try sockets(); defer { close(renewClient) }
        model.receiveBroker(BrokerRequest(session: "fixture", project: project.id.uuidString, environment: .development, tool: "request_access", arguments: ["operation": .string("metadata"), "maximumCalls": .number(1)]), channel: renewChannel)
        await model.acceptBroker()
        let (renewedList, renewedReader) = try sockets(); defer { close(renewedReader) }
        model.receiveBroker(BrokerRequest(session: "fixture", project: project.id.uuidString, environment: .development, tool: "list_connections", arguments: [:]), channel: renewedList)
        let renewed = try JSONDecoder().decode(JSONValue.self, from: #require(try SocketTransport.readLine(from: renewedReader)))
        #expect(renewed["result"]?["variables"] != nil)
        model.lock()
        #expect(model.grants.isEmpty && model.snapshot == nil)
    }
    @Test @MainActor func clipboardOwnershipDoesNotEraseOtherCopies() {
        let board = NSPasteboard(name: .init("Keydesk-QA-\(UUID())"))
        let service = ClipboardService(board: board)
        service.copy("DISPOSABLE_SENTINEL", secret: true)
        #expect(board.string(forType: .string) == "DISPOSABLE_SENTINEL")
        #expect(board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
        service.clearOwned(); #expect(board.string(forType: .string) == nil)
        service.copy("DISPOSABLE_SENTINEL", secret: true)
        board.clearContents(); board.setString("new-user-copy", forType: .string)
        service.clearOwned(); #expect(board.string(forType: .string) == "new-user-copy")
        board.clearContents()
    }
    @Test @MainActor func idleAndSimulatedSleepEventsClearSession() async throws {
        let model = VaultModel(demo: true); defer { model.shutdown() }
        model.autoLockMinutes = 5
        model.lockIfIdle(now: Date().addingTimeInterval(299)); #expect(model.snapshot != nil)
        model.lockIfIdle(now: Date().addingTimeInterval(301)); #expect(model.snapshot == nil)
        await model.unlock(); #expect(model.snapshot != nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.snapshot == nil)
        await model.unlock()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.snapshot == nil)
    }
    @Test @MainActor func everyChangeReachesBackupFolderByLockTime() async throws {
        let model = VaultModel(demo: true); defer { model.shutdown() }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-app-backup-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try model.configureBackup(directory: root)
        #expect(model.lastBackupAt != nil && !model.hasUnbackedChanges)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
        // Several edits on the same day: the old once-a-day rule left these out of every backup.
        try model.addProject("second"); try model.addProject("third")
        #expect(model.hasUnbackedChanges)
        let revision = try #require(model.snapshot?.revision)
        model.lock()
        let newest = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).map { try VaultFileStore.read(at: $0).header.revision }.max()
        #expect(newest == revision)
    }
    @Test @MainActor func demoRotationBackupIsRecoverable() async throws {
        let model = VaultModel(demo: true); defer { model.shutdown() }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-app-rotation-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let code = RecoveryCode.encode(SymmetricKey(size: .bits256))
        try await model.rotateVaultKeys(code: code, dataKey: true, backupDirectory: root)
        let output = try #require(BackupManager.latestBackup(in: root)).url
        let envelope = try VaultFileStore.read(at: output)
        let snapshot = try VaultCrypto.open(envelope, key: VaultCrypto.recover(envelope, code: code))
        #expect(snapshot.credentials.count == 4)
        #expect(model.snapshot?.revision == snapshot.revision)
        #expect(!String(decoding: try Data(contentsOf: output), as: UTF8.self).contains("DEMO_ONLY_"))
    }

    @Test @MainActor func pendingApprovalIsInvalidatedByVaultMutation() throws {
        let model = VaultModel(demo: true); defer { model.shutdown() }
        let project = try #require(model.snapshot?.projects.first)
        let (channel, client) = try sockets(); defer { close(client) }
        model.receiveBroker(BrokerRequest(session: "fixture", project: project.id.uuidString, environment: .development, tool: "request_access", arguments: ["operation": .string("metadata")]), channel: channel)
        #expect(model.brokerApproval != nil)
        try model.addProject("another project")
        #expect(model.brokerApproval == nil && model.grants.isEmpty)
    }
    @Test @MainActor func disconnectedAndMalformedApprovalsFailClosed() async throws {
        let model = VaultModel(demo: true); defer { model.shutdown() }
        let project = try #require(model.snapshot?.projects.first)
        let (channel, client) = try sockets()
        model.receiveBroker(BrokerRequest(session: "fixture", project: project.id.uuidString, environment: .development, tool: "request_access", arguments: ["operation": .string("metadata")]), channel: channel)
        close(client); await model.acceptBroker(); #expect(model.grants.isEmpty)
        let (malformed, reader) = try sockets(); defer { close(reader) }
        model.receiveBroker(BrokerRequest(session: "fixture", project: project.id.uuidString, environment: .development, tool: "request_access", arguments: ["operation": .string("metadata"), "duration": .string("600")]), channel: malformed)
        #expect(model.brokerApproval == nil)
        let response = try JSONDecoder().decode(JSONValue.self, from: #require(try SocketTransport.readLine(from: reader)))
        #expect(response["error"] != nil)
    }

    @Test func stdinSecretIsNotAlsoInjectedIntoEnvironment() throws {
        let (channel, client) = try sockets(); defer { close(client) }
        let request = CLIRequest(project: "fixture", environment: .development, command: ["/bin/sh", "-c", "if [ -n \"${TOKEN+x}\" ]; then exit 91; fi; read value; printf '%s\\n' \"$value\"; printf '%s\\n' \"$OTHER\""], directory: "/tmp", stdinKey: "TOKEN", variables: ["TOKEN", "OTHER"])
        let running = try CommandRunner.start(request, secrets: ["TOKEN": "FAKE_STDIN_SECRET", "OTHER": "FAKE_ENV_SECRET"], channel: channel, completion: {})
        defer { running.terminate(); channel.finish() }
        var output = Data(), exitCode: Int32?
        while let line = try SocketTransport.readLine(from: client) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            if let data = event.data { output += data }
            if event.kind == "exit" { exitCode = event.exitCode; break }
        }
        #expect(exitCode == 0)
        #expect(String(decoding: output, as: UTF8.self).components(separatedBy: "[REDACTED]").count == 3)
        #expect(!String(decoding: output, as: UTF8.self).contains("FAKE_"))
    }

    @Test func changedApprovedExecutableDoesNotStart() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-approval-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("command"), marker = root.appendingPathComponent("executed")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable); chmod(executable.path, 0o700)
        let request = CLIRequest(project: "fixture", environment: .development, command: [executable.path], directory: root.path, stdinKey: nil, variables: ["KEY"])
        let (channel, client) = try sockets(); defer { close(client); channel.finish() }
        let approval = try CLIApproval(request: request, channel: channel)
        try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: executable)
        #expect(throws: (any Error).self) { try CommandRunner.start(request, secrets: ["KEY": "FAKE_SECRET"], channel: channel, approvedExecutable: approval.executable, completion: {}) }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func socketPeerMustMatchExpectedSignedExecutable() throws {
        let process = Process(), input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.standardInput = input; process.standardOutput = FileHandle.nullDevice
        try process.run()
        defer { try? input.fileHandleForWriting.close(); if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let cat = try PeerVerifier.requirement(for: URL(fileURLWithPath: "/bin/cat"))
        let shell = try PeerVerifier.requirement(for: URL(fileURLWithPath: "/bin/sh"))
        #expect(PeerVerifier.matches(pid: process.processIdentifier, requirement: cat))
        #expect(!PeerVerifier.matches(pid: process.processIdentifier, requirement: shell))
        #expect(!PeerVerifier.matches(pid: -1, requirement: cat))
    }

    @Test func secureSocketRejectsUntrustedPeerBeforeDecodingRequest() throws {
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("kdp-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("cli.sock").path
        let server = CLIServer(path: path, trustedHelper: URL(fileURLWithPath: "/bin/cat"))
        try server.start(deliver: { _ in }, broker: { _, _ in })
        defer { server.stop() }
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(client) }
        var address = try SocketTransport.address(path), timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let connected = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        #expect(connected == 0)
        // This test process shares the uid but has a different signing identity than cat.
        #expect(try SocketTransport.readLine(from: client) == nil)
    }

}
