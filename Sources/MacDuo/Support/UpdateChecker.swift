import Foundation
import DuoCore

/// A small JSON feed at mac-duo.com tells the app about newer builds.
///
///     { "version": "1.1.0", "url": "https://mac-duo.com/#download", "notes": "…" }
struct UpdateInfo: Decodable, Equatable {
    let version: String
    let url: URL
    let notes: String?
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case available(UpdateInfo)
    case failed(String)
}

actor UpdateChecker {
    private let feed: URL
    private let current: SemanticVersion

    init(feed: URL = AppInfo.updateFeed, currentVersion: String = AppInfo.version) {
        self.feed = feed
        self.current = SemanticVersion(currentVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    func check() async -> UpdateCheckResult {
        var request = URLRequest(url: feed)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed("The update server did not answer.")
            }
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            guard let latest = SemanticVersion(info.version) else {
                return .failed("The update feed is malformed.")
            }
            return latest > current ? .available(info) : .upToDate
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
