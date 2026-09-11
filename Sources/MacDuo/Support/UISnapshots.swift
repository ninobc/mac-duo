import AppKit
import SwiftUI

/// Renders the app's windows to PNG files without showing them, for QA:
///
///     "Mac Duo.app/Contents/MacOS/MacDuo" --render-ui /tmp/ui
///
/// Windows are created off screen and drawn through the view cache, so no
/// Screen Recording access is needed.
@MainActor
enum UISnapshots {

    static func renderIfRequested(preferences: Preferences, controller: FoldController) -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-ui"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        controller.probeSensor()

        let selection = SettingsSelection()
        for tab in SettingsTab.allCases {
            selection.tab = tab
            let view = SettingsView(preferences: preferences, controller: controller, selection: selection)
            snapshot(view, size: NSSize(width: 520, height: 600), to: directory.appendingPathComponent("settings-\(tab.rawValue).png"))
        }
        snapshot(OnboardingView(preferences: preferences, controller: controller, finish: {}),
                 size: NSSize(width: 560, height: 520), to: directory.appendingPathComponent("onboarding-welcome.png"))
        snapshot(OnboardingView(preferences: preferences, controller: controller, finish: {}, initialStep: .permission),
                 size: NSSize(width: 560, height: 520), to: directory.appendingPathComponent("onboarding-permission.png"))
        snapshot(OnboardingView(preferences: preferences, controller: controller, finish: {}, initialStep: .ready),
                 size: NSSize(width: 560, height: 520), to: directory.appendingPathComponent("onboarding-ready.png"))
        snapshot(OnboardingView(preferences: preferences, controller: controller, finish: {}, initialStep: .unsupported),
                 size: NSSize(width: 560, height: 520), to: directory.appendingPathComponent("onboarding-unsupported.png"))

        // The menu's rows, stacked as they appear in the dropdown.
        let stack = NSStackView(views: [
            MenuToggleRow(title: "Mac Duo", isOn: true, emphasised: true, onChange: { _ in }),
            MenuSliderRow(title: "Starts at", value: 100, range: 40...125, step: 1, format: { String(format: "%.0f°", $0) }, onChange: { _ in }),
            MenuSliderRow(title: "Frost", value: 72, range: 16...180, step: 2, format: { String(format: "%.0f pt", $0) }, onChange: { _ in }),
            MenuSliderRow(title: "Darkness", value: 1, range: 0...1, step: 0.05, format: { String(format: "%.0f%%", $0 * 100) }, onChange: { _ in }),
        ])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 172)
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalToConstant: 260).isActive = true }
        snapshotView(stack, to: directory.appendingPathComponent("menu-sliders.png"))

        // The menu bar glyph at a few angles, enlarged.
        for angle in [108.0, 80.0, 50.0] {
            let image = MenuBarGlyph.image(angle: angle, active: angle < 100)
            write(image, scale: 8, to: directory.appendingPathComponent("glyph-\(Int(angle)).png"))
        }
        print("rendered UI to \(directory.path)")
        return true
    }

    private static func snapshot<V: View>(_ view: V, size: NSSize, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        // Two turns of the run loop so SwiftUI finishes its first layout.
        for _ in 0..<3 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
        window.close()
    }

    private static func snapshotView(_ view: NSView, to url: URL) {
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        view.layoutSubtreeIfNeeded()
        for _ in 0..<2 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        window.close()
    }

    private static func write(_ image: NSImage, scale: CGFloat, to url: URL) {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        // Template images draw black; tint like a menu bar item.
        let tinted = image.copy() as! NSImage
        tinted.isTemplate = false
        tinted.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
