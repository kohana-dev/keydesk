import Foundation
import Darwin
import KeydeskCore

enum PTYRunner {
    static func start(executable: String, arguments: [String], environment: [String: String], directory: String, keepRunning: Bool, secrets: [String], channel: CLIChannel, completion: @escaping @Sendable () -> Void) throws -> RunningCommand {
        var master: Int32 = -1, slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        guard openpty(&master, &slave, &name, nil, nil) == 0 else { throw POSIXError(.EIO) }
        let slaveName = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        close(slave)
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addopen(&actions, 0, slaveName, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&actions, 0, 1); posix_spawn_file_actions_adddup2(&actions, 0, 2)
        posix_spawn_file_actions_addchdir_np(&actions, directory)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.compactMap { $0 }.forEach { free($0) }; envp.compactMap { $0 }.forEach { free($0) } }
        var pid: pid_t = 0
        let result = argv.withUnsafeBufferPointer { argv in envp.withUnsafeBufferPointer { envp in
            posix_spawn(&pid, executable, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
        } }
        guard result == 0 else { close(master); throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        let childPID = pid
        let running = RunningCommand(pid: childPID, keepRunning: keepRunning)
        let terminal = master
        let inputFinished = DispatchGroup(); inputFinished.enter()
        channel.send(CLIEvent(kind: "started"))
        DispatchQueue.global().async {
            defer { close(terminal) }
            var redactor = StreamingRedactor(secrets: secrets)
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = Darwin.read(terminal, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { break }
                let output = redactor.push(Data(buffer.prefix(count)))
                if !output.isEmpty && !channel.send(CLIEvent(kind: "stdout", data: output)) { running.terminate(); break }
            }
            let tail = redactor.push(Data(), final: true)
            if !tail.isEmpty { channel.send(CLIEvent(kind: "stdout", data: tail)) }
            var status: Int32 = 0
            while waitpid(childPID, &status, 0) < 0 && errno == EINTR {}
            running.didFinish()
            let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            channel.send(CLIEvent(kind: "exit", exitCode: exitCode)); channel.finish(); inputFinished.wait(); completion()
        }
        DispatchQueue.global().async {
            defer { inputFinished.leave() }
            do {
                while let line = try SocketTransport.readLine(from: channel.fd, maximum: 16_384) {
                    let input = try JSONDecoder().decode(CLIInput.self, from: line)
                    if input.kind == "cancel" { break }
                    if input.kind == "resize", let rows = input.rows, let cols = input.columns {
                        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
                        _ = ioctl(terminal, TIOCSWINSZ, &size)
                    } else if input.kind == "stdin", let data = input.data, data.count <= 4096 {
                        try data.withUnsafeBytes { bytes in
                            var offset = 0
                            while offset < bytes.count {
                                let n = Darwin.write(terminal, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                                guard n > 0 else { throw POSIXError(.EIO) }; offset += n
                            }
                        }
                    } else if input.kind == "eof" { var eof: UInt8 = 4; _ = Darwin.write(terminal, &eof, 1) }
                    else { throw VaultError.invalidData }
                }
            } catch {}
            running.terminate()
        }
        return running
    }
}
