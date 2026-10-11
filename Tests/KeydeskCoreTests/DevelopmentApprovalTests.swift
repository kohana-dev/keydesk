import Testing
import Foundation
@testable import KeydeskCore

struct DevelopmentApprovalTests {
    func request(project: String = "fixture", environment: EnvironmentName = .development, command: [String] = ["/usr/bin/true"], directory: String = "/tmp", variables: [String] = ["KEY"], stdinKey: String? = nil, interactive: Bool = false, keepRunning: Bool = false) -> CLIRequest {
        CLIRequest(project: project, environment: environment, command: command, directory: directory, stdinKey: stdinKey, variables: variables, interactive: interactive, keepRunning: keepRunning)
    }
    @Test func exactInvocationExpiresAndRevokes() throws {
        let invocation = request(), executable = try ExecutableIdentity.capture(command: "/usr/bin/true", directory: "/tmp"), now = Date()
        var cache = DevelopmentApprovalCache()
        #expect(!cache.allows(invocation, executable: executable, now: now))
        try cache.remember(invocation, executable: executable, now: now)
        #expect(cache.allows(invocation, executable: executable, now: now.addingTimeInterval(1799)))
        #expect(!cache.allows(invocation, executable: executable, now: now.addingTimeInterval(1800)))
        try cache.remember(invocation, executable: executable, now: now)
        cache.clear()
        #expect(!cache.allows(invocation, executable: executable, now: now))
    }
    @Test func changedScopeAndExecutableRequireApproval() throws {
        let executable = try ExecutableIdentity.capture(command: "/usr/bin/true", directory: "/tmp")
        var cache = DevelopmentApprovalCache()
        try cache.remember(request(), executable: executable)
        for changed in [request(project: "other"), request(environment: .staging), request(command: ["/usr/bin/true", "arg"]), request(directory: "/"), request(variables: ["OTHER"]), request(stdinKey: "KEY"), request(interactive: true), request(keepRunning: true)] {
            #expect(!cache.allows(changed, executable: executable))
        }
        #expect(!cache.allows(request(), executable: ExecutableIdentity(path: executable.path, digest: Data([0]))))
        #expect(!cache.allows(request(), executable: ExecutableIdentity(path: "/other", digest: executable.digest)))
    }
    @Test func productionExpiryUseLimitAndFileChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prod-cache-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("task.py")
        try Data("print('fixture')".utf8).write(to: script)
        let invocation = request(environment: .production, command: ["/usr/bin/true", "task.py"], directory: root.path)
        let executable = try ExecutableIdentity.capture(command: "/usr/bin/true", directory: root.path), now = Date()
        var cache = DevelopmentApprovalCache()
        try cache.remember(invocation, executable: executable, now: now)
        #expect(cache.allows(invocation, executable: executable, now: now.addingTimeInterval(299)))
        #expect(!cache.allows(invocation, executable: executable, now: now.addingTimeInterval(300)))
        for _ in 0..<10 { let allowed = cache.consume(invocation, executable: executable, now: now); #expect(allowed) }
        let exhausted = cache.consume(invocation, executable: executable, now: now); #expect(!exhausted)
        try cache.remember(invocation, executable: executable, now: now)
        try Data("print('changed')".utf8).write(to: script)
        #expect(!cache.allows(invocation, executable: executable, now: now))
        try cache.remember(invocation, executable: executable, now: now)
        try FileManager.default.removeItem(at: script)
        #expect(!cache.allows(invocation, executable: executable, now: now))
        for mode in [request(environment: .production, interactive: true), request(environment: .production, keepRunning: true)] {
            try cache.remember(mode, executable: executable, now: now)
            #expect(!cache.allows(mode, executable: executable, now: now))
        }
    }

    @Test func warningCommandsCannotBeRemembered() throws {
        let executable = try ExecutableIdentity.capture(command: "/usr/bin/true", directory: "/tmp")
        var cache = DevelopmentApprovalCache()
        for restricted in [request(command: ["/bin/sh", "-c", "echo $KEY"]), request(command: ["curl", "https://example.com"])] {
            try cache.remember(restricted, executable: executable)
            #expect(!cache.allows(restricted, executable: executable))
        }
    }
}
