import AppKit
import Observation

/// Checks the feed once a day, and on demand from the menu.
@MainActor
@Observable
final class UpdateCoordinator {

    private(set) var available: UpdateInfo?
    private(set) var isChecking = false

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
        alert.informativeText = info.notes ?? "You have \(AppInfo.version). Download the new version from mac-duo.com."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(info.url)
        case .alertThirdButtonReturn:
            preferences.skippedUpdateVersion = info.version
            available = nil
        default:
            break
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
