import AppKit
import Observation

/// Checks the feed once a day, and on demand from the menu.
@MainActor
@Observable
final class UpdateCoordinator {

    private(set) var available: UpdateInfo?
    private(set) var isChecking = false
    private(set) var isDownloading = false

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let checker = UpdateChecker()

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func checkOnLaunchIfDue() {
        guard preferences.checksForUpdates else { return }
        if let last = preferences.lastUpdateCheck, Date().timeIntervalSince(last) < 20 * 60 * 60 { return }
        Task { await check(interactive: false) }
    }

    func check(interactive: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        let result = await checker.check()
        isChecking = false
        preferences.lastUpdateCheck = Date()
        switch result {
        case .available(let info):
            if !interactive, preferences.skippedUpdateVersion == info.version { return }
            available = info
            if interactive { offer(info) }
        case .upToDate:
            available = nil
            if interactive { tell("You're up to date", "\(AppInfo.name) \(AppInfo.version) is the latest version.") }
        case .failed(let reason):
            if interactive { tell("Couldn't check for updates", reason) }
        }
    }

    func offer(_ info: UpdateInfo) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) \(info.version) is available"
        var text = "You have \(AppInfo.version)."
        if let notes = info.notes, !notes.isEmpty { text += "\n\n" + notes.prefix(600) }
        alert.informativeText = text
        alert.addButton(withTitle: "Download and Open")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await download(info) }
        case .alertThirdButtonReturn:
            preferences.skippedUpdateVersion = info.version
            available = nil
        default:
            break
        }
    }

    /// Fetches the disk image into Downloads and opens it, so the new copy
    /// is one drag away. Anything that is not a DMG just opens in the browser.
    private func download(_ info: UpdateInfo) async {
        guard info.url.pathExtension.lowercased() == "dmg" else {
            NSWorkspace.shared.open(info.url)
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            var request = URLRequest(url: info.url)
            request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
            let (temporary, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let destination = downloads.appendingPathComponent("Mac-Duo-\(info.version).dmg")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            FileLog.write("app", "downloaded update \(info.version) to \(destination.path)")
            NSWorkspace.shared.open(destination)
        } catch {
            FileLog.write("app", "update download failed: \(error)")
            tell("Couldn't download the update", "Opening the download page instead.")
            NSWorkspace.shared.open(AppInfo.downloadPage)
        }
    }

    private func tell(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
