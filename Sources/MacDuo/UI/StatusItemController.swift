import AppKit
import DuoCore

/// The menu bar item and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let preferences: Preferences
    private let controller: FoldController
    private let windows: WindowCoordinator
    private let updates: UpdateCoordinator
    private var refreshTimer: Timer?
    private var lastGlyph: (angle: Int, active: Bool) = (-1, false)

    private let statusLine = NSMenuItem()
    private let enableItem = NSMenuItem(title: "Enable Mac Duo", action: #selector(toggleEnabled), keyEquivalent: "")
    private let previewItem = NSMenuItem(title: "Preview Fold", action: #selector(preview), keyEquivalent: "p")
    private let styleMenu = NSMenu(title: "Style")
    private let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Allow Screen Recording…", action: #selector(openPermission), keyEquivalent: "")
    private let liveItem = NSMenuItem(title: "Live Picture", action: #selector(toggleLive), keyEquivalent: "")
    private let wakeItem = NSMenuItem(title: "Focus on Wake", action: #selector(toggleWake), keyEquivalent: "")
    private let angleItem = NSMenuItem(title: "Show Angle in Menu Bar", action: #selector(toggleAngle), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var startRow: MenuSliderRow!
    private var frostRow: MenuSliderRow!
    private var darkRow: MenuSliderRow!

    init(preferences: Preferences, controller: FoldController, windows: WindowCoordinator, updates: UpdateCoordinator) {
        self.preferences = preferences
        self.controller = controller
        self.windows = windows
        self.updates = updates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        statusItem.menu = menu
        statusItem.button?.image = MenuBarGlyph.image()
        statusItem.button?.imagePosition = .imageLeading
        refresh()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        for item in [enableItem, previewItem] {
            item.target = self
            menu.addItem(item)
        }
        previewItem.keyEquivalentModifierMask = [.command, .shift]

        let style = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        for preset in EffectPreset.allCases {
            let item = NSMenuItem(title: preset.title, action: #selector(choosePreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            styleMenu.addItem(item)
        }
        styleMenu.addItem(.separator())
        let custom = NSMenuItem(title: "Custom…", action: #selector(openEffectSettings), keyEquivalent: "")
        custom.target = self
        styleMenu.addItem(custom)
        style.submenu = styleMenu
        menu.addItem(style)

        // The three knobs people reach for most, right in the menu.
        startRow = MenuSliderRow(title: "Starts at", value: preferences.effect.startAngle, range: 40...125, step: 1,
                                 format: { String(format: "%.0f°", $0) }) { [weak self] value in
            self?.preferences.effect.startAngle = value
        }
        frostRow = MenuSliderRow(title: "Frost", value: preferences.effect.blurRadius, range: 16...180, step: 2,
                                 format: { String(format: "%.0f pt", $0) }) { [weak self] value in
            self?.preferences.effect.blurRadius = value
        }
        darkRow = MenuSliderRow(title: "Darkness", value: preferences.effect.dimming, range: 0...1, step: 0.05,
                                format: { String(format: "%.0f%%", $0 * 100) }) { [weak self] value in
            self?.preferences.effect.dimming = value
        }
        for row in [startRow!, frostRow!, darkRow!] {
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }
        menu.addItem(.separator())

        for item in [liveItem, wakeItem, angleItem, loginItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        permissionItem.target = self
        menu.addItem(permissionItem)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        updateItem.target = self
        menu.addItem(updateItem)
        let about = NSMenuItem(title: "About Mac Duo", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Mac Duo", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let status = controller.status
        let angle = String(format: "%.0f°", controller.angle)
        switch status {
        case .noSensor:
            statusLine.title = "No lid angle sensor on this Mac"
        case .needsPermission:
            statusLine.title = "Screen Recording access needed"
        case .off:
            statusLine.title = "Mac Duo is off  ·  \(angle)"
        case .ready:
            statusLine.title = controller.isActive ? "Folding  ·  \(angle)" : "Ready  ·  \(angle)"
        }
        enableItem.state = preferences.isEnabled ? .on : .off
        enableItem.isEnabled = status != .noSensor
        startRow.set(value: preferences.effect.startAngle)
        frostRow.set(value: preferences.effect.blurRadius)
        darkRow.set(value: preferences.effect.dimming)
        liveItem.state = preferences.effect.livePicture ? .on : .off
        wakeItem.state = preferences.focusOnWake ? .on : .off
        angleItem.state = preferences.showsAngleInMenuBar ? .on : .off
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        for item in [liveItem, wakeItem, angleItem] { item.isEnabled = status != .noSensor }
        previewItem.isEnabled = status == .ready || status == .off
        permissionItem.isHidden = status != .needsPermission
        let current = preferences.preset
        for item in styleMenu.items {
            guard let raw = item.representedObject as? String, let preset = EffectPreset(rawValue: raw) else {
                if item.title == "Custom…" { item.state = current == nil ? .on : .off }
                continue
            }
            item.state = preset == current ? .on : .off
        }
        if let update = updates.available {
            updateItem.title = "Update to \(update.version)…"
        } else {
            updateItem.title = updates.isChecking ? "Checking for Updates…" : "Check for Updates…"
        }
        updateItem.isEnabled = !updates.isChecking
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let angle = Int(controller.angle.rounded())
        let active = controller.isActive
        if lastGlyph.angle != angle || lastGlyph.active != active {
            lastGlyph = (angle, active)
            button.image = MenuBarGlyph.image(angle: controller.sensorAvailable ? controller.angle : 108, active: active)
        }
        let title = preferences.showsAngleInMenuBar && controller.sensorAvailable ? String(format: " %.0f°", controller.angle) : ""
        if button.title != title { button.title = title }
        button.appearsDisabled = !preferences.isEnabled || controller.status == .noSensor
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        preferences.isEnabled.toggle()
    }

    @objc private func preview() {
        controller.preview()
    }

    @objc private func choosePreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = EffectPreset(rawValue: raw) else { return }
        preferences.apply(preset)
    }

    @objc private func toggleLive() { preferences.effect.livePicture.toggle() }
    @objc private func toggleWake() { preferences.focusOnWake.toggle() }
    @objc private func toggleAngle() { preferences.showsAngleInMenuBar.toggle() }
    @objc private func toggleLogin() { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }

    @objc private func openEffectSettings() {
        windows.showSettings(tab: .effect)
    }

    @objc private func openSettings() {
        windows.showSettings()
    }

    @objc private func openAbout() {
        windows.showSettings(tab: .about)
    }

    @objc private func openPermission() {
        windows.showOnboarding()
    }

    @objc private func checkForUpdates() {
        if let update = updates.available {
            updates.offer(update)
        } else {
            Task { await updates.check(interactive: true) }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
