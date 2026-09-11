import CoreGraphics
import AppKit

/// Screen Recording, the one permission the fold needs. Without it the
/// capture returns nothing but the wallpaper.
enum ScreenRecordingPermission {

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time. Later calls return the stored
    /// answer without prompting, so the settings pane is the way back in.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
    )!

    @MainActor
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}

/// The Lock Screen pane, for the "require password after" delay that lets
/// the wake reveal play instead of the login window.
enum LockScreenSettings {
    static let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!

    @MainActor
    static func open() {
        NSWorkspace.shared.open(url)
    }
}
