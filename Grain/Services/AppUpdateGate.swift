import Foundation
import os

private let gateLogger = Logger(subsystem: "social.grain.grain", category: "AppUpdateGate")

/// What `/app-version.json` says about iOS: the oldest build the server still
/// supports, and where to send someone running one older than that.
struct AppVersionPolicy: Equatable {
    static let fallbackStoreURL = URL(string: "https://apps.apple.com/app/id6747730230")!

    /// `nil` means the server sets no minimum.
    let minimumBuild: Int?
    let storeURL: URL

    init(minimumBuild: Int?, storeURL: URL = Self.fallbackStoreURL) {
        self.minimumBuild = minimumBuild
        self.storeURL = storeURL
    }

    private struct Document: Decodable {
        struct Platform: Decodable {
            let minimumBuild: Int?
            let storeUrl: String?
        }

        let ios: Platform?
    }

    /// Reads the document, or returns `nil` when it isn't one: not JSON, not an
    /// object, or a field of the wrong type. A missing `ios` key or
    /// `minimumBuild` is a valid document with no minimum.
    static func parse(_ data: Data) -> AppVersionPolicy? {
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else {
            return nil
        }
        let storeURL = document.ios?.storeUrl.flatMap { URL(string: $0) }.flatMap { url in
            url.scheme == "https" || url.scheme == "itms-apps" ? url : nil
        }
        return AppVersionPolicy(
            minimumBuild: document.ios?.minimumBuild,
            storeURL: storeURL ?? fallbackStoreURL
        )
    }

    /// Whether a build is too old to use. A build number that couldn't be read
    /// never blocks: the gate exists to stop old builds, not to strand one it
    /// can't place.
    func blocks(build: Int?) -> Bool {
        guard let build, let minimumBuild else { return false }
        return build < minimumBuild
    }
}

/// The last policy fetched, so a blocked build stays blocked when it launches
/// offline.
enum AppVersionPolicyCache {
    private static let minimumBuildKey = "appVersion.ios.minimumBuild"
    private static let storeURLKey = "appVersion.ios.storeUrl"

    static func load(from defaults: UserDefaults = StorageEnvironment.defaults) -> AppVersionPolicy? {
        guard let minimumBuild = defaults.object(forKey: minimumBuildKey) as? Int else { return nil }
        let storeURL = defaults.string(forKey: storeURLKey).flatMap { URL(string: $0) }
        return AppVersionPolicy(minimumBuild: minimumBuild, storeURL: storeURL ?? AppVersionPolicy.fallbackStoreURL)
    }

    static func store(_ policy: AppVersionPolicy, in defaults: UserDefaults = StorageEnvironment.defaults) {
        if let minimumBuild = policy.minimumBuild {
            defaults.set(minimumBuild, forKey: minimumBuildKey)
            defaults.set(policy.storeURL.absoluteString, forKey: storeURLKey)
        } else {
            defaults.removeObject(forKey: minimumBuildKey)
            defaults.removeObject(forKey: storeURLKey)
        }
    }
}

/// Decides whether this build may run, from the server's minimum when it can
/// be fetched and from the last one fetched when it can't.
///
/// Starts from the cached policy so the decision is made before any request,
/// and never waits on the network to let the app open.
@Observable
@MainActor
final class AppUpdateGate {
    private(set) var isUpdateRequired: Bool
    private(set) var storeURL: URL

    private let currentBuild: Int?
    private let endpoint: URL
    private let session: URLSession
    private var isChecking = false

    nonisolated static let timeout: TimeInterval = 5

    /// `CFBundleVersion`, which Xcode Cloud sets to its build counter.
    nonisolated static var runningBuild: Int? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0) }
    }

    init(
        currentBuild: Int? = AppUpdateGate.runningBuild,
        serverURL: URL = AuthManager.serverURL,
        session: URLSession = NetworkEnvironment.session
    ) {
        self.currentBuild = currentBuild
        endpoint = serverURL.appendingPathComponent("app-version.json")
        self.session = session
        let cached = AppVersionPolicyCache.load()
        isUpdateRequired = cached?.blocks(build: currentBuild) ?? false
        storeURL = cached?.storeURL ?? AppVersionPolicy.fallbackStoreURL
    }

    /// Fetches the policy and applies it. A failed request or an unreadable
    /// document leaves the current decision, which came from the cache, alone.
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let policy = await fetch() else { return }
        AppVersionPolicyCache.store(policy)
        apply(policy)
    }

    func apply(_ policy: AppVersionPolicy) {
        isUpdateRequired = policy.blocks(build: currentBuild)
        storeURL = policy.storeURL
    }

    private func fetch() async -> AppVersionPolicy? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = Self.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                gateLogger.info("[check] unexpected response")
                return nil
            }
            guard let policy = AppVersionPolicy.parse(data) else {
                gateLogger.info("[check] unreadable document")
                return nil
            }
            return policy
        } catch {
            gateLogger.info("[check] failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
