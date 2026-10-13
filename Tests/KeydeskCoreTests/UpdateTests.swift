import Foundation
import Testing
@testable import KeydeskCore

struct UpdateTests {
    @Test func comparesNumericComponentsAndPrereleases() throws {
        let ordered = ["0.7.8-alpha", "0.7.8-alpha.2", "0.7.8-alpha.10", "0.7.8-beta", "0.7.8-rc.1", "0.7.8", "0.7.9", "0.7.10", "0.10.0", "1.0.0"]
        let versions = try ordered.map(AppRelease.Version.init)
        for index in 1..<versions.count { #expect(versions[index - 1] < versions[index]) }
        #expect(try AppRelease.Version("0.7.8+build.1") == AppRelease.Version("0.7.8+build.2"))
        #expect(try AppRelease.Version("0.7.8-alpha.999999999999999999999999") < AppRelease.Version("0.7.8-alpha.1000000000000000000000000"))
    }

    @Test func rejectsMalformedVersions() {
        for value in ["", "v0.7.8", "0.7", "0.7.8.1", "00.7.8", "0.-7.8", "0.7.8-", "0.7.8-alpha..1", "0.7.8-01", "0.7.8+", "0.7.8+x+y", "0.7.8/evil", "0.7.8-한글", "18446744073709551616.0.0"] {
            #expect(throws: AppRelease.CheckError.invalidVersion) { try AppRelease.Version(value) }
        }
    }

    @Test func parsesOfficialReleaseAndComparesInstalledVersions() throws {
        let release = try parse(fixture())
        #expect(release.version.rawValue == "0.7.8")
        #expect(release.pageURL.absoluteString == "https://github.com/kohana-dev/keydesk/releases/tag/v0.7.8")
        #expect(try release.version > AppRelease.Version("0.7.7"))
        #expect(try release.version == AppRelease.Version("0.7.8"))
        #expect(try release.version < AppRelease.Version("0.7.9"))
        #expect(try release.version > AppRelease.Version("0.7.8-rc.1"))
    }

    @Test func rejectsUntrustedResponseAndReleaseURLs() throws {
        for responseURL in ["https://api.github.com/repos/other/keydesk/releases/latest", "https://api.github.com/repos/kohana-dev/keydesk/releases/latest?token=secret", "https://example.com/repos/kohana-dev/keydesk/releases/latest", "http://api.github.com/repos/kohana-dev/keydesk/releases/latest"] {
            #expect(throws: AppRelease.CheckError.unexpectedOrigin) {
                try AppRelease.parse(data: fixture(), statusCode: 200, responseURL: URL(string: responseURL), mimeType: "application/json")
            }
        }
        for pageURL in ["https://evil.example/release", "https://github.com.evil.example/kohana-dev/keydesk/releases/tag/v0.7.8", "https://github.com/other/keydesk/releases/tag/v0.7.8", "https://github.com/kohana-dev/keydesk/releases/tag/v0.7.7", "https://github.com/kohana-dev/keydesk/releases/tag/v0.7.8?token=evil", "https://user:pass@github.com/kohana-dev/keydesk/releases/tag/v0.7.8"] {
            #expect(throws: AppRelease.CheckError.unexpectedOrigin) { try parse(fixture(pageURL: pageURL)) }
        }
    }

    @Test func rejectsHostileOrMismatchedAssets() throws {
        for assetURL in ["https://evil.example/Cellar-0.7.8-macOS-arm64.zip", "http://github.com/kohana-dev/keydesk/releases/download/v0.7.8/Cellar-0.7.8-macOS-arm64.zip", "https://github.com/other/keydesk/releases/download/v0.7.8/Cellar-0.7.8-macOS-arm64.zip", "https://github.com/kohana-dev/keydesk/releases/download/v0.7.7/Cellar-0.7.8-macOS-arm64.zip", "https://github.com/kohana-dev/keydesk/releases/download/v0.7.8/Cellar-0.7.8-macOS-arm64.zip?redirect=evil"] {
            #expect(throws: AppRelease.CheckError.unexpectedOrigin) { try parse(fixture(assetURL: assetURL)) }
        }
        #expect(throws: AppRelease.CheckError.invalidResponse) {
            try parse(fixture(assetName: "Cellar-0.7.7-macOS-arm64.zip", assetURL: "https://github.com/kohana-dev/keydesk/releases/download/v0.7.8/Cellar-0.7.7-macOS-arm64.zip"))
        }
        #expect(throws: AppRelease.CheckError.unexpectedOrigin) {
            try parse(fixture(assetName: "../Cellar-0.7.8.zip", assetURL: "https://github.com/kohana-dev/keydesk/releases/download/v0.7.8/../Cellar-0.7.8.zip"))
        }
    }

    @Test func rejectsDraftPrereleaseAndUnfinishedRelease() throws {
        #expect(throws: AppRelease.CheckError.unsupportedRelease) { try parse(fixture(draft: true)) }
        #expect(throws: AppRelease.CheckError.unsupportedRelease) { try parse(fixture(prerelease: true)) }
        #expect(throws: AppRelease.CheckError.unsupportedRelease) { try parse(fixture(tag: "v0.7.8-rc.1")) }
        #expect(throws: AppRelease.CheckError.unsupportedRelease) { try parse(fixture(tag: "0.7.8")) }
        #expect(throws: AppRelease.CheckError.unsupportedRelease) { try parse(fixture(includeAsset: false)) }
    }

    @Test func boundsResponseAndHandlesHTTPFailures() throws {
        #expect(throws: AppRelease.CheckError.oversizedResponse) { try parse(Data(repeating: 32, count: AppRelease.maximumResponseBytes + 1)) }
        #expect(throws: AppRelease.CheckError.invalidResponse) { try parse(Data("not JSON".utf8)) }
        #expect(throws: AppRelease.CheckError.invalidResponse) {
            try AppRelease.parse(data: fixture(), statusCode: 200, responseURL: AppRelease.latestAPIURL, mimeType: "text/html")
        }
        for (status, expected) in [(403, AppRelease.CheckError.rateLimited), (429, .rateLimited), (404, .notFound), (503, .serverUnavailable), (302, .httpFailure), (401, .httpFailure)] {
            #expect(throws: expected) {
                try AppRelease.parse(data: Data(), statusCode: status, responseURL: AppRelease.latestAPIURL, mimeType: "application/json")
            }
        }
    }

    private func parse(_ data: Data) throws -> AppRelease {
        try AppRelease.parse(data: data, statusCode: 200, responseURL: AppRelease.latestAPIURL, mimeType: "application/json")
    }

    private func fixture(tag: String = "v0.7.8", pageURL: String = "https://github.com/kohana-dev/keydesk/releases/tag/v0.7.8",
                         assetName: String = "Cellar-0.7.8-macOS-arm64.zip",
                         assetURL: String = "https://github.com/kohana-dev/keydesk/releases/download/v0.7.8/Cellar-0.7.8-macOS-arm64.zip",
                         draft: Bool = false, prerelease: Bool = false, includeAsset: Bool = true) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": pageURL, "draft": draft, "prerelease": prerelease,
                                                   "assets": includeAsset ? [["name": assetName, "browser_download_url": assetURL]] : []])
    }
}
