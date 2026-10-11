import Foundation

/// Memory-only permission for an exact development invocation. This is not a sandbox:
/// an approved tool can load changed dependencies and read its injected variables.
public struct DevelopmentApprovalCache {
    private struct Entry {
        let request: Data
        let executablePath: String
        let executableDigest: Data
        let expiresAt: Date
    }
    private var entries: [Entry] = []
    public init() {}
    public static func eligible(_ request: CLIRequest) -> Bool {
        request.environment != .production && CommandRisk.warnings(for: request.command).isEmpty
    }
    private func encoded(_ request: CLIRequest) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(request)
    }
    public mutating func remember(_ request: CLIRequest, executable: ExecutableIdentity, now: Date = Date()) throws {
        guard Self.eligible(request) else { return }
        entries.removeAll { $0.expiresAt <= now }
        if entries.count >= 32 { entries.removeFirst() }
        entries.append(Entry(request: try encoded(request), executablePath: executable.path, executableDigest: executable.digest, expiresAt: now.addingTimeInterval(1800)))
    }
    public func allows(_ request: CLIRequest, executable: ExecutableIdentity, now: Date = Date()) -> Bool {
        guard Self.eligible(request), let data = try? encoded(request) else { return false }
        return entries.contains { $0.expiresAt > now && $0.request == data && $0.executablePath == executable.path && $0.executableDigest == executable.digest }
    }
    public mutating func clear() { entries.removeAll() }
}
