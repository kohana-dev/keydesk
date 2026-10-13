import Foundation

/// Public release metadata only. This type has no access to vault or account data.
public struct AppRelease: Equatable, Sendable {
    public static let latestAPIURL = URL(string: "https://api.github.com/repos/kohana-dev/keydesk/releases/latest")!
    public static let maximumResponseBytes = 256 * 1_024

    public let version: Version
    public var pageURL: URL {
        URL(string: "https://github.com/kohana-dev/keydesk/releases/tag/v\(version.rawValue)")!
    }

    public enum CheckError: Error, Equatable, Sendable {
        case invalidVersion
        case unexpectedOrigin
        case invalidResponse
        case unsupportedRelease
        case oversizedResponse
        case rateLimited
        case notFound
        case serverUnavailable
        case httpFailure
    }

    /// A strict SemVer value; build metadata does not affect version precedence.
    public struct Version: Comparable, Sendable {
        public let rawValue: String
        private let major: UInt64
        private let minor: UInt64
        private let patch: UInt64
        private let prerelease: [String]

        public init(_ value: String) throws {
            guard value.utf8.count <= 128 else { throw CheckError.invalidVersion }
            let metadataParts = value.split(separator: "+", omittingEmptySubsequences: false)
            guard metadataParts.count <= 2,
                  metadataParts.count == 1 || Self.validIdentifiers(String(metadataParts[1]), numericLeadingZeroAllowed: true) else {
                throw CheckError.invalidVersion
            }
            let releaseParts = metadataParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let numbers = releaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
            guard numbers.count == 3,
                  let major = Self.number(numbers[0]),
                  let minor = Self.number(numbers[1]),
                  let patch = Self.number(numbers[2]) else { throw CheckError.invalidVersion }
            if releaseParts.count == 2 {
                guard Self.validIdentifiers(String(releaseParts[1]), numericLeadingZeroAllowed: false) else {
                    throw CheckError.invalidVersion
                }
                prerelease = releaseParts[1].split(separator: ".").map(String.init)
            } else {
                prerelease = []
            }
            rawValue = value
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        public var isPrerelease: Bool { !prerelease.isEmpty }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
            if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
                return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
            }
            for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
                let leftIsNumber = left.utf8.allSatisfy { (48...57).contains($0) }
                let rightIsNumber = right.utf8.allSatisfy { (48...57).contains($0) }
                if leftIsNumber && rightIsNumber {
                    // Comparing lengths avoids integer overflow for prerelease identifiers.
                    return left.count == right.count ? left < right : left.count < right.count
                }
                if leftIsNumber != rightIsNumber { return leftIsNumber }
                return left < right
            }
            return lhs.prerelease.count < rhs.prerelease.count
        }

        private static func number(_ value: Substring) -> UInt64? {
            guard !value.isEmpty,
                  value.utf8.allSatisfy({ (48...57).contains($0) }),
                  value.count == 1 || value.first != "0" else { return nil }
            return UInt64(value)
        }

        private static func validIdentifiers(_ value: String, numericLeadingZeroAllowed: Bool) -> Bool {
            value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { identifier in
                guard !identifier.isEmpty,
                      identifier.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { return false }
                if !numericLeadingZeroAllowed, identifier.utf8.allSatisfy({ (48...57).contains($0) }) {
                    return identifier.count == 1 || identifier.first != "0"
                }
                return true
            }
        }
    }

    public static func parse(data: Data, statusCode: Int, responseURL: URL?, mimeType: String?) throws -> Self {
        guard responseURL == latestAPIURL else { throw CheckError.unexpectedOrigin }
        switch statusCode {
        case 200: break
        case 403, 429: throw CheckError.rateLimited
        case 404: throw CheckError.notFound
        case 500...599: throw CheckError.serverUnavailable
        default: throw CheckError.httpFailure
        }
        guard data.count <= maximumResponseBytes else { throw CheckError.oversizedResponse }
        guard mimeType?.lowercased() == "application/json" else { throw CheckError.invalidResponse }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw CheckError.invalidResponse }
        guard !payload.draft, !payload.prerelease, payload.tagName.hasPrefix("v") else {
            throw CheckError.unsupportedRelease
        }
        let version = try Version(String(payload.tagName.dropFirst()))
        guard !version.isPrerelease else { throw CheckError.unsupportedRelease }
        let release = Self(version: version)
        guard payload.htmlURL == release.pageURL.absoluteString else { throw CheckError.unexpectedOrigin }
        var hasDownload = false
        for asset in payload.assets {
            guard !asset.name.isEmpty, asset.name.utf8.count <= 180,
                  asset.name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 }),
                  asset.name != ".", asset.name != "..",
                  asset.browserDownloadURL == "https://github.com/kohana-dev/keydesk/releases/download/\(payload.tagName)/\(asset.name)" else {
                throw CheckError.unexpectedOrigin
            }
            if asset.name.hasPrefix("Cellar-") {
                guard asset.name.hasPrefix("Cellar-\(version.rawValue)-") else { throw CheckError.invalidResponse }
                hasDownload = hasDownload || asset.name.hasSuffix(".zip")
            }
        }
        guard hasDownload else { throw CheckError.unsupportedRelease }
        return release
    }

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name, browserDownloadURL = "browser_download_url"
        }
    }
}
