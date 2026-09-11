import AppKit

@main
@MainActor
enum MacDuoMain {
    /// `NSApplication.delegate` is weak; something has to own it.
    private static var delegate: AppDelegate?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
