import AppKit
import Metal
import MetalPerformanceShaders
import QuartzCore
import simd
import DuoCore
import os

private let log = Logger(subsystem: "com.mac-duo.app", category: "render")

/// The per-frame look, everything the shader needs beyond the picture.
public struct FrameParameters {
    public var corners: [ScreenPoint]
    public var blurStrength: Double
    public var dimStrength: Double
    public var blurFloor: Double
    public var maxDim: Double
    public var dimStart: Double
    public var maxBlurRadius: Double
    public var visibleTop: Double
    public var sheenAmount: Double
    public var sheenPosition: Double
    public var grain: Double
    public var time: Double

    public init(corners: [ScreenPoint], blurStrength: Double, dimStrength: Double, blurFloor: Double, maxDim: Double,
                dimStart: Double, maxBlurRadius: Double, visibleTop: Double, sheenAmount: Double, sheenPosition: Double,
                grain: Double, time: Double) {
        self.corners = corners; self.blurStrength = blurStrength; self.dimStrength = dimStrength
        self.blurFloor = blurFloor; self.maxDim = maxDim; self.dimStart = dimStart; self.maxBlurRadius = maxBlurRadius
        self.visibleTop = visibleTop; self.sheenAmount = sheenAmount; self.sheenPosition = sheenPosition
        self.grain = grain; self.time = time
    }

    /// The whole look for one frame, derived from the settings and the lid.
    public static func make(effect: EffectSettings, screenSize: CGSize, angle: Double, progressOverride: Double? = nil,
                            flat: Bool = false, time: Double) -> FrameParameters {
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        let curve = FoldCurve(startAngle: effect.startAngle, span: effect.span)
        let progress = progressOverride ?? curve.progress(at: angle)
        let corners: [ScreenPoint]
        if flat {
            corners = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: width, y: 0), ScreenPoint(x: width, y: height), ScreenPoint(x: 0, y: height)]
        } else {
            let geometry = FoldGeometry(screenWidth: width, screenHeight: height, startAngle: effect.startAngle,
                                        eyeDistance: effect.eyeDistance, depth: effect.depth)
            corners = geometry.corners(at: angle)
        }
        // How much of the picture the glass still shows at its top edge.
        let inverse = Homography.matrix(width: width, height: height, to: corners).inverse
        let topCentre = Homography.apply(inverse, to: ScreenPoint(x: width / 2, y: height))
        let visibleTop = min(max(topCentre.y / max(height, 1), 0.2), 1)
        // The sheen swells in the middle of the fold and crosses the frost.
        let envelope = 4 * progress * (1 - progress)
        return FrameParameters(
            corners: corners,
            blurStrength: curve.blurStrength(progress: progress),
            dimStrength: curve.dimStrength(progress: progress),
            blurFloor: effect.blurFloor,
            maxDim: effect.dimming,
            dimStart: effect.dimStart,
            maxBlurRadius: effect.blurRadius,
            visibleTop: visibleTop,
            sheenAmount: effect.sheen * 0.16 * pow(envelope, 1.5),
            sheenPosition: 0.15 + 0.75 * progress,
            grain: effect.grain,
            time: time
        )
    }
}

/// Draws the fold with Metal. The picture sits on a black margin inside one
/// mipmapped texture; each frame is one full-screen pass.
@MainActor
public final class DuoRenderer {

    /// Black margin around the picture in points. Kept above the widest blur
    /// so the frost runs out to true black on every side.
    nonisolated public static let padding: CGFloat = 176

    private struct Uniforms {
        var column0: SIMD4<Float>
        var column1: SIMD4<Float>
        var column2: SIMD4<Float>
        var screenAndOrigin: SIMD4<Float>
        var paddedAndBlur: SIMD4<Float>
        var shape: SIMD4<Float>
        var light: SIMD4<Float>
        var extra: SIMD4<Float>
    }

    public struct Picture {
        let texture: MTLTexture
        let colourSpace: CGColorSpace
        let screenSize: CGSize
        let pixelScale: CGFloat
        let maxLevel: Float
    }

    public private(set) var layer = CAMetalLayer()
    nonisolated public let device: MTLDevice
    nonisolated private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private var texture: MTLTexture?
    private var screenSize: CGSize = .zero
    private var pixelScale: CGFloat = 2
    private var paddedSize: CGSize = .zero
    private var maxLevel: Float = 0

    private var liveTexture: MTLTexture?
    private var liveSize: CGSize = .zero
    private var liveScale: CGFloat = 0
    private var isLive = false
    private var pendingFrame: MTLTexture?
    private var pendingSeed: (buffer: MTLBuffer, width: Int, height: Int)?
    private lazy var pyramid = MPSImageGaussianPyramid(device: device, centerWeight: 0.375)

    public var isReady: Bool { texture != nil }

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: DuoShaders.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "duoVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "duoFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            log.error("pipeline failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        configure(layer)
    }

    public func makeLayer() -> CAMetalLayer {
        let fresh = CAMetalLayer()
        configure(fresh)
        layer = fresh
        return fresh
    }

    private func configure(_ target: CAMetalLayer) {
        target.device = device
        target.pixelFormat = .bgra8Unorm_srgb
        target.framebufferOnly = true
        // An opaque full-screen layer makes the window server treat everything
        // underneath as hidden and apps stop drawing. The shader writes alpha
        // 1 everywhere, so blending gives the same picture.
        target.isOpaque = false
        // The display link paces frames; waiting on the drawable here would
        // block the main thread and halve the rate under a capture stream.
        target.displaySyncEnabled = false
        target.needsDisplayOnBoundsChange = true
    }

    // MARK: Still picture

    /// Builds the padded, mipmapped texture for one still. Off the main thread.
    nonisolated public func makePicture(from image: CGImage, screenSize: CGSize, pixelScale: CGFloat) -> Picture? {
        let padding = Self.padding
        let padded = CGSize(width: screenSize.width + 2 * padding, height: screenSize.height + 2 * padding)
        let width = Int((padded.width * pixelScale).rounded())
        let height = Int((padded.height * pixelScale).rounded())
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        guard let staging = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared) else { return nil }
        let space = CGColorSpace(name: Self.colourSpace) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: staging.contents(), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let inset = padding * pixelScale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: inset, y: inset, width: CGFloat(width) - 2 * inset, height: CGFloat(height) - 2 * inset))

        let levels = Int(floor(log2(Double(max(width, height))))) + 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard var texture = device.makeTexture(descriptor: descriptor),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerRow * height,
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        MPSImageGaussianPyramid(device: device, centerWeight: 0.375)
            .encode(commandBuffer: commands, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
        commands.commit()
        commands.waitUntilCompleted()
        return Picture(texture: texture, colourSpace: space, screenSize: screenSize, pixelScale: pixelScale, maxLevel: Float(levels - 1))
    }

    public func adopt(_ picture: Picture) {
        isLive = false
        texture = picture.texture
        screenSize = picture.screenSize
        pixelScale = picture.pixelScale
        paddedSize = CGSize(width: picture.screenSize.width + 2 * Self.padding, height: picture.screenSize.height + 2 * Self.padding)
        maxLevel = picture.maxLevel
        layer.colorspace = picture.colourSpace
        layer.drawableSize = CGSize(width: picture.screenSize.width * picture.pixelScale, height: picture.screenSize.height * picture.pixelScale)
    }

    // MARK: Live picture

    /// Prepares the live texture. Nothing is drawn until a frame or seed lands.
    @discardableResult
    public func beginLive(screenSize: CGSize, pixelScale: CGFloat) -> Bool {
        let padded = CGSize(width: screenSize.width + 2 * Self.padding, height: screenSize.height + 2 * Self.padding)
        let width = Int((padded.width * pixelScale).rounded())
        let height = Int((padded.height * pixelScale).rounded())
        guard width > 0, height > 0 else { return false }
        if liveTexture == nil || liveSize != padded || liveScale != pixelScale {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: true)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            guard let fresh = device.makeTexture(descriptor: descriptor) else { return false }
            clear(fresh)
            liveTexture = fresh
            liveSize = padded
            liveScale = pixelScale
        }
        texture = nil
        isLive = true
        self.screenSize = screenSize
        self.pixelScale = pixelScale
        paddedSize = padded
        maxLevel = Float(Int(floor(log2(Double(max(width, height))))))
        layer.colorspace = CGColorSpace(name: Self.colourSpace)
        layer.drawableSize = CGSize(width: screenSize.width * pixelScale, height: screenSize.height * pixelScale)
        return true
    }

    /// Starts the live picture from one still; the stream's first frame replaces it.
    @discardableResult
    public func seed(_ image: CGImage) -> Bool {
        guard isLive, liveTexture != nil else { return false }
        let width = Int((screenSize.width * pixelScale).rounded())
        let height = Int((screenSize.height * pixelScale).rounded())
        guard width > 0, height > 0 else { return false }
        let bytesPerRow = width * 4
        guard let staging = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let space = CGColorSpace(name: Self.colourSpace),
              let context = CGContext(data: staging.contents(), width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pendingSeed = (staging, width, height)
        texture = liveTexture
        return true
    }

    public func absorb(_ frame: MTLTexture) {
        guard isLive, liveTexture != nil else { return }
        pendingFrame = frame
        pendingSeed = nil
        texture = liveTexture
    }

    public func endLive() {
        pendingFrame = nil
        pendingSeed = nil
        if isLive { texture = nil }
        isLive = false
        liveTexture = nil
        liveSize = .zero
        liveScale = 0
    }

    public func release() {
        texture = nil
    }

    private func clear(_ target: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
    }

    private func absorbPending(into commands: MTLCommandBuffer) {
        guard var target = liveTexture, pendingFrame != nil || pendingSeed != nil else { return }
        let inset = Int((Self.padding * pixelScale).rounded())
        guard let blit = commands.makeBlitCommandEncoder() else { return }
        if let frame = pendingFrame {
            let width = min(frame.width, target.width - 2 * inset)
            let height = min(frame.height, target.height - 2 * inset)
            if width > 0, height > 0 {
                blit.copy(from: frame, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                          sourceSize: MTLSize(width: width, height: height, depth: 1),
                          to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: inset, y: inset, z: 0))
            }
        } else if let seed = pendingSeed {
            let width = min(seed.width, target.width - 2 * inset)
            let height = min(seed.height, target.height - 2 * inset)
            if width > 0, height > 0 {
                blit.copy(from: seed.buffer, sourceOffset: 0, sourceBytesPerRow: seed.width * 4, sourceBytesPerImage: seed.width * 4 * seed.height,
                          sourceSize: MTLSize(width: width, height: height, depth: 1),
                          to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: inset, y: inset, z: 0))
            }
        }
        pendingFrame = nil
        pendingSeed = nil
        blit.endEncoding()
        _ = pyramid.encode(commandBuffer: commands, inPlaceTexture: &target, fallbackCopyAllocator: nil)
        liveTexture = target
        texture = target
    }

    // MARK: Frame

    /// Draws one frame to the layer.
    public func render(_ p: FrameParameters) {
        guard let commands = queue.makeCommandBuffer() else { return }
        absorbPending(into: commands)
        guard let texture, screenSize.width > 0, screenSize.height > 0, let drawable = layer.nextDrawable() else {
            commands.commit()
            return
        }
        encode(p, texture: texture, target: drawable.texture, into: commands)
        commands.present(drawable)
        commands.commit()
    }

    /// Draws one frame into a texture and waits for it. For tools and tests.
    public func renderOffscreen(_ p: FrameParameters) -> MTLTexture? {
        guard let commands = queue.makeCommandBuffer() else { return nil }
        absorbPending(into: commands)
        guard let texture, screenSize.width > 0, screenSize.height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Int(screenSize.width * pixelScale), height: Int(screenSize.height * pixelScale), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor) else { return nil }
        encode(p, texture: texture, target: target, into: commands)
        commands.commit()
        commands.waitUntilCompleted()
        return target
    }

    private func encode(_ p: FrameParameters, texture: MTLTexture, target: MTLTexture, into commands: MTLCommandBuffer) {
        let forward = Homography.matrix(width: Double(screenSize.width), height: Double(screenSize.height), to: p.corners)
        let inverse = forward.inverse
        func column(_ i: Int) -> SIMD4<Float> {
            let c = inverse[i]
            return SIMD4(Float(c.x), Float(c.y), Float(c.z), 0)
        }
        var uniforms = Uniforms(
            column0: column(0), column1: column(1), column2: column(2),
            screenAndOrigin: SIMD4(Float(screenSize.width), Float(screenSize.height), Float(-Self.padding), Float(-Self.padding)),
            paddedAndBlur: SIMD4(Float(paddedSize.width), Float(paddedSize.height), Float(p.maxBlurRadius * Double(pixelScale)), Float(p.blurStrength)),
            shape: SIMD4(Float(p.blurFloor), Float(p.maxDim), Float(pixelScale), maxLevel),
            light: SIMD4(Float(p.dimStart), Float(p.dimStrength), Float(p.visibleTop), Float(p.sheenAmount)),
            extra: SIMD4(Float(p.sheenPosition), Float(p.grain), Float(p.time.truncatingRemainder(dividingBy: 1000)), 0)
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// The colour space live frames and stills are handed over in. Display P3
    /// shares sRGB's transfer curve, so the sRGB texture view decodes it.
    nonisolated public static let colourSpace = CGColorSpace.displayP3
}
