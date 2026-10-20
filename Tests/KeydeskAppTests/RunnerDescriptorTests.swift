import Foundation
import Darwin
import Testing
import KeydeskCore
@testable import KeydeskApp

struct RunnerDescriptorTests {
    @Test func aDelayedInputReaderCannotConsumeAReusedChannelsOutput() async throws {
        let (oldChannel, oldClient) = try RunnerTests().sockets()
        defer { oldChannel.finish(); close(oldClient) }
        let oldInput = try oldChannel.makeInputHandle()
        defer { try? oldInput.close() }
        #expect(oldInput.fileDescriptor != oldChannel.fd)
        #expect(fcntl(oldInput.fileDescriptor, F_GETFD) & FD_CLOEXEC != 0)
        oldChannel.finish()

        // Allocate subsequent requests before the old pump starts. Its owned descriptor must
        // observe shutdown, even if the original descriptor number has already been recycled.
        var following: [(CLIChannel, Int32)] = []
        defer { for (channel, client) in following { channel.finish(); close(client) } }
        for _ in 0..<32 { following.append(try RunnerTests().sockets()) }
        for (index, pair) in following.enumerated() {
            try SocketTransport.send(CLIEvent(kind: "stdout", text: "FOLLOWING_\(index)"), to: pair.1)
        }
        let sawEOF = try await BlockingRunnerTestSupport.run {
            try SocketTransport.readLine(from: oldInput.fileDescriptor) == nil
        }
        #expect(sawEOF)
        #expect(throws: (any Error).self) { try oldChannel.makeInputHandle() }
        for (index, pair) in following.enumerated() {
            let bytes = try #require(try await BlockingRunnerTestSupport.readLine(from: pair.0.fd))
            #expect(try JSONDecoder().decode(CLIEvent.self, from: bytes).text == "FOLLOWING_\(index)")
        }
    }

    @Test func rapidConcurrentPipeAndPTYRunsKeepEveryOutputWithItsOwnRequest() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for worker in 0..<4 {
                group.addTask {
                    for round in 0..<20 {
                        let index = worker * 20 + round
                        let text = try await Self.run(index: index, interactive: round % 2 == 1)
                        #expect(text.replacingOccurrences(of: "\r\n", with: "\n") == "RUN_\(index)\n[REDACTED]\n")
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    @Test @MainActor func mainActorLaunchAndOffMainBlockingReadBothDeliverOutput() async throws {
        #expect(Self.isMainThread())
        let (channel, client) = try RunnerTests().sockets()
        defer { channel.finish(); close(client) }
        let request = CLIRequest(project: "Synthetic main actor", environment: .development,
                                 command: ["/bin/sh", "-c", "printf 'MAIN_ACTOR_LAUNCH_OK\\n'"],
                                 directory: "/tmp", stdinKey: nil, variables: ["KEY"])
        let running = try CommandRunner.start(request, secrets: ["KEY": "SYNTHETIC_THREAD_FIXTURE"], channel: channel, completion: {})
        defer { running.terminate() }
        let readerWasMain = try await BlockingRunnerTestSupport.run { Thread.isMainThread }
        #expect(!readerWasMain)
        let output = try await Self.output(from: client)
        #expect(output == "MAIN_ACTOR_LAUNCH_OK\n")
    }

    @MainActor private static func isMainThread() -> Bool { Thread.isMainThread }

    private static func run(index: Int, interactive: Bool) async throws -> String {
        let (channel, client) = try RunnerTests().sockets()
        defer { channel.finish(); close(client) }
        let request = CLIRequest(project: "Synthetic descriptor reuse", environment: .development,
                                 command: ["/bin/sh", "-c", "printf 'RUN_\(index)\\n%s\\n' \"$KEY\""],
                                 directory: "/tmp", stdinKey: nil, variables: ["KEY"], interactive: interactive)
        let running = try await BlockingRunnerTestSupport.start(request, secrets: ["KEY": "SYNTHETIC_RAPID_TOKEN"], channel: channel)
        defer { running.terminate() }
        return try await output(from: client)
    }

    private static func output(from descriptor: Int32) async throws -> String {
        var output = Data(), exitCode: Int32?
        while let line = try await BlockingRunnerTestSupport.readLine(from: descriptor) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            if let data = event.data { output += data }
            if event.kind == "exit" { exitCode = event.exitCode; break }
        }
        guard exitCode == 0 else { throw VaultError.invalidData }
        return String(decoding: output, as: UTF8.self)
    }
}
