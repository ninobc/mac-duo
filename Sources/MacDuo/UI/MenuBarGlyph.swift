import AppKit

/// The menu bar mark: a MacBook seen from the side, lid mid-fold, with a
/// second, fainter lid where the picture stays. Drawn as a template so it
/// follows the menu bar's colour.
enum MenuBarGlyph {

    static func image(angle: Double = 108, active: Bool = false) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setLineCap(.round)
            context.setLineJoin(.round)
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let hinge = CGPoint(x: 4.5, y: 3.5)
            let baseLength: CGFloat = 12.5
            let lidLength: CGFloat = 11

            // Base.
            context.setLineWidth(2.2)
            context.move(to: hinge)
            context.addLine(to: CGPoint(x: hinge.x + baseLength, y: hinge.y))
            context.strokePath()

            // The lid, at the live angle. 0° lies on the base, 90° is upright.
            let a = min(max(angle, 5), 135) * .pi / 180
            let tip = CGPoint(x: hinge.x + lidLength * cos(a), y: hinge.y + lidLength * sin(a))
            context.setLineWidth(2.2)
            context.move(to: hinge)
            context.addLine(to: tip)
            context.strokePath()

            // Where the picture stays: a fainter lid, only while folding.
            if active {
                let rest = 108.0 * .pi / 180
                let ghost = CGPoint(x: hinge.x + lidLength * cos(rest), y: hinge.y + lidLength * sin(rest))
                context.setAlpha(0.35)
                context.setLineWidth(1.6)
                context.move(to: hinge)
                context.addLine(to: ghost)
                context.strokePath()
                context.setAlpha(1)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mac Duo"
        return image
    }
}
