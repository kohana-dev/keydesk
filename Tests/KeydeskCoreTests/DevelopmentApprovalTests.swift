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
    @Test func productionAndWarningCommandsCannotBeRemembered() throws {
        let executable = try ExecutableIdentity.capture(command: "/usr/bin/true", directory: "/tmp")
        var cache = DevelopmentApprovalCache()
        for restricted in [request(environment: .production), request(command: ["/bin/sh", "-c", "echo $KEY"]), request(command: ["curl", "https://example.com"])] {
            try cache.remember(restricted, executable: executable)
            #expect(!cache.allows(restricted, executable: executable))
        }
    }
}
