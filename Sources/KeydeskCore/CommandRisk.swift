import Foundation

/// Approval hints for commands that can trivially print or send an injected key.
/// A heuristic for the person approving; it is not a sandbox and cannot prove a command safe.
public enum CommandRisk {
    private static let wrappers: Set<String> = ["env", "exec", "command", "nohup", "time", "xargs", "sudo", "nice"]
    private static let shells: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "csh", "tcsh"]
    private static let inlineFlags: [String: Set<String>] = [
        "python": ["-c"], "python3": ["-c"], "node": ["-e", "-p", "--eval", "--print"], "deno": ["eval"], "bun": ["-e", "--eval"],
        "ruby": ["-e"], "perl": ["-e", "-E"], "php": ["-r"], "osascript": ["-e"], "swift": ["-e"]
    ]
    private static let network: Set<String> = ["curl", "wget", "nc", "ncat", "netcat", "socat", "ssh", "scp", "sftp", "rsync", "ftp", "telnet"]
    private static let printers: Set<String> = ["echo", "printf", "env", "printenv", "set", "export", "declare", "cat", "tee"]

    public static func warnings(for command: [String]) -> [String] {
        let bases = command.map { ($0 as NSString).lastPathComponent.lowercased() }
        let printWarning = "값을 그대로 화면이나 파일에 출력할 수 있는 명령입니다."
        // Skip wrappers such as `env FOO=1 sh -c ...` to reach the program that actually runs.
        var index = 0
        while index < bases.count, wrappers.contains(bases[index]) {
            index += 1
            while index < bases.count, bases[index].hasPrefix("-") || command[index].contains("=") { index += 1 }
        }
        guard index < bases.count else { return bases.contains("env") ? [printWarning] : [] }
        let name = bases[index]
        let arguments = Array(command[(index + 1)...])
        var result: [String] = []
        if printers.contains(name) { result.append(printWarning) }
        if shells.contains(name) && arguments.contains(where: { $0 == "-c" || ($0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("c")) }) {
            result.append("셸에 문자열로 된 코드를 실행합니다. 출력 마스킹은 base64 같은 변환을 막지 못합니다.")
        }
        if let flags = inlineFlags[name] ?? inlineFlags[name.replacingOccurrences(of: #"[0-9.]+$"#, with: "", options: .regularExpression)],
           arguments.contains(where: flags.contains) {
            result.append("명령줄에 적힌 코드를 바로 실행합니다. 코드가 키를 읽고 변환하거나 전송할 수 있습니다.")
        }
        if network.contains(name) {
            result.append("네트워크 전송 도구입니다. 키를 외부 주소로 보낼 수 있습니다.")
        }
        return result
    }
}
