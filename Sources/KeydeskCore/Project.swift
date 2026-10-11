import Foundation

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var colorIndex: Int
    public init(id: UUID = UUID(), name: String, colorIndex: Int = 0) {
        self.id = id; self.name = name; self.colorIndex = colorIndex
    }
}
