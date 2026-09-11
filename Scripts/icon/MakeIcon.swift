import AppKit
import CoreGraphics

// Draws the Mac Duo app icon at 1024×1024 with Core Graphics.
//
// The mark: a MacBook seen from the side, lid folding forward, with the
// desktop's light staying where it was: a soft glowing sheet still standing
// at the open angle while the glass tilts through it.
//
//   swift Scripts/icon/MakeIcon.swift build/icon/AppIcon-1024.png

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.displayP3)!
guard let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// macOS icon canvas: the artwork sits inside a rounded square that fills
// 824 of the 1024 points, matching Apple's template grid.
let inset = 100.0
let canvas = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let corner = canvas.width * 0.2237
let squircle = CGPath(roundedRect: canvas, cornerWidth: corner, cornerHeight: corner, transform: nil)

// Drop shadow like the system's own icons.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: rgb(0, 0, 0, 0.35))
context.addPath(squircle)
context.setFillColor(rgb(0.07, 0.08, 0.16))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(squircle)
context.clip()

// Background: night sky at the top into warm dusk at the hinge.
let background = CGGradient(colorsSpace: space, colors: [
    rgb(0.05, 0.06, 0.16), rgb(0.12, 0.10, 0.30), rgb(0.42, 0.20, 0.36), rgb(0.93, 0.55, 0.36),
] as CFArray, locations: [0, 0.45, 0.78, 1])!
context.drawLinearGradient(background, start: CGPoint(x: size / 2, y: canvas.maxY), end: CGPoint(x: size / 2, y: canvas.minY), options: [])

// A pool of light low on the canvas, where the desktop's colour gathers.
let pool = CGGradient(colorsSpace: space, colors: [rgb(1, 0.78, 0.55, 0.75), rgb(1, 0.6, 0.45, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(pool, startCenter: CGPoint(x: size * 0.52, y: canvas.minY + 120), startRadius: 0,
                           endCenter: CGPoint(x: size * 0.52, y: canvas.minY + 120), endRadius: 420, options: [])

// Geometry of the MacBook, side view. Hinge on the left, base to the right.
let hinge = CGPoint(x: size * 0.30, y: size * 0.36)
let baseLength = size * 0.46
let lidLength = size * 0.50
let thickness = size * 0.052

func lidPath(angleDegrees: Double, length: Double, thickness: Double) -> CGPath {
    let a = angleDegrees * .pi / 180
    var t = CGAffineTransform(translationX: hinge.x, y: hinge.y).rotated(by: a)
    let rect = CGRect(x: 0, y: -thickness / 2, width: length, height: thickness)
    return CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: &t)
}

// The frozen desktop: the light that stays where the lid was. Drawn as a
// translucent sheet at the open angle with a bright edge.
context.saveGState()
let ghostAngle = 108.0
let sheet = lidPath(angleDegrees: ghostAngle, length: lidLength * 1.02, thickness: thickness * 2.6)
context.addPath(sheet)
context.clip()
let a = ghostAngle * .pi / 180
let sheetEnd = CGPoint(x: hinge.x + cos(a) * lidLength, y: hinge.y + sin(a) * lidLength)
let sheetGradient = CGGradient(colorsSpace: space, colors: [rgb(1, 0.86, 0.70, 0.95), rgb(0.95, 0.65, 0.75, 0.45), rgb(0.55, 0.55, 1.0, 0.0)] as CFArray, locations: [0, 0.55, 1])!
context.drawLinearGradient(sheetGradient, start: hinge, end: sheetEnd, options: [])
context.restoreGState()

// Soft bloom around the sheet.
context.saveGState()
context.setShadow(offset: .zero, blur: 90, color: rgb(1, 0.75, 0.6, 0.55))
context.addPath(lidPath(angleDegrees: ghostAngle, length: lidLength * 0.9, thickness: thickness * 0.9))
context.setFillColor(rgb(1, 0.85, 0.7, 0.35))
context.fillPath()
context.restoreGState()

// Base.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0, 0, 0, 0.35))
let base = CGPath(roundedRect: CGRect(x: hinge.x - thickness * 0.15, y: hinge.y - thickness / 2, width: baseLength, height: thickness),
                  cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
context.addPath(base)
context.setFillColor(rgb(0.86, 0.87, 0.92))
context.fillPath()
context.restoreGState()
// Base top highlight.
context.saveGState()
context.addPath(base)
context.clip()
let baseSheen = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1, 0.9), rgb(0.7, 0.72, 0.8, 0.0)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(baseSheen, start: CGPoint(x: 0, y: hinge.y + thickness / 2), end: CGPoint(x: 0, y: hinge.y - thickness / 2), options: [])
context.restoreGState()

// Lid, folding forward to 62°: frosted glass with the desktop's light in it.
let lidAngle = 62.0
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0, 0, 0, 0.4))
context.addPath(lidPath(angleDegrees: lidAngle, length: lidLength, thickness: thickness))
context.setFillColor(rgb(0.92, 0.93, 0.97))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(lidPath(angleDegrees: lidAngle, length: lidLength, thickness: thickness))
context.clip()
let la = lidAngle * .pi / 180
let lidEnd = CGPoint(x: hinge.x + cos(la) * lidLength, y: hinge.y + sin(la) * lidLength)
let lidGradient = CGGradient(colorsSpace: space, colors: [rgb(1.0, 0.82, 0.66), rgb(0.96, 0.90, 0.95), rgb(0.80, 0.84, 1.0)] as CFArray, locations: [0, 0.5, 1])!
context.drawLinearGradient(lidGradient, start: hinge, end: lidEnd, options: [])
// Glass edge highlight along the front face.
let edge = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1, 0.85), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
let normal = CGPoint(x: -sin(la), y: cos(la))
context.drawLinearGradient(edge, start: CGPoint(x: hinge.x + normal.x * thickness / 2, y: hinge.y + normal.y * thickness / 2),
                           end: CGPoint(x: hinge.x - normal.x * thickness / 2, y: hinge.y - normal.y * thickness / 2), options: [])
context.restoreGState()

// Hinge cap.
context.setFillColor(rgb(0.55, 0.57, 0.66))
context.fillEllipse(in: CGRect(x: hinge.x - thickness * 0.42, y: hinge.y - thickness * 0.42, width: thickness * 0.84, height: thickness * 0.84))
context.setFillColor(rgb(0.95, 0.96, 1.0))
context.fillEllipse(in: CGRect(x: hinge.x - thickness * 0.22, y: hinge.y - thickness * 0.22, width: thickness * 0.44, height: thickness * 0.44))

// Glass rim on the squircle.
context.restoreGState()
context.saveGState()
context.addPath(squircle)
context.clip()
let rim = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0.0)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(rim, start: CGPoint(x: size / 2, y: canvas.maxY), end: CGPoint(x: size / 2, y: canvas.maxY - 260), options: [])
context.restoreGState()

guard let image = context.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
