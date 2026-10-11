import Foundation
import Testing
import CryptoKit
import Darwin
@testable import KeydeskCore

struct SecretFileTests {
    @Test func binaryFileEncryptsAndRecoversExactlyWithoutStringConversion() throws {
        let bytes = Data([0, 255, 13, 10, 128]) + Data("FAKE_PRIVATE_FILE_SENTINEL\r\n\n".utf8)
        let file = try SecretFile(name: "키 파일.p12", data: bytes)
        let deposit = try SecretDeposit(project: "file-fixture", environment: .development, variable: "APPLE_PRIVATE_KEY_PATH", file: file)
        let snapshot = try deposit.adding(to: VaultSnapshot())
        let key = SymmetricKey(size: .bits256), recovery = SymmetricKey(size: .bits256), header = VaultHeader()
        let wrap = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let sealed = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrap, key: key)
        #expect(sealed.header.format == 2)
        #expect(sealed.ciphertext.range(of: Data("FAKE_PRIVATE_FILE_SENTINEL".utf8)) == nil)
        let reopened = try VaultCrypto.open(sealed, key: VaultCrypto.recover(sealed, code: RecoveryCode.encode(recovery)))
        #expect(reopened.credentials.first?.currentFile == file)
        #expect(reopened.credentials.first?.currentValue == nil)
        #expect(try reopened.environment(projectID: reopened.projects[0].id, environment: .development).isEmpty)
        #expect(try reopened.files(projectID: reopened.projects[0].id, environment: .development)["APPLE_PRIVATE_KEY_PATH"] == file)
    }
    @Test func oldStringVersionWithoutFileFieldStillDecodes() throws {
        let old = SecretVersion(value: "fake-text")
        let decoded = try JSONDecoder().decode(SecretVersion.self, from: JSONEncoder().encode(old))
        #expect(decoded.file == nil && decoded.value == old.value)
    }
    @Test func lockedDepositPreservesBinaryAndRejectsTampering() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let file = try SecretFile(name: "service-account.json", data: Data(repeating: 255, count: SecretFile.maximumBytes))
        let deposit = try SecretDeposit(project: "fixture", environment: .development, variable: "GOOGLE_APPLICATION_CREDENTIALS", file: file)
        var sealed = try SealedDeposit.seal(deposit, publicKey: key.publicKey.rawRepresentation)
        #expect(sealed.version == 2)
        #expect(try sealed.open(privateKey: key.rawRepresentation).file == file)
        sealed.ciphertext[0] ^= 1
        #expect(throws: (any Error).self) { try sealed.open(privateKey: key.rawRepresentation) }
    }
    @Test func sourceReaderRejectsLinksDirectoriesAndOversizeAndKeepsTrailingBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("fixture.pem"), bytes = Data([0,255,13,10,10])
        try bytes.write(to: url)
        #expect(try SecretFile.read(at: url).data == bytes)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        #expect(throws: (any Error).self) { try SecretFile.read(at: link) }
        #expect(throws: (any Error).self) { try SecretFile.read(at: root) }
        try Data(repeating: 0, count: SecretFile.maximumBytes + 1).write(to: url)
        #expect(throws: (any Error).self) { try SecretFile.read(at: url) }
        #expect(throws: (any Error).self) { try SecretFile(name: "../escape", data: bytes) }
    }
    @Test func temporaryFilesArePrivateSeparateAndDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try SecretFile(name: "same.p8", data: Data([0,255,13,10]))
        let run = try TemporarySecretFiles(files: ["FIRST_FILE":file,"SECOND_FILE":file], root: root)
        #expect(run.paths["FIRST_FILE"] != run.paths["SECOND_FILE"])
        for path in run.paths.values {
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == file.data)
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: run.directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        run.cleanup(); run.cleanup()
        #expect(!FileManager.default.fileExists(atPath: run.directory.path))
    }
    @Test func fileSelectionIsExplicitAndDoesNotAllowExecutionControlOrCollisions() throws {
        let file = try SecretFile(name: "a.json", data: Data())
        let request = CLIRequest(project: "fixture", environment: .development, command: ["true"], directory: "/tmp", stdinKey: nil, fileVariables: ["FILE"])
        #expect(try request.selectedSecrets(from: ["OTHER":"fake"]).isEmpty)
        #expect(try request.selectedFiles(from: ["FILE":file,"UNSELECTED":file]).count == 1)
        for names in [["HOME"],["FILE","FILE"],["MISSING"]] {
            let invalid = CLIRequest(project: "fixture", environment: .development, command: ["true"], directory: "/tmp", stdinKey: nil, fileVariables: names)
            #expect(throws: (any Error).self) { try invalid.selectedFiles(from: ["FILE":file,"HOME":file]) }
        }
        let overlap = CLIRequest(project: "fixture", environment: .development, command: ["true"], directory: "/tmp", stdinKey: nil, variables: ["FILE"], fileVariables: ["FILE"])
        #expect(throws: (any Error).self) { try overlap.selectedFiles(from: ["FILE":file]) }
    }
    @Test func binaryOutputRedactionAcrossChunks() {
        let bytes = Data([0,255,128,10])
        var redactor = StreamingRedactor(bytes: [bytes])
        let output = redactor.push(Data([1,0,255])) + redactor.push(Data([128,10,2]), final: true)
        #expect(output == Data([1]) + Data("[REDACTED]".utf8) + Data([2]))
    }

    @Test func maximumFileCrossesSocketWithoutConsumingNextMessage() throws {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let reader = fds[0], writer = fds[1]
        var noSig: Int32 = 1
        for fd in fds { setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout<Int32>.size)) }
        defer { close(reader) }
        let file = try SecretFile(name: "max.p12", data: Data(repeating: 255, count: SecretFile.maximumBytes))
        let request = ServiceRequest(kind: "store-file", project: "fixture", environment: .development, variable: "FILE", file: file)
        DispatchQueue.global().async {
            defer { close(writer) }
            try? SocketTransport.send(request, to: writer)
            try? SocketTransport.send(["next":true], to: writer)
        }
        let line = try #require(try SocketTransport.readLine(from: reader, maximum: 2_097_152, deadlineSeconds: 5))
        #expect(try JSONDecoder().decode(ServiceRequest.self, from: line).file == file)
        let next = try #require(try SocketTransport.readLine(from: reader, deadlineSeconds: 5))
        #expect(try JSONDecoder().decode([String:Bool].self, from: next)["next"] == true)
    }
    @Test func orphanCleanupLeavesLiveRunsAndUnrelatedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let abandoned = root.appendingPathComponent("2147483647-\(UUID())")
        let live = root.appendingPathComponent("\(getpid())-\(UUID())")
        let unrelated = root.appendingPathComponent("unrelated")
        for url in [abandoned, live, unrelated] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        TemporarySecretFiles.cleanupOrphans(root: root)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(FileManager.default.fileExists(atPath: live.path) && FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func pipeLineTransportStillSupportsMCPStdinAndMultipleMessages() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data("first\nsecond\n".utf8))
        try pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        #expect(try SocketTransport.readLine(from: pipe.fileHandleForReading.fileDescriptor) == Data("first".utf8))
        #expect(try SocketTransport.readLine(from: pipe.fileHandleForReading.fileDescriptor) == Data("second".utf8))
        #expect(try SocketTransport.readLine(from: pipe.fileHandleForReading.fileDescriptor) == nil)
    }
}
