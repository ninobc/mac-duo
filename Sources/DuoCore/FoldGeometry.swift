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

    /// Where the four corners of the frozen picture land on the glass when the
    /// lid is at `angle`. Order: bottom-left, bottom-right, top-right, top-left.
    ///
    /// At `angle == startAngle` this is exactly the screen rectangle. As the
    /// lid folds towards the eye the glass covers less of the room, so the
    /// picture's far edge climbs past the top of the glass and its sides draw
    /// in: the picture holds still and the glass slides down over it.
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
        let eye = (x: width / 2,
                   y: centre.y + normal.y * reach + up.y * lift,
                   z: centre.z + normal.z * reach + up.z * lift)

        // Glass plane through the hinge with normal n(lid).
        let n = (y: -cos(lid), z: sin(lid))
        let nDotEye = n.y * eye.y + n.z * eye.z

        func project(_ px: Double, _ ph: Double) -> ScreenPoint {
            // Picture point in the room.
            let q = (x: px, y: ph * sin(pic), z: ph * cos(pic))
            let d = (x: q.x - eye.x, y: q.y - eye.y, z: q.z - eye.z)
            let nDotD = n.y * d.y + n.z * d.z
            // Ray eye + t·d meets the glass where n·p = 0.
            let t: Double
            if abs(nDotD) < 1e-9 {
                t = 1
            } else {
                t = -nDotEye / nDotD
            }
            // A picture point behind the eye would flip; hold it at the eye.
            let clamped = max(t, 1e-3)
            let hit = (x: eye.x + clamped * d.x, y: eye.y + clamped * d.y, z: eye.z + clamped * d.z)
            let along = hit.y * sin(lid) + hit.z * cos(lid)
            return ScreenPoint(x: hit.x, y: along)
        }

        return [
            project(0, 0),
            project(width, 0),
            project(width, height),
            project(0, height),
        ]
    }
}
