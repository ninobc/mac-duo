import AppKit
import Metal
import QuartzCore
import DuoRender

/// A borderless window above everything, including the menu bar and full
/// screen spaces. Never takes focus, never takes clicks.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MetalHostView: NSView {
    init(layer metalLayer: CALayer, scale: CGFloat) {
        super.init(frame: .zero)
        metalLayer.contentsScale = scale
        self.layer = metalLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}

/// Owns the overlay window for one run of the fold and the renderer behind it.
@MainActor
final class FoldOverlay {

    private var window: OverlayWindow?
    private var fadingWindow: OverlayWindow?
    private var presenceWindow: OverlayWindow?
    private(set) var renderer: DuoRenderer?
    private var triedRenderer = false
    private var buildToken = 0
    private let buildQueue = DispatchQueue(label: "com.mac-duo.picture", qos: .userInteractive)
    private var revealed = false

    private(set) var screenSize: CGSize = .zero
    private(set) var pixelScale: CGFloat = 2

    var isVisible: Bool { window != nil }
    var isPictureReady: Bool { renderer?.isReady ?? false }
    var hostWindow: NSWindow? { window }

    @discardableResult
    func warmUp() -> Bool {
        if !triedRenderer {
            triedRenderer = true
            renderer = DuoRenderer()
        }
        keepPresence()
        return renderer != nil
    }

    /// ScreenCaptureKit only lists applications that own an on-screen window,
    /// and the capture filter has to name this app to leave the overlay out.
    /// A one-point window that draws nothing keeps us on that list.
    private func keepPresence() {
        guard presenceWindow == nil else { return }
        let window = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.alphaValue = 0.004
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.orderFrontRegardless()
        presenceWindow = window
    }

    /// Puts up a window for a live picture. It stays clear until a frame lands.
    @discardableResult
    func showLive(on screen: NSScreen) -> Bool {
        dismiss(animated: false)
        guard warmUp(), let renderer else { return false }
        screenSize = screen.frame.size
        pixelScale = screen.backingScaleFactor
        guard renderer.beginLive(screenSize: screenSize, pixelScale: pixelScale) else { return false }
        buildToken += 1
        makeWindow(on: screen)
        return window != nil
    }

    func absorb(_ frame: MTLTexture) {
        guard window != nil, let renderer else { return }
        renderer.absorb(frame)
        reveal()
    }

    func seed(_ image: CGImage) {
        guard window != nil, let renderer, renderer.seed(image) else { return }
        reveal()
    }

    /// Puts up a window with one still, prepared off the main thread.
    func showStill(_ image: CGImage, on screen: NSScreen, then ready: @escaping @MainActor () -> Void) {
        dismiss(animated: false)
        guard warmUp(), let renderer else { return }
        screenSize = screen.frame.size
        pixelScale = screen.frame.width > 0 ? CGFloat(image.width) / screen.frame.width : screen.backingScaleFactor
        makeWindow(on: screen)
        guard let window else { return }
        buildToken += 1
        let token = buildToken
        let size = screenSize
        let scale = pixelScale
        buildQueue.async { [weak self, weak renderer] in
            guard let renderer else { return }
            let picture = renderer.makePicture(from: image, screenSize: size, pixelScale: scale)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.buildToken == token, self.window === window, let picture else { return }
                    renderer.adopt(picture)
                    ready()
                    self.reveal()
                }
            }
        }
    }

    private func makeWindow(on screen: NSScreen) {
        guard let renderer else { return }
        let view = MetalHostView(layer: renderer.makeLayer(), scale: pixelScale)
        view.frame = NSRect(origin: .zero, size: screenSize)
        view.autoresizingMask = [.width, .height]
        let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        revealed = false
        self.window = window
    }

    private func reveal() {
        guard let window, !revealed, renderer?.isReady == true else { return }
        revealed = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func render(_ parameters: FrameParameters) {
        guard let renderer, renderer.isReady else { return }
        renderer.render(parameters)
    }

    func endLive() {
        renderer?.endLive()
    }

    func dismiss(animated: Bool, duration: TimeInterval = 0.24) {
        closeFading()
        guard let window else { return }
        self.window = nil
        buildToken += 1
        renderer?.release()
        guard animated else {
            window.orderOut(nil)
            window.close()
            return
        }
        fadingWindow = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.fadingWindow === window { self.fadingWindow = nil }
                window.orderOut(nil)
                window.close()
            }
        }
    }

    private func closeFading() {
        guard let fadingWindow else { return }
        self.fadingWindow = nil
        fadingWindow.orderOut(nil)
        fadingWindow.close()
    }
}
