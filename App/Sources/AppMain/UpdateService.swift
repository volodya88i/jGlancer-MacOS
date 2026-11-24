import Foundation
import JGSettings
import Observation

/// Looks for a newer version (D-104): at most once a day, 5 s after the start, it asks GitHub's API for the number and
/// notes of the latest release and offers its page. Nothing is downloaded or installed. A setting turns it off; runs with
/// `-JGDataDirectory` (checks and benchmarks) never look by themselves.
@MainActor
@Observable
final class UpdateService {
    /// A newer release.
    struct Offer: Identifiable {
        let version: AppVersion
        let notes: String
        var id: String {
            version.description
        }

        /// Built from the fixed repository and the checked number, never taken from the answer.
        var page: URL? {
            URL(string: "\(UpdateService.repositoryPage)/releases/tag/v\(version)")
        }
    }

    enum Status: Equatable {
        case idle, checking, upToDate, failed
    }

    nonisolated static let repositoryPage = "https://github.com/volodya88i/jGlancer-MacOS"
    private static let latestRelease = "https://api.github.com/repos/volodya88i/jGlancer-MacOS/releases/latest"
    private static let startDelay: Duration = .seconds(5)

    var offer: Offer?
    private(set) var status = Status.idle
    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    /// The installed version.
    static var installed: AppVersion? {
        let override = UserDefaults.standard.string(forKey: "JGUpdateInstalled")
        return AppVersion(override ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }

    /// From the app's start.
    func scheduleDailyCheck() {
        guard AppPaths.dataOverride == nil, store.settings.checksForUpdates,
              UpdatePolicy.isDue(lastCheck: store.settings.lastUpdateCheck, now: Date())
        else { return }
        Task {
            try? await Task.sleep(for: Self.startDelay)
            guard store.settings.checksForUpdates else { return }
            await check(manual: false)
        }
    }

    /// Asks once. A failed check says nothing unless the user asked (`manual`).
    func check(manual: Bool) async {
        status = .checking
        guard let release = await Self.fetchLatest(), let latest = AppVersion(release.tag), let installed = Self.installed else {
            status = manual ? .failed : .idle
            return
        }
        store.update { $0.lastUpdateCheck = Date() }
        if UpdatePolicy.offer(latest: latest, installed: installed, skipped: store.settings.skippedVersion, manual: manual) {
            status = .idle
            offer = Offer(version: latest, notes: release.body ?? "")
        } else {
            status = manual ? .upToDate : .idle
        }
    }

    func skip(_ offer: Offer) {
        store.update { $0.skippedVersion = offer.version.description }
        self.offer = nil
    }

    /// No cookies or cache, a plain request: GitHub sees the address and the app's name and version, nothing else.
    private static func fetchLatest() async -> Release? {
        guard let url = URL(string: latestRelease) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("jGlancer/\(installed?.description ?? "0")", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder().decode(Release.self, from: data)
    }
}

/// What the update check reads from GitHub's answer.
private struct Release: Decodable {
    let tag: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case body
    }
}
