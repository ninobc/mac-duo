import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var preferences: Preferences!
    private var controller: FoldController!
    private var statusItem: StatusItemController!
    private var windows: WindowCoordinator!
    private var updates: UpdateCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences.shared
        self.preferences = preferences
        let controller = FoldController(preferences: preferences)
        self.controller = controller
        if UISnapshots.renderIfRequested(preferences: preferences, controller: controller) {
            NSApp.terminate(nil)
            return
        }
        windows = WindowCoordinator(preferences: preferences, controller: controller)
        updates = UpdateCoordinator(preferences: preferences)
        statusItem = StatusItemController(preferences: preferences, controller: controller, windows: windows, updates: updates)
        controller.start()

        if !preferences.hasCompletedOnboarding || (controller.status == .needsPermission && !preferences.hasCompletedOnboarding) {
            windows.showOnboarding()
        }
        updates.checkOnLaunchIfDue()
        Log.app.notice("launched \(AppInfo.version, privacy: .public) (\(AppInfo.build, privacy: .public))")
        FileLog.write("app", "launched \(AppInfo.version) (\(AppInfo.build)), sensor \(controller.sensorAvailable), screen recording \(ScreenRecordingPermission.isGranted), model \(MacModel.identifier)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings()
        return true
    }
}
