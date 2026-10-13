import Foundation
import Observation
import KeydeskCore

@MainActor @Observable
final class UpdateCheckModel {
    enum State: Equatable {
        case idle
        case checking
        case current(AppRelease.Version)
        case available(AppRelease)
        case development(AppRelease)
        case failed(Failure)
    }

    enum Failure: Equatable {
        case network
        case timedOut
        case release(AppRelease.CheckError)

        var message: String {
            switch self {
            case .network:
                L10n.tr("연결하지 못했습니다. 인터넷 연결을 확인하고 다시 시도하세요.", "Could not connect. Check your internet connection and try again.")
            case .timedOut:
                L10n.tr("확인 시간이 초과됐습니다. 잠시 후 다시 시도하세요.", "The update check timed out. Try again shortly.")
            case .release(.rateLimited):
                L10n.tr("GitHub에서 요청을 제한했습니다. 잠시 후 다시 시도하세요.", "GitHub has limited this request. Try again later.")
            case .release(.notFound):
                L10n.tr("공개 릴리스를 찾지 못했습니다. 잠시 후 다시 시도하세요.", "Could not find a public release. Try again later.")
            case .release(.serverUnavailable), .release(.httpFailure):
                L10n.tr("GitHub에서 릴리스 정보를 가져오지 못했습니다. 잠시 후 다시 시도하세요.", "Could not retrieve the release from GitHub. Try again later.")
            case .release:
                L10n.tr("릴리스 정보를 검증하지 못했습니다. 잠시 후 다시 시도하세요.", "Could not verify the release information. Try again later.")
            }
        }
    }

    let installedVersion: String?
    let installedBuild: String?
    private(set) var state: State
    @ObservationIgnored private let fetch: @Sendable () async throws -> AppRelease

    convenience init(bundle: Bundle = .main, initialState: State = .idle,
         fetch: @escaping @Sendable () async throws -> AppRelease = PublicReleaseFetcher.fetch) {
        self.init(installedVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  installedBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  initialState: initialState, fetch: fetch)
    }

    init(installedVersion: String?, installedBuild: String?, initialState: State = .idle,
         fetch: @escaping @Sendable () async throws -> AppRelease = PublicReleaseFetcher.fetch) {
        self.installedVersion = installedVersion
        self.installedBuild = installedBuild
        state = initialState
        self.fetch = fetch
    }

    var installationLabel: String {
        guard let installedVersion, (try? AppRelease.Version(installedVersion)) != nil else {
            return L10n.tr("개발 빌드 · 버전 정보 없음", "Development build · Version information unavailable")
        }
        if let installedBuild, !installedBuild.isEmpty {
            return L10n.tr("설치된 버전 \(installedVersion) (빌드 \(installedBuild))", "Installed version \(installedVersion) (build \(installedBuild))")
        }
        return L10n.tr("설치된 버전 \(installedVersion)", "Installed version \(installedVersion)")
    }

    /// Called only by the user's button action; no startup or background checks.
    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let release = try await fetch()
            guard let installedVersion, let current = try? AppRelease.Version(installedVersion) else {
                state = .development(release)
                return
            }
            state = release.version > current ? .available(release) : .current(release.version)
        } catch let error as AppRelease.CheckError {
            state = .failed(.release(error))
        } catch let error as URLError {
            state = .failed(error.code == .timedOut ? .timedOut : .network)
        } catch {
            state = .failed(.network)
        }
    }
}

/// An ephemeral, anonymous request to one fixed public endpoint.
private enum PublicReleaseFetcher {
    static func fetch() async throws -> AppRelease {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: AppRelease.latestAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Cellar-update-check", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppRelease.CheckError.invalidResponse }
        guard response.url == AppRelease.latestAPIURL else { throw AppRelease.CheckError.unexpectedOrigin }
        guard response.statusCode == 200 else {
            return try AppRelease.parse(data: Data(), statusCode: response.statusCode, responseURL: response.url, mimeType: response.mimeType)
        }
        guard response.expectedContentLength <= Int64(AppRelease.maximumResponseBytes) else {
            throw AppRelease.CheckError.oversizedResponse
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < AppRelease.maximumResponseBytes else { throw AppRelease.CheckError.oversizedResponse }
            data.append(byte)
        }
        return try AppRelease.parse(data: data, statusCode: response.statusCode, responseURL: response.url, mimeType: response.mimeType)
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
