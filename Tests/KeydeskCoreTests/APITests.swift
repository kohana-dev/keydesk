import Testing
import Foundation
import KeydeskCore

struct APITests {
    func request(method: String = "GET", url: String = "https://api.cloudflare.com/client/v4/user/tokens/verify", body: String? = nil, environment: EnvironmentName = .production) -> APIRequest {
        APIRequest(project: "fixture", environment: environment, variable: "CLOUDFLARE_API_TOKEN", method: method, url: url, body: body)
    }
    @Test func onlyFixedProviderOriginIsAllowed() throws {
        #expect(try APIProvider.resolve(provider: "Cloudflare", request: request()).name == "Cloudflare")
        #expect(throws: (any Error).self) { try APIProvider.resolve(provider: "OpenAI", request: request()) }
        for url in ["http://api.cloudflare.com/", "https://api.cloudflare.com.evil.test/", "https://evil.test/", "https://api.cloudflare.com:444/", "https://user@api.cloudflare.com/", "https://api.cloudflare.com/#fragment", "https://127.0.0.1/", "https://[::1]/", "https://api.cloudflare.com/a/../b", "https://api.cloudflare.com/%2e%2e/b", "https://api.cloudflare.com/a%2fb", "https://api.cloudflare.com/\nheader"] {
            #expect(throws: (any Error).self) { try APIProvider.resolve(provider: "Cloudflare", request: request(url: url)) }
        }
    }
    @Test func bodiesAndCLIArgumentsAreBounded() throws {
        #expect(throws: (any Error).self) { try request(body: "{}").validated() }
        #expect(throws: (any Error).self) { try request(method: "POST", body: "invalid").validated() }
        #expect(throws: (any Error).self) { try request(method: "POST", body: "\"" + String(repeating: "x", count: 262144) + "\"").validated() }
        let args = ["--project", "fixture", "--key", "CLOUDFLARE_API_TOKEN", "--env", "prod", "--url", request().url]
        #expect(try APIRequestParser.parse(args, bodyReader: { _ in "{}" }) == request())
        for extra in [["--header", "Authorization: other"], ["--url", "https://evil.test/"], ["--env", "invalid"], ["--method"]] {
            #expect(throws: (any Error).self) { try APIRequestParser.parse(args + extra, bodyReader: { _ in "{}" }) }
        }
    }
    @Test func exactRequestBudgetExpiryAndVersionRevocation() {
        let id = UUID(), version = UUID(), now = Date()
        var cache = APIApprovalCache()
        cache.remember(request(), credentialID: id, versionID: version, now: now)
        #expect(cache.active(now: now).count == 1)
        #expect(cache.consume(request(), credentialID: id, versionID: version, now: now.addingTimeInterval(300)) == nil)
        #expect(cache.consume(request(url: request().url + "?account=other"), credentialID: id, versionID: version, now: now) == nil)
        #expect(cache.consume(request(method: "DELETE"), credentialID: id, versionID: version, now: now) == nil)
        #expect(cache.consume(request(environment: .development), credentialID: id, versionID: version, now: now) == nil)
        #expect(cache.consume(request(), credentialID: UUID(), versionID: version, now: now) == nil)
        #expect(cache.consume(request(), credentialID: id, versionID: UUID(), now: now) == nil)
        for _ in 0..<10 { #expect(cache.consume(request(), credentialID: id, versionID: version, now: now) != nil) }
        #expect(cache.consume(request(), credentialID: id, versionID: version, now: now) == nil)
        #expect(cache.active(now: now).isEmpty)
        cache.remember(request(), credentialID: id, versionID: version, now: now)
        cache.revoke(cache.active(now: now)[0].id)
        #expect(cache.active(now: now).isEmpty)
        cache.remember(request(), credentialID: id, versionID: version, now: now)
        cache.clear(); #expect(cache.active(now: now).isEmpty)
    }
    @Test func changedJSONRequiresApprovalAndGrantDoesNotSlide() {
        let id = UUID(), version = UUID(), now = Date()
        let original = request(method: "POST", body: "{\"amount\":1}")
        var cache = APIApprovalCache(); cache.remember(original, credentialID: id, versionID: version, now: now)
        #expect(cache.consume(request(method: "POST", body: "{\"amount\":2}"), credentialID: id, versionID: version, now: now) == nil)
        #expect(cache.consume(original, credentialID: id, versionID: version, now: now.addingTimeInterval(299)) != nil)
        #expect(cache.active(now: now)[0].expiresAt == now.addingTimeInterval(300))
    }
    @Test func internalAndSpecialIPsAreDenied() {
        for address in ["127.0.0.1", "10.0.0.1", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "255.255.255.255", "198.18.1.1", "192.0.2.1", "198.51.100.1", "203.0.113.1", "2130706433", "0x7f000001", "127.1", "::1", "::ffff:127.0.0.1", "0177.0.0.1"] { #expect(!PublicIPv4.allowed(address)) }
        #expect(PublicIPv4.allowed("1.1.1.1")); #expect(PublicIPv4.allowed("8.8.8.8"))
    }
    @Test func reflectedSecretsAndRedirectsFailClosed() throws {
        let secret = "DISPOSABLE_SECRET_+/"
        for body in [secret, Data(secret.utf8).base64EncodedString(), secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!, Data(secret.utf8).map { String(format: "%02x", $0) }.joined()] {
            #expect(throws: (any Error).self) { try APIResponse(status: 200, body: body).validated(secret: secret) }
        }
        #expect(throws: (any Error).self) { try APIResponse(status: 302, body: "redirect").validated(secret: secret) }
        #expect(throws: (any Error).self) { try APIResponse(status: 200, body: String(repeating: "x", count: 1048577)).validated(secret: secret) }
        #expect(try APIResponse(status: 401, body: "{\"error\":\"invalid token\"}").validated(secret: secret).status == 401)
    }
    @Test func runGrantsExposePerEntryRevocation() throws {
        let command = CLIRequest(project: "fixture", environment: .production, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: nil, variables: ["KEY"])
        let identity = try ExecutableIdentity.capture(command: "/usr/bin/true", directory: "/tmp")
        var cache = DevelopmentApprovalCache(); try cache.remember(command, executable: identity)
        let grant = try #require(cache.active().first)
        #expect(grant.invocation == command && grant.remainingUses == 10)
        cache.revoke(grant.id); #expect(!cache.allows(command, executable: identity))
        let development = CLIRequest(project: "fixture", environment: .development, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: nil, variables: ["KEY"])
        try cache.remember(development, executable: identity)
        let consumed = cache.consume(development, executable: identity)
        #expect(consumed)
        #expect(cache.active().first?.remainingUses == Int.max)
    }
}
