import Foundation
import CryptoKit

/// Memory-only permission for an exact invocation. This is not a sandbox: loaded
/// dependencies and child programs are not attested, and approved tools can copy secrets.
public struct DevelopmentApprovalCache {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let invocation: CLIRequest
        let request: Data
        public let executablePath: String
        let executableDigest: Data
        let artifacts: Data
        public let expiresAt: Date
        public var remainingUses: Int
    }
    private var entries: [Entry] = []
    public init() {}
    public static func eligible(_ request: CLIRequest) -> Bool {
        CommandRisk.warnings(for: request.command).isEmpty &&
        (request.environment != .production || (request.keepRunning != true && request.interactive != true))
    }
    private func encoded(_ request: CLIRequest) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(request)
    }
    /// Hash directly named files and common package task/configuration files. This detects
    /// edits to a script passed as an argument; it cannot attest every imported dependency.
    private func artifacts(_ request: CLIRequest) throws -> Data {
        guard request.environment == .production else { return Data() }
        let root = URL(fileURLWithPath: request.directory)
        var paths: Set<String> = []
        let names = ["package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "pyproject.toml", "uv.lock", "Makefile"]
        for argument in Array(request.command.dropFirst()) + names {
            let candidate = argument.hasPrefix("/") ? URL(fileURLWithPath: argument) : root.appendingPathComponent(argument)
            if FileManager.default.fileExists(atPath: candidate.path) {
                let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true {
                    guard (values.fileSize ?? Int.max) <= 4 * 1024 * 1024, paths.count < 64 else { throw VaultError.accessDenied }
                    paths.insert(candidate.standardizedFileURL.resolvingSymlinksInPath().path)
                }
            }
        }
        var hash = SHA256()
        for path in paths.sorted() {
            hash.update(data: Data(path.utf8)); hash.update(data: Data([0]))
            hash.update(data: try ExecutableIdentity.hashFile(path))
        }
        return Data(hash.finalize())
    }
    public mutating func remember(_ request: CLIRequest, executable: ExecutableIdentity, now: Date = Date()) throws {
        guard Self.eligible(request) else { return }
        let data = try encoded(request), digest = try artifacts(request)
        entries.removeAll { $0.expiresAt <= now || $0.request == data }
        if entries.count >= 32 { entries.removeFirst() }
        let production = request.environment == .production
        entries.append(Entry(id: UUID(), invocation: request, request: data, executablePath: executable.path, executableDigest: executable.digest, artifacts: digest, expiresAt: now.addingTimeInterval(production ? 300 : 1800), remainingUses: production ? 10 : Int.max))
    }
    public func allows(_ request: CLIRequest, executable: ExecutableIdentity, now: Date = Date()) -> Bool {
        matchingIndex(request, executable: executable, now: now) != nil
    }
    private func matchingIndex(_ request: CLIRequest, executable: ExecutableIdentity, now: Date) -> Int? {
        guard Self.eligible(request), let data = try? encoded(request), let digest = try? artifacts(request) else { return nil }
        return entries.firstIndex { $0.expiresAt > now && $0.remainingUses > 0 && $0.request == data && $0.executablePath == executable.path && $0.executableDigest == executable.digest && $0.artifacts == digest }
    }
    /// Reserve before starting, so concurrent callers cannot exceed the production budget.
    public mutating func consume(_ request: CLIRequest, executable: ExecutableIdentity, now: Date = Date()) -> Bool {
        guard let index = matchingIndex(request, executable: executable, now: now) else { return false }
        if entries[index].remainingUses != Int.max { entries[index].remainingUses -= 1 }
        return true
    }
    public func approvalReason(_ request: CLIRequest, executable: ExecutableIdentity, now: Date = Date()) -> String {
        guard Self.eligible(request) else { return L10n.tr("위험 경고 또는 실행 모드 때문에 매번 확인이 필요합니다.", "The risk warnings or execution mode require approval every time.") }
        guard let data = try? encoded(request), let entry = entries.first(where: { $0.request == data }) else { return L10n.tr("새 명령이거나 프로젝트·키·폴더·명령이 변경됐습니다.", "This is a new command, or the project, keys, directory, or command has changed.") }
        if entry.expiresAt <= now { return L10n.tr("기억한 명령 승인이 만료됐습니다.", "The remembered command approval has expired.") }
        if entry.remainingUses <= 0 { return L10n.tr("허용한 재실행 횟수를 모두 사용했습니다.", "All permitted reruns have been used.") }
        if entry.executablePath != executable.path || entry.executableDigest != executable.digest { return L10n.tr("실행 파일이 변경됐습니다.", "The executable has changed.") }
        return L10n.tr("직접 지정한 파일이나 패키지 설정이 변경됐습니다.", "A directly specified file or package configuration has changed.")
    }
    public func active(now: Date = Date()) -> [Entry] { entries.filter { $0.expiresAt > now && $0.remainingUses > 0 } }
    public mutating func revoke(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func clear() { entries.removeAll() }
}
