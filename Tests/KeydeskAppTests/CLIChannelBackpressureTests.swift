import Testing
import Foundation
import Darwin
import KeydeskCore
@testable import KeydeskApp

struct CLIChannelBackpressureTests {
    private func sockets() throws -> (CLIChannel, Int32) {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.EIO) }
        var size: Int32 = 4096
        setsockopt(descriptors[0], SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        return (CLIChannel(fd: descriptors[0]), descriptors[1])
    }

    @Test @MainActor func nonReadingPeerCannotBlockMainActorOrFinish() async throws {
        let (channel, client) = try sockets()
        defer { channel.finish(); close(client) }
        let heartbeat = DispatchSemaphore(value: 0)
        let responsive = await withCheckedContinuation { continuation in
            // The independent watchdog releases an old blocking sender, so a regression fails
            // instead of leaving the test suite hung. The peer intentionally never reads.
            Thread.detachNewThread {
                let result = heartbeat.wait(timeout: .now() + .seconds(1))
                shutdown(client, SHUT_RDWR)
                continuation.resume(returning: result == .success)
            }
            _ = channel.send(CLIEvent(kind: "stdout", data: Data(repeating: 65, count: 1_048_576)))
            _ = channel.isConnected
            channel.finish()
            Task { @MainActor in heartbeat.signal() }
        }
        #expect(responsive, "A slow CLI reader held the main actor in socket output or finish")
    }

    @Test func normalLargeResponseAndExitAreDeliveredBeforeFinishInOrder() async throws {
        let (channel, client) = try sockets()
        defer { channel.finish(); close(client) }
        let payload = Data(repeating: 66, count: 1_048_576)
        #expect(channel.send(CLIEvent(kind: "status", text: "synthetic response")))
        #expect(channel.send(CLIEvent(kind: "stdout", data: payload)))
        #expect(channel.send(CLIEvent(kind: "exit", exitCode: 0)))
        channel.finish()
        let events = try await BlockingRunnerTestSupport.run {
            var events: [CLIEvent] = []
            while let line = try SocketTransport.readLine(from: client, maximum: 2 * 1_048_576, deadlineSeconds: 5) {
                events.append(try JSONDecoder().decode(CLIEvent.self, from: line))
            }
            return events
        }
        try #require(events.count == 3)
        #expect(events.map(\.kind) == ["status", "stdout", "exit"])
        #expect(events[1].data == payload)
        #expect(events[2].exitCode == 0)
        #expect(!channel.isConnected)
        #expect(!channel.send(CLIEvent(kind: "status", text: "too late")))
    }

    @Test func overflowingOutboxRejectsOutputAndDisconnectsWithoutWaitingForPeer() throws {
        let (channel, client) = try sockets()
        defer { channel.finish(); close(client) }
        let event = CLIEvent(kind: "stdout", data: Data(repeating: 67, count: 1_048_576))
        var rejected = false
        for _ in 0..<5 {
            if !channel.send(event) { rejected = true; break }
        }
        #expect(rejected)
        #expect(!channel.isConnected)
        #expect(!channel.send(CLIEvent(kind: "exit", exitCode: 0)))
        #expect(throws: (any Error).self) { try channel.makeInputHandle() }
    }
}
