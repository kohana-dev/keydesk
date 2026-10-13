import Foundation

/// Only these public diagnostic fields can be included in a bug report.
/// This type deliberately has no access to a vault, logs, files, or user identity.
public struct BugReportMetadata: Equatable, Sendable {
    public let appVersion: String
    public let appBuild: String
    public let operatingSystemVersion: String
    public let architecture: String

    public init(appVersion: String, appBuild: String, operatingSystemVersion: String, architecture: String) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.operatingSystemVersion = operatingSystemVersion
        self.architecture = architecture
    }
}

public struct BugReportDraft: Equatable, Sendable {
    public static let maximumTitleLength = 120
    public static let maximumStepsLength = 1_600
    public static let maximumResultLength = 800
    public static let maximumURLBytes = 8_192
    public static let issueDestination = URL(string: "https://github.com/kohana-dev/keydesk/issues/new")!
    public static let privateSecurityDestination = URL(string: "https://github.com/kohana-dev/keydesk/security/advisories/new")!

    public var title: String
    public var stepsToReproduce: String
    public var expectedResult: String
    public var actualResult: String
    public var includesMetadata: Bool

    public init(title: String = "", stepsToReproduce: String = "", expectedResult: String = "", actualResult: String = "", includesMetadata: Bool = false) {
        self.title = title
        self.stepsToReproduce = stepsToReproduce
        self.expectedResult = expectedResult
        self.actualResult = actualResult
        self.includesMetadata = includesMetadata
    }

    /// Entirely local: returns the exact title and body that will populate GitHub's editor.
    public func preview(metadata: BugReportMetadata, language: AppLanguage) throws -> BugReportPreview {
        let title = normalized(self.title)
        let steps = normalized(stepsToReproduce)
        let expected = normalized(expectedResult)
        let actual = normalized(actualResult)
        let fields = [(title, Self.maximumTitleLength), (steps, Self.maximumStepsLength),
                      (expected, Self.maximumResultLength), (actual, Self.maximumResultLength)]

        guard fields.allSatisfy({ !$0.0.isEmpty }) else { throw BugReportValidationError.missingFields }
        guard fields.allSatisfy({ $0.0.count <= $0.1 }) else { throw BugReportValidationError.fieldTooLong }
        guard !title.contains("\n"), fields.allSatisfy({ !containsUnsupportedControls($0.0) }) else {
            throw BugReportValidationError.unsupportedCharacters
        }
        guard !fields.contains(where: { Self.containsObviousSensitiveContent($0.0) }) else {
            throw BugReportValidationError.sensitiveContent
        }

        var body = """
        ## \(L10n.tr("재현 방법", "Steps to reproduce", language: language))
        \(steps)

        ## \(L10n.tr("예상 결과", "Expected result", language: language))
        \(expected)

        ## \(L10n.tr("실제 결과", "Actual result", language: language))
        \(actual)
        """

        if includesMetadata {
            let values = [metadata.appVersion, metadata.appBuild, metadata.operatingSystemVersion, metadata.architecture]
            guard values.allSatisfy({ !$0.isEmpty && $0.count <= 80 && !$0.contains("\n") && !$0.contains("\r") && !containsUnsupportedControls($0) }) else {
                throw BugReportValidationError.invalidMetadata
            }
            guard !values.contains(where: Self.containsObviousSensitiveContent) else {
                throw BugReportValidationError.sensitiveContent
            }
            body += """


            ## \(L10n.tr("선택한 앱·시스템 정보", "Selected app and system information", language: language))
            - Cellar: \(metadata.appVersion) (\(L10n.tr("빌드", "build", language: language)) \(metadata.appBuild))
            - macOS: \(metadata.operatingSystemVersion)
            - \(L10n.tr("아키텍처", "Architecture", language: language)): \(metadata.architecture)
            """
        }

        var components = URLComponents(url: Self.issueDestination, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        // GitHub reads query strings as form data, where an unescaped '+' becomes a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url, url.absoluteString.utf8.count <= Self.maximumURLBytes else {
            throw BugReportValidationError.reportTooLong
        }
        return BugReportPreview(title: title, body: body, destination: url)
    }

    /// A small local guard for common accidental pastes, never a promise of complete detection.
    public static func containsObviousSensitiveContent(_ text: String) -> Bool {
        sensitivePatterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static let sensitivePatterns = [
        #"(?i)\bsk-[a-z0-9_-]{12,}"#,
        #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"#,
        #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,
        #"\bAIza[A-Za-z0-9_-]{30,}"#,
        #"\bxox[baprs]-[A-Za-z0-9-]{12,}"#,
        #"(?i)\bBearer\s+[a-z0-9_./+=-]{16,}"#,
        #"(?i)-----BEGIN(?: [A-Z0-9]+)* PRIVATE KEY-----"#,
        #"(?im)\b(?:[A-Z0-9_]*API_?KEY[A-Z0-9_]*|[A-Z0-9_]*SECRET[A-Z0-9_]*|[A-Z0-9_]*TOKEN[A-Z0-9_]*|[A-Z0-9_]*PASSWORD[A-Z0-9_]*|[A-Z0-9_]*PASSWD[A-Z0-9_]*|[A-Z0-9_]*PRIVATE_?KEY[A-Z0-9_]*|[A-Z0-9_]*RECOVERY_?(?:KEY|CODE)[A-Z0-9_]*)[\"']?\s*[:=]\s*\S"#,
        #"(?i)\b[0-9a-f]{8}(?:[-\s][0-9a-f]{8}){8}\b"#,
        #"(?i)\b[0-9a-f]{72}\b"#
    ]

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsUnsupportedControls(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (CharacterSet.controlCharacters.contains(scalar) && scalar != "\n" && scalar != "\t") ||
                scalar.properties.generalCategory == .format
        }
    }
}

public struct BugReportPreview: Equatable, Sendable {
    public let title: String
    public let body: String
    public let destination: URL
}

public enum BugReportValidationError: Error, LocalizedError, Equatable {
    case missingFields
    case fieldTooLong
    case reportTooLong
    case sensitiveContent
    case unsupportedCharacters
    case invalidMetadata

    public var errorDescription: String? {
        switch self {
        case .missingFields:
            L10n.tr("제목, 재현 방법, 예상 결과, 실제 결과를 모두 입력하세요.", "Enter a title, steps to reproduce, expected result, and actual result.")
        case .fieldTooLong:
            L10n.tr("입력 길이 제한을 넘었습니다. 표시된 글자 수 안으로 줄이세요.", "An input exceeds its limit. Shorten it to the displayed character limit.")
        case .reportTooLong:
            L10n.tr("브라우저로 전달할 제보가 너무 깁니다. 내용을 줄인 후 다시 확인하세요.", "The report is too long to pass to the browser. Shorten it and review it again.")
        case .sensitiveContent:
            L10n.tr("비밀정보로 보이는 입력을 발견했습니다. API 키, 비밀 환경변수 값, 개인 키, 복구 코드를 제거하세요. 이 검사는 모든 민감정보를 찾지는 못합니다.", "The input appears to contain a secret. Remove API keys, secret environment variable values, private keys, or recovery codes. This check does not detect all sensitive information.")
        case .unsupportedCharacters:
            L10n.tr("제목의 줄바꿈 또는 보이지 않는 제어 문자를 제거하세요.", "Remove title line breaks or invisible control characters.")
        case .invalidMetadata:
            L10n.tr("앱·시스템 정보를 포함할 수 없습니다. 해당 옵션을 끄고 다시 확인하세요.", "App and system information cannot be included. Turn off that option and review again.")
        }
    }
}
