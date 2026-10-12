import Foundation

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var colorIndex: Int
    public var iconPNG: Data?
    public init(id: UUID = UUID(), name: String, colorIndex: Int = 0, iconPNG: Data? = nil) {
        self.id = id; self.name = name; self.colorIndex = colorIndex; self.iconPNG = iconPNG
    }
}
