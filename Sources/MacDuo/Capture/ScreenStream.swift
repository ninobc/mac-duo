import AppKit
import CoreVideo
import Metal
import ScreenCaptureKit
import DuoRender

/// A live picture of the built-in display as Metal textures. Frames are
/// IOSurface-backed so wrapping them copies nothing.
@MainActor
final class ScreenStream {

    /// Display P3 shares sRGB's transfer curve, so an sRGB texture view decodes it.
    nonisolated static let colourSpace = DuoRenderer.colourSpace

    private final class Receiver: NSObject, SCStreamOutput {
        private let cache: CVMetalTextureCache
        private let lock = NSLock()
        private var newest: CVMetalTexture?
        private var newestID: UInt64 = 0

        init?(device: MTLDevice) {
            var made: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &made) == kCVReturnSuccess,
                  let made else { return nil }
            cache = made
        }

        func latest() -> (texture: MTLTexture, id: UInt64)? {
            lock.lock(); defer { lock.unlock() }
            guard let newest, let texture = CVMetalTextureGetTexture(newest) else { return nil }
            return (texture, newestID)
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
                  let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            CVMetalTextureCacheFlush(cache, 0)
            var wrapped: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, pixels, nil, .bgra8Unorm_srgb,
                CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), 0, &wrapped
            )
            guard result == kCVReturnSuccess, let wrapped else { return }
            lock.lock()
            newest = wrapped
            newestID &+= 1
            lock.unlock()
        }
    }

    private let device: MTLDevice?
    private var stream: SCStream?
    private var receiver: Receiver?
    private var starting: Task<Void, Never>?
    private var filter: SCContentFilter?
    private var filterDisplay: CGDirectDisplayID?
    private var consumed: UInt64 = 0
    private var lastHandOver: CFTimeInterval = 0
    private static let minimumHandOver: CFTimeInterval = 1.0 / 60

    private(set) var isRunning = false

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
    }

    func warm() async {
        guard let id = NSScreen.builtIn?.displayID, filter == nil || filterDisplay != id else { return }
        filter = await ContentFilterBuilder.make(display: id)
        filterDisplay = filter == nil ? nil : id
    }

    func invalidateFilter() {
        filter = nil
        filterDisplay = nil
    }

    func start() {
        guard !isRunning, starting == nil, device != nil else { return }
        guard let screen = NSScreen.builtIn, let id = screen.displayID else { return }
        isRunning = true
        starting = Task { [weak self] in
            await self?.begin(display: id)
            self?.starting = nil
        }
    }

    func stop() {
        guard isRunning || stream != nil else { return }
        isRunning = false
        starting?.cancel()
        starting = nil
        let closing = stream
        stream = nil
        receiver = nil
        consumed = 0
        lastHandOver = 0
        guard let closing else { return }
        Task { try? await closing.stopCapture() }
        Log.capture.debug("stream stopped")
    }

    /// The newest frame, once. `nil` until something new has arrived.
    func takeFrame() -> MTLTexture? {
        let now = CACurrentMediaTime()
        guard now - lastHandOver >= Self.minimumHandOver else { return nil }
        guard let latest = receiver?.latest(), latest.id != consumed else { return nil }
        consumed = latest.id
        lastHandOver = now
        return latest.texture
    }

    private func begin(display id: CGDirectDisplayID) async {
        guard let device, let receiver = Receiver(device: device) else {
            isRunning = false
            return
        }
        if filter == nil || filterDisplay != id {
            filter = await ContentFilterBuilder.make(display: id)
            filterDisplay = filter == nil ? nil : id
        }
        guard isRunning, let filter else {
            isRunning = false
            return
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = Self.colourSpace
        configuration.showsCursor = false
        configuration.queueDepth = 5
        configuration.scalesToFit = false

        let fresh = SCStream(filter: filter, configuration: configuration, delegate: nil)
        do {
            try fresh.addStreamOutput(receiver, type: .screen,
                                      sampleHandlerQueue: DispatchQueue(label: "com.mac-duo.frames", qos: .userInteractive))
            let started = CACurrentMediaTime()
            try await fresh.startCapture()
            guard isRunning else {
                try? await fresh.stopCapture()
                return
            }
            self.receiver = receiver
            self.stream = fresh
            Log.capture.notice("stream started \(configuration.width)x\(configuration.height) in \((CACurrentMediaTime() - started) * 1000, format: .fixed(precision: 0)) ms")
            FileLog.write("capture", String(format: "stream started %dx%d in %.0f ms", configuration.width, configuration.height, (CACurrentMediaTime() - started) * 1000))
        } catch {
            Log.capture.error("stream failed: \(String(describing: error), privacy: .public)")
            FileLog.write("capture", "stream failed: \(error)")
            invalidateFilter()
            isRunning = false
        }
    }
}
