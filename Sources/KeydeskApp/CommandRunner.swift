import Foundation
import Darwin
import KeydeskCore

enum CommandRunner {
    static func start(_ request: CLIRequest, secrets: [String: String], channel: CLIChannel, approvedExecutable: ExecutableIdentity? = nil, completion: @escaping @Sendable () -> Void) throws -> RunningCommand {
        let process = Process()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let selected = try request.selectedSecrets(from: secrets)
        var injected = selected
        if let stdinKey = request.stdinKey { injected.removeValue(forKey: stdinKey) }
        var environment = ["PATH": ExecutableIdentity.searchPath, "HOME": home, "USER": NSUserName(), "LOGNAME": NSUserName(), "LANG": "en_US.UTF-8", "TERM": "dumb", "TMPDIR": NSTemporaryDirectory()]
        environment.merge(injected) { _, value in value }
        if request.interactive == true { environment["TERM"] = "xterm-256color" }
        let identity = try approvedExecutable ?? ExecutableIdentity.capture(command: request.command[0], directory: request.directory)
        // Detect replacement while approval is pending. A hostile same-uid process can still
        // race the final path-based spawn; this is not an OS isolation boundary.
        try identity.validate()
        let executable = identity.path
        if request.interactive == true {
            guard request.stdinKey == nil else { throw VaultError.invalidData }
            return try PTYRunner.start(executable: executable, arguments: Array(request.command.dropFirst()), environment: environment, directory: request.directory, keepRunning: request.keepRunning == true, secrets: Array(selected.values), channel: channel, completion: completion)
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(request.command.dropFirst())
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: request.directory, isDirectory: true)
        let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        process.standardOutput = stdout; process.standardError = stderr; process.standardInput = stdin
        try process.run()
        let running = RunningCommand(process: process, keepRunning: request.keepRunning == true)
        channel.send(CLIEvent(kind: "started"))
        if let variable = request.stdinKey {
            guard let value = selected[variable] else { process.terminate(); throw VaultError.invalidData }
            DispatchQueue.global().async {
                try? stdin.fileHandleForWriting.write(contentsOf: Data((value + "\n").utf8))
                try? stdin.fileHandleForWriting.close()
            }
        }
        let group = DispatchGroup()
        for (pipe, kind) in [(stdout, "stdout"), (stderr, "stderr")] {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                var redactor = StreamingRedactor(secrets: Array(selected.values))
                while true {
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    let count = Darwin.read(pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { break }
                    let bytes = Data(buffer.prefix(count))
                    let filtered = redactor.push(bytes)
                    if !filtered.isEmpty && !channel.send(CLIEvent(kind: kind, data: filtered)) {
                        if process.isRunning { process.terminate() }; break
                    }
                }
                let final = redactor.push(Data(), final: true)
                if !final.isEmpty { channel.send(CLIEvent(kind: kind, data: final)) }
                try? pipe.fileHandleForReading.close()
            }
        }
        DispatchQueue.global().async {
            defer { try? stdin.fileHandleForWriting.close(); running.terminate() }
            do {
                while let line = try SocketTransport.readLine(from: channel.fd, maximum: 16_384) {
                    let input = try JSONDecoder().decode(CLIInput.self, from: line)
                    if input.kind == "cancel" { break }
                    if input.kind == "stdin", request.stdinKey == nil, let data = input.data, data.count <= 4096 { try stdin.fileHandleForWriting.write(contentsOf: data) }
                    else if input.kind == "eof" { try? stdin.fileHandleForWriting.close() }
                    else if input.kind != "resize" { throw VaultError.invalidData }
                }
            } catch {}
        }
        DispatchQueue.global().async {
            process.waitUntilExit(); group.wait()
            running.didFinish()
            channel.send(CLIEvent(kind: "exit", exitCode: process.terminationStatus))
            channel.finish(); completion()
        }
        return running
    }
}
