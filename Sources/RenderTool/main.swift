import AppKit
import DuoCore
import DuoRender
import Metal

/// Renders the fold on an image, for QA and marketing frames.
///
///     duofold <input.png> <output.png> --angle 60 [--preset duo|soft|cinematic] [--scale 2]
///     duofold <input.png> <outdir> --sweep 12        twelve frames from the start angle down
@MainActor
func run() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 2 else {
        FileHandle.standardError.write(Data("usage: duofold <input> <output|outdir> [--angle N] [--preset P] [--scale S] [--sweep N]\n".utf8))
        exit(2)
    }
    let input = arguments.removeFirst()
    let output = arguments.removeFirst()
    var angle = 60.0
    var preset = EffectPreset.duo
    var scale = 2.0
    var sweep = 0
    var index = 0
    while index < arguments.count {
        let flag = arguments[index]
        let value = index + 1 < arguments.count ? arguments[index + 1] : ""
        switch flag {
        case "--angle": angle = Double(value) ?? angle
        case "--preset": preset = EffectPreset(rawValue: value) ?? preset
        case "--scale": scale = Double(value) ?? scale
        case "--sweep": sweep = Int(value) ?? sweep
        default: break
        }
        index += 2
    }

    guard let source = NSImage(contentsOfFile: input)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "duofold", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot read \(input)"])
    }
    guard let renderer = DuoRenderer() else {
        throw NSError(domain: "duofold", code: 2, userInfo: [NSLocalizedDescriptionKey: "no Metal device"])
    }
    let screenSize = CGSize(width: Double(source.width) / scale, height: Double(source.height) / scale)
    guard let picture = renderer.makePicture(from: source, screenSize: screenSize, pixelScale: scale) else {
        throw NSError(domain: "duofold", code: 3, userInfo: [NSLocalizedDescriptionKey: "cannot build picture"])
    }
    renderer.adopt(picture)
    let effect = preset.settings

    func write(angle: Double, to path: String) throws {
        let parameters = FrameParameters.make(effect: effect, screenSize: screenSize, angle: angle, time: 0)
        guard let texture = renderer.renderOffscreen(parameters) else { return }
        let width = texture.width, height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let space = CGColorSpace(name: DuoRenderer.colourSpace)!
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let image = context.makeImage()!
        let rep = NSBitmapImageRep(cgImage: image)
        let data = rep.representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) at \(String(format: "%.1f", angle))°")
    }

    if sweep > 0 {
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        let shut = max(effect.startAngle - effect.span * 1.1, 8)
        for i in 0..<sweep {
            let t = Double(i) / Double(max(sweep - 1, 1))
            let a = effect.startAngle + (shut - effect.startAngle) * t
            try write(angle: a, to: "\(output)/frame-\(String(format: "%02d", i)).png")
        }
    } else {
        try write(angle: angle, to: output)
    }
}

MainActor.assumeIsolated {
    do { try run() } catch {
        FileHandle.standardError.write(Data("duofold: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
