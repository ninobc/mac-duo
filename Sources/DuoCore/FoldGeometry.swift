import Foundation

/// A point on the lid's glass, in screen points. Origin at the bottom-left,
/// which is the hinge edge; y grows towards the top of the lid.
public struct ScreenPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// The physical model behind the Duo effect.
///
/// The desktop is frozen in the room at the moment the effect starts. The lid
/// keeps turning, and every pixel of the glass shows what a fixed eye would see
/// of that frozen picture *through* the glass. That is the whole trick: the
/// picture holds still while the MacBook folds around it.
///
/// World axes: the hinge runs along x. y is up, z points at the person. A point
/// at height `h` on a lid open to angle `θ` (0° flat on the keyboard, 90°
/// vertical) sits at `(x, h·sinθ, h·cosθ)`. The glass faces `(0, −cosθ, sinθ)`.
public struct FoldGeometry: Sendable {

    /// Width and height of the built-in display in points.
    public var screenWidth: Double
    public var screenHeight: Double

    /// The angle the picture was frozen at.
    public var startAngle: Double

    /// Eye distance from the middle of the screen, in screen heights, measured
    /// along the glass normal at the start angle.
    public var eyeDistance: Double = 2.6

    /// Eye height above the middle of the screen, in screen heights, measured
    /// along the glass at the start angle. People look slightly down at a
    /// laptop, so the default sits a little above centre.
    public var eyeHeight: Double = 0.15

    /// How much of the lid's travel the picture stays behind. 1 keeps it
    /// exactly where it was in the room; 0 lets it ride along with the glass
    /// (no perspective at all); above 1 leans it away harder.
    public var depth: Double = 1

    /// The picture never turns past this far from the glass, so it cannot go
    /// edge-on or behind the eye.
    public var maximumSeparation: Double = 84

    public init(screenWidth: Double, screenHeight: Double, startAngle: Double,
                eyeDistance: Double = 2.6, eyeHeight: Double = 0.15, depth: Double = 1) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.startAngle = startAngle
        self.eyeDistance = eyeDistance
        self.eyeHeight = eyeHeight
        self.depth = depth
    }

    /// Where the frozen picture lands on the glass when the lid is at `angle`.
    /// Order: bottom-left, bottom-right, top-right, top-left.
    ///
    /// At `angle == startAngle` this is exactly the screen rectangle. As the
    /// lid folds towards the eye the glass covers less of the room, so the
    /// picture's far edge climbs past the top of the glass: the picture holds
    /// still and the glass slides down over it. The mapping keeps every
    /// column where it is (no keystone), so the picture always fills the
    /// glass from edge to edge and nothing is cut off at the sides; the
    /// vertical re-projection carries the whole feeling of depth.
    public func corners(at angle: Double) -> [ScreenPoint] {
        let travel = max(startAngle - angle, 0)
        let separation = min(depth * travel, maximumSeparation)
        // The picture sits this far "behind" the glass, measured as a hinge
        // angle. With depth 1 it is the start angle itself.
        let pictureAngle = angle + separation
        let lid = angle * .pi / 180
        let pic = pictureAngle * .pi / 180
        let start = startAngle * .pi / 180

        let width = screenWidth
        let height = screenHeight

        // Eye: in front of the screen centre at the start pose.
        let centre = (y: height / 2 * sin(start), z: height / 2 * cos(start))
        let normal = (y: -cos(start), z: sin(start))
        let reach = eyeDistance * height
        let lift = eyeHeight * height
        let up = (y: sin(start), z: cos(start))
        let eye = (y: centre.y + normal.y * reach + up.y * lift,
                   z: centre.z + normal.z * reach + up.z * lift)

        // Glass plane through the hinge with normal n(lid).
        let n = (y: -cos(lid), z: sin(lid))
        let nDotEye = n.y * eye.y + n.z * eye.z

        /// Height on the glass where the picture point at height `ph` shows.
        func along(_ ph: Double) -> Double {
            let q = (y: ph * sin(pic), z: ph * cos(pic))
            let d = (y: q.y - eye.y, z: q.z - eye.z)
            let nDotD = n.y * d.y + n.z * d.z
            let t = abs(nDotD) < 1e-9 ? 1 : max(-nDotEye / nDotD, 1e-3)
            let hit = (y: eye.y + t * d.y, z: eye.z + t * d.z)
            return hit.y * sin(lid) + hit.z * cos(lid)
        }
        let top = max(along(height), height * 0.5)

        return [
            ScreenPoint(x: 0, y: 0),
            ScreenPoint(x: width, y: 0),
            ScreenPoint(x: width, y: top),
            ScreenPoint(x: 0, y: top),
        ]
    }
}
