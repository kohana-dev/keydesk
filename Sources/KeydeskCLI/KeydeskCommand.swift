import Foundation
import Darwin
import KeydeskCore

@main
enum KeydeskCommand {
    static let help = """
    keydesk run --project <이름|UUID> --env <dev|staging|prod> [--only <VAR,VAR>] [--stdin-key <VAR>] [--interactive] [--keep-running] -- <명령> [인자...]
    keydesk mcp --project <UUID> --env <dev|staging|prod>
    keydesk store-file --project <이름> --env <dev|staging|prod> --name <PATH_VAR> --from-file <경로>
    keydesk run --project <이름|UUID> --env dev --files <PATH_VAR,...> -- <명령> [인자...]
    keydesk store --project <이름> --env <dev|staging|prod> --name <VAR> --stdin
    keydesk store --project <이름> --env <dev|staging|prod> --name <VAR> --from-env-file <경로>
    keydesk lock
    keydesk delete-project --project <이름|UUID> --delete-exclusive-keys
    keydesk verify-recovery
    keydesk install

    앱에서 금고를 열고 승인해야 합니다. 실행 코드는 전달된 키를 읽을 수 있습니다.
    delete-project: 잠금 해제된 금고에서 프로젝트와 전용 키 삭제. 공유 키는 보존. 과거 백업·제공사 키는 별도.
    --only: 환경변수로 전달할 이름을 명시해야 합니다. 생략 시 모든 키를 전달하지 않습니다.
    --stdin-key: 이 키는 표준입력에만 전달하며 환경변수에는 넣지 않습니다.
    --interactive: 실제 터미널에서 대화형 CLI 실행. --stdin-key와 함께 사용하지 않습니다.
    --keep-running: 금고가 잠겨도 승인된 개발 프로세스 유지. CLI 연결 종료/앱 종료 시 종료 요청.
    """
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let terminal = TerminalSession()
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let result: Int32
            if args.first == "mcp" { result = try MCPServer.run(Array(args.dropFirst())) }
            else if args.first == "store" || args.first == "store-file" || args.first == "delete-project" || args == ["verify-recovery"] || args == ["lock"] { result = try service(args) }
            else if args == ["install"] { try install(); result = 0 }
            else { result = try run(args, terminal: terminal) }
            terminal.restore(); exit(terminal.terminationExitCode ?? result)
        } catch {
            terminal.restore()
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(terminal.terminationExitCode ?? 1)
        }
    }
    static func service(_ args: [String]) throws -> Int32 {
        var request = ServiceRequest(kind: args.first ?? "")
        if args.first == "delete-project" {
            guard args.count == 4, args[1] == "--project", !args[2].isEmpty, args[3] == "--delete-exclusive-keys" else { throw VaultError.invalidData }
            request.project = args[2]
        }
        if args.first == "store-file" {
            var source: String?, index = 1
            while index < args.count {
                guard index + 1 < args.count else { throw VaultError.invalidData }
                switch args[index] {
                case "--project": request.project = args[index+1]
                case "--env": request.environment = EnvironmentName(rawValue: args[index+1])
                case "--name": request.variable = args[index+1]
                case "--from-file": source = args[index+1]
                default: throw VaultError.invalidData
                }
                index += 2
            }
            guard let source, let project = request.project, let variable = request.variable,
                  let environment = request.environment else { throw VaultError.invalidData }
            let file = try SecretFile.read(at: URL(fileURLWithPath: source))
            _ = try SecretDeposit(project: project, environment: environment, variable: variable, file: file)
            request.file = file
        }
        if args.first == "store" {
            var index = 1, fromStdin = false, sourceFile: String?
            while index < args.count {
                if args[index] == "--stdin" { fromStdin = true; index += 1; continue }
                guard index + 1 < args.count else { throw VaultError.invalidData }
                switch args[index] {
                case "--project": request.project = args[index+1]
                case "--env": request.environment = EnvironmentName(rawValue: args[index+1])
                case "--name": request.variable = args[index+1]
                case "--from-env-file": sourceFile = args[index+1]
                default: throw VaultError.invalidData
                }
                index += 2
            }
            guard let project = request.project, let variable = request.variable, let environment = request.environment, fromStdin != (sourceFile != nil) else { throw VaultError.invalidData }
            let value: String
            if let sourceFile {
                let file = try Data(contentsOf: URL(fileURLWithPath: sourceFile))
                guard file.count <= 1024 * 1024, let text = String(data: file, encoding: .utf8) else { throw VaultError.invalidData }
                let rows = DotenvParser.parse(text)
                guard let row = rows.first(where: { $0.name == variable }), row.error == nil else { throw VaultError.invalidData }
                value = row.value
            } else {
                var bytes = Data()
                while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
                    guard bytes.count + chunk.count <= 32769 else { throw VaultError.invalidData }
                    bytes.append(chunk)
                }
                guard var text = String(data: bytes, encoding: .utf8) else { throw VaultError.invalidData }
                if text.hasSuffix("\n") { text.removeLast(); if text.hasSuffix("\r") { text.removeLast() } }
                value = text
            }
            _ = try SecretDeposit(project: project, environment: environment, variable: variable, value: value)
            request.value = value
        }
        let connection = try ClientConnection(path: ProcessInfo.processInfo.environment["KEYDESK_SOCKET_PATH"] ?? SocketTransport.socketPath)
        defer { connection.closeConnection() }
        try connection.send(request)
        while let line = try SocketTransport.readLine(from: connection.fd) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            if let data = event.data { FileHandle.standardOutput.write(data) }
            if let text = event.text { FileHandle.standardError.write(Data((text + "\n").utf8)) }
            if event.kind == "error" { return 1 }
            if event.kind == "exit" { return event.exitCode ?? 1 }
        }
        return 1
    }
    static func run(_ args: [String], terminal: TerminalSession) throws -> Int32 {
        if args.isEmpty || args == ["--help"] || args == ["help"] { print(help); return 0 }
        guard args.first == "run", let separator = args.firstIndex(of: "--"), separator + 1 < args.count else { throw VaultError.invalidData }
        var project: String?, environment = EnvironmentName.development, stdinKey: String?, variables: [String]?
        var fileVariables: [String]?
        var interactive = false, keepRunning = false, index = 1
        while index < separator {
            if args[index] == "--interactive" { interactive = true; index += 1; continue }
            if args[index] == "--keep-running" { keepRunning = true; index += 1; continue }
            guard index + 1 < separator else { throw VaultError.invalidData }
            switch args[index] {
            case "--project": project = args[index + 1]
            case "--env": guard let value = EnvironmentName(rawValue: args[index + 1]) else { throw VaultError.invalidData }; environment = value
            case "--stdin-key": stdinKey = args[index + 1]
            case "--files": fileVariables = args[index + 1].split(separator: ",").map(String.init)
            case "--only": variables = args[index + 1].split(separator: ",").map(String.init)
            default: throw VaultError.invalidData
            }
            index += 2
        }
        guard let project, !project.isEmpty, !(interactive && stdinKey != nil), !interactive || isatty(STDIN_FILENO) == 1 else { throw VaultError.invalidData }
        guard variables?.isEmpty == false || stdinKey != nil || fileVariables?.isEmpty == false else {
            throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: "--only로 전달할 변수를 지정하거나 --stdin-key를 사용하세요. 전체 키를 자동으로 전달하지 않습니다."])
        }
        let connection = try ClientConnection(path: ProcessInfo.processInfo.environment["KEYDESK_SOCKET_PATH"] ?? SocketTransport.socketPath)
        defer { connection.closeConnection() }
        try connection.send(CLIRequest(project: project, environment: environment, command: Array(args[(separator + 1)...]), directory: FileManager.default.currentDirectoryPath, stdinKey: stdinKey, variables: variables, interactive: interactive, keepRunning: keepRunning, fileVariables: fileVariables))
        var resizing: DispatchSourceSignal?
        var terminationSources: [DispatchSourceSignal] = []
        defer { resizing?.cancel(); terminationSources.forEach { $0.cancel() } }
        while let line = try SocketTransport.readLine(from: connection.fd) {
            let event = try JSONDecoder().decode(CLIEvent.self, from: line)
            switch event.kind {
            case "stdout": if let data = event.data { FileHandle.standardOutput.write(data) }
            case "stderr": if let data = event.data { FileHandle.standardError.write(data) }
            case "status": if let text = event.text { FileHandle.standardError.write(Data((text + "\n").utf8)) }
            case "error": FileHandle.standardError.write(Data(((event.text ?? "실행 거부") + "\n").utf8)); return 1
            case "exit": return event.exitCode ?? 1
            case "started":
                connection.allowLongRunningRead()
                if interactive {
                    try terminal.start(); try connection.send(TerminalSession.size())
                    for value in [SIGTERM, SIGHUP] {
                        signal(value, SIG_IGN)
                        let termination = DispatchSource.makeSignalSource(signal: value, queue: .global())
                        termination.setEventHandler { terminal.markTerminated(code: 128 + value); connection.closeConnection(); exit(128 + value) }
                        termination.resume(); terminationSources.append(termination)
                    }
                    signal(SIGWINCH, SIG_IGN)
                    let source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .global())
                    source.setEventHandler { try? connection.send(TerminalSession.size()) }; source.resume(); resizing = source
                }
                if stdinKey == nil {
                    DispatchQueue.global().async {
                        var buffer = [UInt8](repeating: 0, count: 4096)
                        while true {
                            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
                            if count < 0 && errno == EINTR { continue }
                            if count <= 0 { try? connection.send(CLIInput(kind: "eof")); break }
                            do { try connection.send(CLIInput(kind: "stdin", data: Data(buffer.prefix(count)))) } catch { break }
                        }
                    }
                }
            default: throw VaultError.invalidData
            }
        }
        throw VaultError.locked
    }
    static func install() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        let target = try CLIInstaller.install(executable: source)
        print("설치 위치: \(target.path)")
        print("PATH에 ~/.local/bin이 없다면 셸 설정에 추가하세요. 기존 설정은 변경하지 않았습니다.")
    }
}
