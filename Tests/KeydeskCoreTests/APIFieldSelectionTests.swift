import Foundation
import Testing
import KeydeskCore

struct APIFieldSelectionTests {
    private func request(field: String? = "/services/openai/token", provider: String? = "OpenAI", url: String = "https://api.openai.com/v1/models") -> APIRequest {
        APIRequest(project: "Synthetic documents", environment: .development, variable: "SETTINGS", method: "GET", url: url, field: field, provider: provider)
    }

    @Test func selectedFieldArgumentsRoundTripWithoutValuesAndLegacyRequestsStillDecode() throws {
        let args = ["--project", "Synthetic documents", "--key", "SETTINGS", "--field", "/services/openai/token", "--provider", "OpenAI", "--url", "https://api.openai.com/v1/models"]
        let selected = try APIRequestParser.parse(args, bodyReader: { _ in "{}" })
        #expect(selected == request())
        #expect(try JSONDecoder().decode(APIRequest.self, from: JSONEncoder().encode(selected)) == selected)
        let legacy = Data(#"{"kind":"api-request","project":"Synthetic documents","environment":"dev","variable":"SETTINGS","method":"GET","url":"https://api.openai.com/v1/models"}"#.utf8)
        let decoded = try JSONDecoder().decode(APIRequest.self, from: legacy)
        #expect(decoded.field == nil && decoded.provider == nil)
        _ = try decoded.validated()
        for extra in [["--field", "/other"], ["--provider", "GitHub"], ["--field"]] {
            #expect(throws: (any Error).self) { try APIRequestParser.parse(args + extra, bodyReader: { _ in "{}" }) }
        }
    }

    @Test func pointersAndProvidersMustBeExplicitAndFixed() throws {
        #expect(try APIProvider.resolve(provider: "Other", request: request()).name == "OpenAI")
        #expect(try APIProvider.resolve(provider: "OpenAI", request: request(provider: nil)).name == "OpenAI")
        #expect(try APIProvider.resolve(provider: "OpenAI", request: request(provider: " openai ")).name == "OpenAI")
        for invalid in [request(field: nil), request(field: "token"), request(field: "/bad~2name"), request(provider: "Custom"), request(provider: "https://evil.invalid"), request(url: "https://api.openai.com.evil.invalid/v1/models")] {
            #expect(throws: (any Error).self) { try APIProvider.resolve(provider: "Other", request: invalid) }
        }
        #expect(throws: (any Error).self) { try APIProvider.resolve(provider: "Other", request: request(provider: nil)) }
        #expect(throws: (any Error).self) { try APIProvider.resolve(provider: "GitHub", request: request()) }
        #expect(throws: (any Error).self) { try APIProvider.resolve(provider: "Custom", request: request()) }
        _ = try request(field: "/a~1b/~0token").validated()
    }

    @Test func changingSelectedFieldOrServiceCannotReuseAnApproval() {
        let credentialID = UUID(), versionID = UUID(), now = Date()
        var approvals = APIApprovalCache()
        let original = request()
        approvals.remember(original, credentialID: credentialID, versionID: versionID, now: now)
        for changed in [request(field: "/services/openai/other"), request(provider: "GitHub"), request(field: nil, provider: nil)] {
            #expect(changed.fingerprint != original.fingerprint)
            #expect(approvals.consume(changed, credentialID: credentialID, versionID: versionID, now: now) == nil)
        }
        #expect(approvals.consume(original, credentialID: credentialID, versionID: UUID(), now: now) == nil)
        #expect(approvals.consume(original, credentialID: credentialID, versionID: versionID, now: now) != nil)
    }
}
