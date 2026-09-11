import Foundation
import DuoCore

/// What a newer build looks like: its version, where its disk image is, and
/// the release notes.
struct UpdateInfo: Decodable, Equatable {
    let version: String
    let url: URL
    let notes: String?
}

/// The shape of GitHub's "latest release" answer, as much as we need.
private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }
    let tag_name: String
    let html_url: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case available(UpdateInfo)
    case failed(String)
}

/// Asks GitHub for the latest release first, since that is where builds are
/// published; falls back to the small feed on mac-duo.com.
actor UpdateChecker {
    private let releases: URL
    private let feed: URL
    private let current: SemanticVersion

    init(releases: URL = AppInfo.latestRelease, feed: URL = AppInfo.updateFeed, currentVersion: String = AppInfo.version) {
        self.releases = releases
        self.feed = feed
        self.current = SemanticVersion(currentVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    func check() async -> UpdateCheckResult {
        if let result = await checkGitHub() { return result }
        return await checkFeed()
    }

    private func request(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func checkGitHub() async -> UpdateCheckResult? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request(releases, accept: "application/vnd.github+json"))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !release.draft, !release.prerelease, let latest = SemanticVersion(release.tag_name) else { return nil }
            let dmg = release.assets.first { $0.name == "Mac-Duo.dmg" }?.browser_download_url
                ?? release.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url
                ?? release.html_url
            let info = UpdateInfo(version: latest.description, url: dmg, notes: release.body?.trimmingCharacters(in: .whitespacesAndNewlines))
            return latest > current ? .available(info) : .upToDate
        } catch {
            return nil
        }
    }

    private func checkFeed() async -> UpdateCheckResult {
        do {
            let (data, response) = try await URLSession.shared.data(for: request(feed, accept: "application/json"))
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
