import AppKit
import SwiftUI

enum SettingsTab: String, Hashable, CaseIterable {
    case general, effect, advanced, about
}

/// Opens and reuses the app's windows.
@MainActor
final class WindowCoordinator {

    private let preferences: Preferences
    private let controller: FoldController
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let selectedTab = SettingsSelection()

    init(preferences: Preferences, controller: FoldController) {
        self.preferences = preferences
        self.controller = controller
    }

    func showSettings(tab: SettingsTab = .general) {
        selectedTab.tab = tab
        if settingsWindow == nil {
            let root = SettingsView(preferences: preferences, controller: controller, selection: selectedTab)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Mac Duo"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarAppearsTransparent = false
            window.isReleasedWhenClosed = false
            window.toolbarStyle = .preference
            window.setContentSize(NSSize(width: 520, height: 560))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let root = OnboardingView(preferences: preferences, controller: controller) { [weak self] in
                self?.onboardingWindow?.close()
            }
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to Mac Duo"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 520))
            window.center()
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
@Observable
final class SettingsSelection {
    var tab: SettingsTab = .general
}
