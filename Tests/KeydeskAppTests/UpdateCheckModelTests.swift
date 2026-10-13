import Foundation
import Testing
import KeydeskCore
@testable import KeydeskApp

@MainActor
struct UpdateCheckModelTests {
    @Test func doesNotFetchAtInitializationAndFetchesOnlyOnCheck() async throws {
        let release = try fixture()
        let counter = FetchCounter()
        let model = UpdateCheckModel(installedVersion: "0.7.7", installedBuild: "28", fetch: {
            await counter.increment()
            return release
        })
        #expect(model.state == .idle)
        #expect(await counter.count == 0)
        #expect(model.installedVersion == "0.7.7")
        #expect(model.installedBuild == "28")
        #expect(model.installationLabel.contains("0.7.7"))
        #expect(model.installationLabel.contains("28"))
        await model.check()
        #expect(await counter.count == 1)
        #expect(model.state == .available(release))
    }

    @Test func distinguishesCurrentNewerPrereleaseAndDevelopmentInstallations() async throws {
        let release = try fixture()
        for version in ["0.7.8", "0.7.9", "0.10.0", "0.7.8+local.1"] {
            let model = UpdateCheckModel(installedVersion: version, installedBuild: "29", fetch: { release })
            await model.check()
            #expect(model.state == .current(release.version))
        }
        let prerelease = UpdateCheckModel(installedVersion: "0.7.8-rc.1", installedBuild: "29", fetch: { release })
        await prerelease.check()
        #expect(prerelease.state == .available(release))
        let developmentVersions: [String?] = [nil, "dev", ""]
        for version in developmentVersions {
            let development = UpdateCheckModel(installedVersion: version, installedBuild: nil, fetch: { release })
            await development.check()
            #expect(development.state == .development(release))
            #expect(!development.installationLabel.isEmpty)
        }
    }

    @Test func mapsTimeoutNetworkAndValidationFailuresWithoutRawErrorData() async {
        let timeout = UpdateCheckModel(installedVersion: "0.7.7", installedBuild: nil, fetch: { throw URLError(.timedOut) })
        await timeout.check()
        #expect(timeout.state == .failed(.timedOut))
        let network = UpdateCheckModel(installedVersion: "0.7.7", installedBuild: nil, fetch: { throw URLError(.notConnectedToInternet) })
        await network.check()
        #expect(network.state == .failed(.network))
        for error in [AppRelease.CheckError.rateLimited, .unexpectedOrigin, .oversizedResponse, .notFound, .serverUnavailable] {
            let model = UpdateCheckModel(installedVersion: "0.7.7", installedBuild: nil, fetch: { throw error })
            await model.check()
            #expect(model.state == .failed(.release(error)))
            #expect(!UpdateCheckModel.Failure.release(error).message.isEmpty)
        }
    }

    @Test func duplicateCheckWhileInFlightStartsOnlyOneFetch() async throws {
        let release = try fixture()
        let gate = FetchGate(release: release)
        let model = UpdateCheckModel(installedVersion: "0.7.7", installedBuild: nil, fetch: { await gate.fetch() })
        let firstCheck = Task { await model.check() }
        for _ in 0..<1_000 {
            if await gate.count == 1 { break }
            await Task.yield()
        }
        #expect(model.state == .checking)
        #expect(await gate.count == 1)
        await model.check()
        #expect(await gate.count == 1)
        await gate.complete()
        await firstCheck.value
        #expect(model.state == .available(release))
    }

    private func fixture() throws -> AppRelease {
        let data = Data(#"{"tag_name":"v0.7.8","html_url":"https://github.com/kohana-dev/keydesk/releases/tag/v0.7.8","draft":false,"prerelease":false,"assets":[{"name":"Cellar-0.7.8-macOS-arm64.zip","browser_download_url":"https://github.com/kohana-dev/keydesk/releases/download/v0.7.8/Cellar-0.7.8-macOS-arm64.zip"}]}"#.utf8)
        return try AppRelease.parse(data: data, statusCode: 200, responseURL: AppRelease.latestAPIURL, mimeType: "application/json")
    }

    private actor FetchCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private actor FetchGate {
        private(set) var count = 0
        private var continuation: CheckedContinuation<Void, Never>?
        private let release: AppRelease

        init(release: AppRelease) { self.release = release }

        func fetch() async -> AppRelease {
            count += 1
            await withCheckedContinuation { continuation = $0 }
            return release
        }

        func complete() {
            continuation?.resume()
            continuation = nil
        }
    }
}
