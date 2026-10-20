import Foundation

/// The stored representation belongs to a version, so restoring a version also restores its type.
public enum SecretFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case apiKey, keyValue, json, text, file

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .apiKey: L10n.tr("API 키", "API key")
        case .keyValue: L10n.tr("키·값 묶음", "Key-value pairs")
        case .json: "JSON"
        case .text: L10n.tr("일반 텍스트", "Plain text")
        case .file: L10n.tr("파일", "File")
        }
    }

    public var shortTitle: String {
        switch self {
        case .apiKey: L10n.tr("API 키", "API key")
        case .keyValue: L10n.tr("키·값", "Key-value")
        case .json: "JSON"
        case .text: L10n.tr("텍스트", "Text")
        case .file: L10n.tr("파일", "File")
        }
    }

    public var symbol: String {
        switch self {
        case .apiKey: "key.horizontal"
        case .keyValue: "list.bullet.rectangle"
        case .json: "curlybraces"
        case .text: "doc.text"
        case .file: "doc"
        }
    }

    public var requiresTypedVault: Bool { self != .apiKey && self != .file }
}
