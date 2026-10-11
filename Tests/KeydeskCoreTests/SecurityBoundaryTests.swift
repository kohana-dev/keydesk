import Testing
import Foundation
import Darwin
@testable import KeydeskCore

struct SecurityBoundaryTests {
    @Test func secretSelectionFailsClosedAndNeverSelectsWholeEnvironment() throws {
        let values = ["A": "sentinel-a", "B": "sentinel-b", "PATH": "/malicious"]
        func request(_ variables: [String]? = nil, stdin: String? = nil) -> CLIRequest {
            CLIRequest(project: "fixture", environment: .development, command: ["/bin/echo"], directory: "/tmp", stdinKey: stdin, variables: variables)
        }
        #expect(throws: (any Error).self) { try request().selectedSecrets(from: values) }
        #expect(try request(["A"]).selectedSecrets(from: values) == ["A": "sentinel-a"])
        #expect(try request(stdin: "B").selectedSecrets(from: values) == ["B": "sentinel-b"])
        for variables in [["missing"], ["A", "A"], ["PATH"]] {
            #expect(throws: (any Error).self) { try request(variables).selectedSecrets(from: values) }
        }
    }
    @Test func executableReplacementAndSymlinkRetargetingAreDetected() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-executable-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("command"), link = root.appendingPathComponent("alias")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file); chmod(file.path, 0o700)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let identity = try ExecutableIdentity.capture(command: link.path, directory: root.path)
        try identity.validate()
        #expect(identity.path == file.resolvingSymlinksInPath().path)
        try Data("#!/bin/sh\nexit 9\n".utf8).write(to: file)
        #expect(throws: (any Error).self) { try identity.validate() }
        #expect(throws: (any Error).self) { try ExecutableIdentity.capture(command: root.path, directory: root.path) }
    }
    @Test func vaultReaderRejectsSymlinksAndFIFOsWithoutBlocking() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-files-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file"), link = root.appendingPathComponent("link"), fifo = root.appendingPathComponent("fifo")
        try Data("{}".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(mkfifo(fifo.path, 0o600) == 0)
        for url in [root, link, fifo] { #expect(throws: (any Error).self) { try VaultFileStore.read(at: url) } }
    }
    @Test func privateDirectoryRepairsPermissionsAndRejectsSymlink() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-private-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        chmod(root.path, 0o777)
        try VaultFileStore.preparePrivateDirectory(root)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        #expect(throws: (any Error).self) { try VaultFileStore.preparePrivateDirectory(link) }
    }
    @Test func partialSocketRequestCannotExtendAbsoluteDeadline() throws {
        var fds = [Int32](repeating: -1, count: 2)
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        defer { fds.forEach { close($0) } }
        var byte: UInt8 = 65
        #expect(Darwin.write(fds[0], &byte, 1) == 1)
        let started = DispatchTime.now().uptimeNanoseconds
        #expect(throws: (any Error).self) { try SocketTransport.readLine(from: fds[1], deadlineSeconds: 0.03) }
        #expect(DispatchTime.now().uptimeNanoseconds - started < 1_000_000_000)
    }

}
