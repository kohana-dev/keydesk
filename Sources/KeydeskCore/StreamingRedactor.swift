import Foundation

/// Exact byte matches only. This does not prevent encoded, partial or transformed secret output.
public struct StreamingRedactor: Sendable {
    private var pending = Data()
    private let secrets: [Data]
    private let tailSize: Int
    public init(secrets: [String]) {
        self.init(bytes: secrets.map { Data($0.utf8) })
    }
    public init(bytes: [Data]) {
        secrets = Array(Set(bytes.filter { !$0.isEmpty })).sorted { $0.count > $1.count }
        tailSize = secrets.map(\.count).max() ?? 0
    }
    public mutating func push(_ chunk: Data, final: Bool = false) -> Data {
        pending.append(chunk)
        var output = Data()
        let limit = pending.count
        var index = 0
        while index < limit {
            // Keep only a suffix that could actually become a secret. Prompts must stream immediately.
            if !final, pending.count - index <= tailSize,
               secrets.contains(where: { pending.count - index < $0.count && $0.prefix(pending.count - index).elementsEqual(pending[index...]) }) { break }
            if let secret = secrets.first(where: { index + $0.count <= pending.count && pending[index..<(index + $0.count)].elementsEqual($0) }) {
                output.append(Data("[REDACTED]".utf8)); index += secret.count
            } else { output.append(pending[index]); index += 1 }
        }
        pending = Data(pending.dropFirst(index))
        return output
    }
}
