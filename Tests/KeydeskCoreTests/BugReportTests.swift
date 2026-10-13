import Foundation
import Testing
@testable import KeydeskCore

struct BugReportTests {
    private let metadata = BugReportMetadata(appVersion: "0.7.8", appBuild: "29", operatingSystemVersion: "15.6.1", architecture: "arm64")

    private var draft: BugReportDraft {
        BugReportDraft(title: "Button does not respond", stepsToReproduce: "1. Open Settings\n2. Press the button",
                       expectedResult: "The panel opens", actualResult: "The panel stays closed")
    }

    @Test func metadataDefaultsOffAndPreviewContainsOnlyEnteredFields() throws {
        let input = draft
        #expect(!input.includesMetadata)
        let preview = try input.preview(metadata: metadata, language: .english)
        #expect(preview.title == input.title)
        #expect(preview.body == """
        ## Steps to reproduce
        1. Open Settings
        2. Press the button

        ## Expected result
        The panel opens

        ## Actual result
        The panel stays closed
        """)
        #expect(!preview.body.contains(metadata.appVersion))
        #expect(!preview.body.contains(metadata.operatingSystemVersion))
    }

    @Test func selectedMetadataHasExactlyThePublicAllowlist() throws {
        var input = draft
        input.includesMetadata = true
        let preview = try input.preview(metadata: metadata, language: .english)
        #expect(preview.body.hasSuffix("""
        ## Selected app and system information
        - Cellar: 0.7.8 (build 29)
        - macOS: 15.6.1
        - Architecture: arm64
        """))
        for disallowed in ["hostname", "username", "project", "vault", "credential", "log", "path", "screenshot"] {
            #expect(!preview.body.contains(disallowed))
        }
    }

    @Test func destinationAndEncodedFieldsMatchTheReadOnlyPreview() throws {
        var input = draft
        input.title = "버튼 + A&B? # 문제 🚀"
        input.stepsToReproduce = "첫째 줄 + & = ?\r\n둘째 줄: https://example.invalid/?a=1&b=2"
        input.actualResult = "Unicode café / 한국어 and a literal %20"
        let preview = try input.preview(metadata: metadata, language: .korean)
        let components = try #require(URLComponents(url: preview.destination, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "github.com")
        #expect(components.path == "/kohana-dev/keydesk/issues/new")
        #expect(components.fragment == nil)
        #expect(components.user == nil)
        #expect(components.port == nil)
        #expect(components.queryItems == [URLQueryItem(name: "title", value: preview.title), URLQueryItem(name: "body", value: preview.body)])
        #expect(preview.destination.absoluteString.contains("%2B"))
        #expect(preview.destination.absoluteString.contains("%26"))
        #expect(preview.body.contains("첫째 줄 + & = ?\n둘째 줄"))
        #expect(preview.body.contains("## 재현 방법"))
        #expect(!preview.body.contains("\r"))
    }

    private static let sensitiveSamples: [String] = [
        "sk-" + "proj-fictitioussecret0123456789",
        "ghp_" + "fictitious012345678901234567890123",
        "github_pat_" + "fictitious012345678901234567890",
        "AKIA" + "1234567890ABCDEF",
        "AIza" + "Fictional123456789012345678901234567890",
        "xoxb-" + "123456789012-123456789012-fictional",
        "Authorization: Bearer fictional01234567890123456789",
        "-----BEGIN " + "PRIVATE KEY-----\nfictional\n-----END " + "PRIVATE KEY-----",
        "-----BEGIN RSA " + "PRIVATE KEY-----\nfictional",
        "OPENAI_API_KEY=fictional",
        "export CLIENT_SECRET = 'fictional'",
        "\"ACCESS_TOKEN\": \"fictional\"",
        "RECOVERY_CODE: fictional",
        "01234567-89ABCDEF-01234567-89ABCDEF-01234567-89ABCDEF-01234567-89ABCDEF-01234567",
        String(repeating: "ABCDEF12", count: 9)
    ]

    @Test(arguments: BugReportTests.sensitiveSamples)
    func obviousSecretsAreBlockedBeforeProducingADestination(_ sample: String) {
        var input = draft
        input.actualResult = sample
        #expect(BugReportDraft.containsObviousSensitiveContent(sample))
        #expect(throws: BugReportValidationError.sensitiveContent) {
            try input.preview(metadata: metadata, language: .english)
        }
    }

    @Test func ordinaryBugTextDoesNotTriggerSecretGuard() throws {
        var input = draft
        input.actualResult = "The API key label disappears. No values were copied. The error says connection failed."
        #expect(!BugReportDraft.containsObviousSensitiveContent(input.actualResult))
        _ = try input.preview(metadata: metadata, language: .english)
    }

    @Test func requiredFieldsAndLengthsAreValidatedWithoutTruncatingReviewedText() {
        var missing = draft
        missing.expectedResult = " \n\t "
        #expect(throws: BugReportValidationError.missingFields) {
            try missing.preview(metadata: metadata, language: .english)
        }
        var longTitle = draft
        longTitle.title = String(repeating: "x", count: BugReportDraft.maximumTitleLength + 1)
        #expect(throws: BugReportValidationError.fieldTooLong) {
            try longTitle.preview(metadata: metadata, language: .english)
        }
        var longSteps = draft
        longSteps.stepsToReproduce = String(repeating: "x", count: BugReportDraft.maximumStepsLength + 1)
        #expect(throws: BugReportValidationError.fieldTooLong) {
            try longSteps.preview(metadata: metadata, language: .english)
        }
        var longResult = draft
        longResult.actualResult = String(repeating: "x", count: BugReportDraft.maximumResultLength + 1)
        #expect(throws: BugReportValidationError.fieldTooLong) {
            try longResult.preview(metadata: metadata, language: .english)
        }
    }

    @Test func encodedURLLimitAccountsForUnicodeExpansion() {
        var input = draft
        input.stepsToReproduce = String(repeating: "한", count: BugReportDraft.maximumStepsLength)
        #expect(throws: BugReportValidationError.reportTooLong) {
            try input.preview(metadata: metadata, language: .korean)
        }
    }

    @Test func invisibleControlsAndTitleLineBreaksAreRejected() {
        var input = draft
        input.title = "Misleading\nTitle"
        #expect(throws: BugReportValidationError.unsupportedCharacters) {
            try input.preview(metadata: metadata, language: .english)
        }
        input = draft
        input.actualResult = "hidden\u{202E}text"
        #expect(throws: BugReportValidationError.unsupportedCharacters) {
            try input.preview(metadata: metadata, language: .english)
        }
    }

    @Test func unselectedMetadataIsNeitherRenderedNorValidated() throws {
        let badMetadata = BugReportMetadata(appVersion: "HOST=private", appBuild: "", operatingSystemVersion: "\ninvalid", architecture: "unknown")
        let preview = try draft.preview(metadata: badMetadata, language: .english)
        #expect(!preview.body.contains("HOST"))
        var input = draft
        input.includesMetadata = true
        #expect(throws: BugReportValidationError.invalidMetadata) {
            try input.preview(metadata: badMetadata, language: .english)
        }
    }

    @Test func securityReportsUseTheSeparateFixedPrivateDestination() {
        #expect(BugReportDraft.privateSecurityDestination.absoluteString == "https://github.com/kohana-dev/keydesk/security/advisories/new")
        #expect(BugReportDraft.issueDestination.absoluteString == "https://github.com/kohana-dev/keydesk/issues/new")
    }
}
