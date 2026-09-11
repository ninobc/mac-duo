import AppKit
import CoreGraphics

// The Mac Duo app icon, drawn with Core Graphics.
//
// The mark: a screen folding towards you. The lower half stays crisp and
// white (the desktop that holds still); the upper half bends forward and
// turns to frosted light, peach at the crease into lavender at the top.
//
//   swift Scripts/icon/MakeIcon.swift build/icon/AppIcon-1024.png

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.displayP3)!
guard let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
func gradient(_ stops: [(CGColor, Double)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.0 } as CFArray, locations: stops.map { CGFloat($0.1) })!
}

// The macOS icon grid: an 824 pt squircle inside the 1024 pt canvas.
let inset = 100.0
let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.2237, cornerHeight: tile.height * 0.2237, transform: nil)

// System-style shadow.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: rgb(0, 0, 0, 0.35))
context.addPath(squircle)
context.setFillColor(rgb(0.10, 0.10, 0.28))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(squircle)
context.clip()

// Background: deep indigo up top, violet below, a warm breath at the bottom.
context.drawLinearGradient(
    gradient([(rgb(0.13, 0.13, 0.42), 0), (rgb(0.24, 0.16, 0.52), 0.55), (rgb(0.40, 0.22, 0.56), 1)]),
    start: CGPoint(x: size / 2, y: tile.maxY), end: CGPoint(x: size / 2, y: tile.minY), options: [])
context.drawRadialGradient(
    gradient([(rgb(0.95, 0.55, 0.40, 0.55), 0), (rgb(0.95, 0.55, 0.40, 0), 1)]),
    startCenter: CGPoint(x: size / 2, y: tile.minY + 150), startRadius: 0,
    endCenter: CGPoint(x: size / 2, y: tile.minY + 150), endRadius: 420, options: [])

// The sheet. Lower panel: a rounded rectangle. Upper panel: bent towards the
// viewer, so it reads wider at the top (perspective) and shorter.
let sheetWidth = 400.0
let crease = 505.0                       // y of the fold
let bottom = crease - 260.0              // bottom edge of the lower panel
let lowerRect = CGRect(x: size / 2 - sheetWidth / 2, y: bottom, width: sheetWidth, height: crease - bottom)
let flare = 46.0                         // how much wider the folded top is
let lidHeight = 232.0
let corner = 44.0

// Glow behind the whole sheet.
context.saveGState()
context.setShadow(offset: .zero, blur: 70, color: rgb(1, 0.80, 0.65, 0.55))
context.setFillColor(rgb(1, 0.85, 0.75, 0.25))
context.fill(CGRect(x: lowerRect.minX + 20, y: bottom + 40, width: sheetWidth - 40, height: crease - bottom + lidHeight - 60))
context.restoreGState()

// Upper, folded panel path: a trapezoid with rounded top corners.
let lid = CGMutablePath()
let topY = crease + lidHeight
let l0 = CGPoint(x: lowerRect.minX, y: crease)
let r0 = CGPoint(x: lowerRect.maxX, y: crease)
let l1 = CGPoint(x: lowerRect.minX - flare, y: topY)
let r1 = CGPoint(x: lowerRect.maxX + flare, y: topY)
lid.move(to: l0)
lid.addLine(to: r0)
lid.addLine(to: CGPoint(x: r1.x, y: r1.y - corner))
lid.addQuadCurve(to: CGPoint(x: r1.x - corner, y: r1.y), control: r1)
lid.addLine(to: CGPoint(x: l1.x + corner, y: l1.y))
lid.addQuadCurve(to: CGPoint(x: l1.x, y: l1.y - corner), control: l1)
lid.closeSubpath()

// Lower panel, with a soft shadow cast by the lid onto it.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0.05, 0.03, 0.2, 0.45))
let lowerPath = CGPath(roundedRect: lowerRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
context.addPath(lowerPath)
context.setFillColor(rgb(0.98, 0.98, 1.0))
context.fillPath()
context.restoreGState()
// Square off the lower panel's top corners so it meets the crease flush.
context.setFillColor(rgb(0.98, 0.98, 1.0))
context.fill(CGRect(x: lowerRect.minX, y: crease - corner, width: sheetWidth, height: corner))
// Lower panel shading: bright near the crease, a touch cooler at the bottom,
// with the lid's shadow just under the fold.
context.saveGState()
context.addPath(lowerPath)
context.addRect(CGRect(x: lowerRect.minX, y: crease - corner, width: sheetWidth, height: corner))
context.clip()
context.drawLinearGradient(
    gradient([(rgb(0.80, 0.80, 0.92, 0.9), 0), (rgb(0.97, 0.97, 1.0, 0), 0.32), (rgb(0.90, 0.92, 1.0, 0.0), 0.7), (rgb(0.86, 0.88, 0.98, 0.9), 1)]),
    start: CGPoint(x: 0, y: crease), end: CGPoint(x: 0, y: bottom), options: [])
context.restoreGState()

// Folded panel: frosted light. Peach at the crease into lavender at the top,
// with a soft bloom so it reads as glass rather than paper.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 8), blur: 26, color: rgb(1, 0.7, 0.55, 0.45))
context.addPath(lid)
context.setFillColor(rgb(1, 0.85, 0.72))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(lid)
context.clip()
context.drawLinearGradient(
    gradient([(rgb(1.0, 0.72, 0.52), 0), (rgb(1.0, 0.82, 0.74), 0.35), (rgb(0.86, 0.80, 0.98), 0.72), (rgb(0.70, 0.74, 1.0), 1)]),
    start: CGPoint(x: 0, y: crease), end: CGPoint(x: 0, y: topY), options: [])
// A band of light crossing the frost.
context.drawLinearGradient(
    gradient([(rgb(1, 1, 1, 0), 0), (rgb(1, 1, 1, 0.55), 0.5), (rgb(1, 1, 1, 0), 1)]),
    start: CGPoint(x: lowerRect.minX - 40, y: crease + 40), end: CGPoint(x: lowerRect.maxX + 40, y: topY - 20), options: [])
// Darken the very top edge slightly, the way the far edge goes dim.
context.drawLinearGradient(
    gradient([(rgb(0.45, 0.40, 0.75, 0), 0.72), (rgb(0.45, 0.40, 0.75, 0.55), 1)]),
    start: CGPoint(x: 0, y: crease), end: CGPoint(x: 0, y: topY), options: [])
context.restoreGState()

// The crease: a thin bright line with a soft shadow below it.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: rgb(0.2, 0.1, 0.4, 0.35))
context.setFillColor(rgb(1, 1, 1, 0.95))
context.fill(CGRect(x: lowerRect.minX, y: crease - 3, width: sheetWidth, height: 6))
context.restoreGState()

// Glass rim on the tile.
context.drawLinearGradient(
    gradient([(rgb(1, 1, 1, 0.20), 0), (rgb(1, 1, 1, 0), 1)]),
    start: CGPoint(x: size / 2, y: tile.maxY), end: CGPoint(x: size / 2, y: tile.maxY - 240), options: [])
context.restoreGState()

guard let image = context.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
