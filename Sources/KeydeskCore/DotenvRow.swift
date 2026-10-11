import Foundation

public struct DotenvRow: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let value: String
    public let error: String?
}
