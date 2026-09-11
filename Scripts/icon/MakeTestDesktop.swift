import AppKit

// Composes a lock-screen style desktop on a wallpaper: menu bar, big clock,
// date. Used for QA renders and the website demo.
//   swift Scripts/icon/MakeTestDesktop.swift <wallpaper.png> <out.png> [light]
let args = CommandLine.arguments
let wallpaperPath = args[1], outPath = args[2]
let light = args.count > 3 && args[3] == "light"
let width = 2560.0, height = 1600.0
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ r: Double,_ g: Double,_ b: Double,_ a: Double = 1) -> CGColor { CGColor(colorSpace: space, components: [r,g,b,a])! }
if light {
    let g = CGGradient(colorsSpace: space, colors: [c(0.80,0.88,1.0), c(0.98,0.90,0.86), c(1.0,0.80,0.62)] as CFArray, locations: [0,0.55,1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: height), end: CGPoint(x: width * 0.3, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
} else if let wp = NSImage(contentsOfFile: wallpaperPath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let scale = max(width / Double(wp.width), height / Double(wp.height))
    let w = Double(wp.width) * scale, h = Double(wp.height) * scale
    ctx.draw(wp, in: CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h))
}
// Menu bar.
ctx.setFillColor(c(0,0,0,light ? 0.08 : 0.18))
ctx.fill(CGRect(x: 0, y: height - 48, width: width, height: 48))
func text(_ s: String, size: Double, weight: NSFont.Weight, at p: CGPoint, alpha: Double = 1, centered: Bool = false) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 1, alpha: alpha)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(line, [])
    ctx.textPosition = CGPoint(x: centered ? p.x - bounds.width / 2 : p.x, y: p.y)
    CTLineDraw(line, ctx)
}
text("", size: 26, weight: .regular, at: CGPoint(x: 34, y: height - 34))
text("Wed Sep 11  9:41 AM", size: 24, weight: .medium, at: CGPoint(x: width - 330, y: height - 33))
// Clock with a soft shadow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: c(0,0,0,0.35))
text("9:41", size: 300, weight: .bold, at: CGPoint(x: width / 2, y: height * 0.62), centered: true)
text("Wednesday, September 11", size: 54, weight: .medium, at: CGPoint(x: width / 2, y: height * 0.62 + 330), centered: true)
ctx.restoreGState()
// A couple of windows, so the frost has structure to soften.
func window(_ r: CGRect, title: String) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: c(0,0,0,0.35))
    let path = CGPath(roundedRect: r, cornerWidth: 22, cornerHeight: 22, transform: nil)
    ctx.addPath(path); ctx.setFillColor(c(0.97,0.97,0.98,0.96)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.setFillColor(c(0.92,0.92,0.94)); ctx.fill(CGRect(x: r.minX, y: r.maxY - 76, width: r.width, height: 76))
    for (i, col) in [c(1,0.38,0.35), c(1,0.74,0.2), c(0.2,0.8,0.35)].enumerated() {
        ctx.setFillColor(col); ctx.fillEllipse(in: CGRect(x: r.minX + 26 + Double(i) * 36, y: r.maxY - 50, width: 24, height: 24))
    }
    let font = NSFont.systemFont(ofSize: 26, weight: .semibold)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor(white: 0.25, alpha: 1)]))
    ctx.textPosition = CGPoint(x: r.minX + 150, y: r.maxY - 47); CTLineDraw(line, ctx)
    for row in 0..<9 {
        ctx.setFillColor(c(0.82,0.83,0.87, row % 2 == 0 ? 1 : 0.6))
        ctx.fill(CGRect(x: r.minX + 40, y: r.maxY - 140 - Double(row) * 58, width: r.width * (0.35 + Double((row * 37) % 50) / 100), height: 22))
    }
    ctx.restoreGState()
}
window(CGRect(x: 140, y: 120, width: 1100, height: 640), title: "Notes")
window(CGRect(x: 1500, y: 200, width: 900, height: 560), title: "Finder")
let img = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
