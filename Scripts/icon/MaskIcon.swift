import AppKit

// Fits a square artwork into the macOS icon grid: the art fills the 824 pt
// tile inside a 1024 pt canvas, clipped to the system squircle, with the
// standard soft shadow.
//
//   swift Scripts/icon/MaskIcon.swift <art.png> <out.png>
let args = CommandLine.arguments
let art = NSImage(contentsOfFile: args[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let size = 1024.0, inset = 100.0
let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let squircle = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.2237, cornerHeight: tile.height * 0.2237, transform: nil)
// Shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: CGColor(colorSpace: space, components: [0, 0, 0, 0.35]))
ctx.addPath(squircle); ctx.setFillColor(CGColor(colorSpace: space, components: [0.1, 0.1, 0.2, 1])!); ctx.fillPath()
ctx.restoreGState()
// Art, slightly over-scaled so the model's own rounded corners fall outside the clip.
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let over = 1.06
let drawn = CGRect(x: tile.midX - tile.width * over / 2, y: tile.midY - tile.height * over / 2, width: tile.width * over, height: tile.height * over)
ctx.interpolationQuality = .high
ctx.draw(art, in: drawn)
// Glass rim on the top edge.
let rim = CGGradient(colorsSpace: space, colors: [CGColor(colorSpace: space, components: [1, 1, 1, 0.18])!, CGColor(colorSpace: space, components: [1, 1, 1, 0])!] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(rim, start: CGPoint(x: size / 2, y: tile.maxY), end: CGPoint(x: size / 2, y: tile.maxY - 200), options: [])
ctx.restoreGState()
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
