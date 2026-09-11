import Foundation
import simd

/// The projective map from the picture rectangle to the quadrilateral it lands
/// on. Column-vector form: `screen = M · (x, y, 1)`, then divide by z.
public enum Homography {

    /// Maps `(0,0)…(width,height)` onto `corners`, ordered bottom-left,
    /// bottom-right, top-right, top-left. Heckbert's square-to-quad, then the
    /// rectangle folded in.
    public static func matrix(width: Double, height: Double, to corners: [ScreenPoint]) -> simd_double3x3 {
        precondition(corners.count == 4, "a quad has four corners")
        let (x0, y0) = (corners[0].x, corners[0].y)
        let (x1, y1) = (corners[1].x, corners[1].y)
        let (x2, y2) = (corners[2].x, corners[2].y)
        let (x3, y3) = (corners[3].x, corners[3].y)

        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3

        var g = 0.0, h = 0.0
        if abs(dx3) > 1e-10 || abs(dy3) > 1e-10 {
            let det = dx1 * dy2 - dx2 * dy1
            if abs(det) > 1e-12 {
                g = (dx3 * dy2 - dx2 * dy3) / det
                h = (dx1 * dy3 - dx3 * dy1) / det
            }
        }
        let a = x1 - x0 + g * x1
        let b = x3 - x0 + h * x3
        let c = x0
        let d = y1 - y0 + g * y1
        let e = y3 - y0 + h * y3
        let f = y0

        return simd_double3x3(columns: (
            SIMD3(a / width, d / width, g / width),
            SIMD3(b / height, e / height, h / height),
            SIMD3(c, f, 1)
        ))
    }

    /// Applies a matrix to a point, with the perspective divide.
    public static func apply(_ m: simd_double3x3, to p: ScreenPoint) -> ScreenPoint {
        let v = m * SIMD3(p.x, p.y, 1)
        return ScreenPoint(x: v.x / v.z, y: v.y / v.z)
    }
}
