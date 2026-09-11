import Foundation

/// How far along the fold we are, and how strong each part of the look is at
/// that point. Everything is a function of the lid angle, so opening simply
/// runs it backwards.
public struct FoldCurve: Sendable {

    /// The effect starts at this angle and reaches full strength `span`
    /// degrees below it.
    public var startAngle: Double
    public var span: Double

    /// Exponents on the progress. Above 1 starts gently.
    public var blurExponent: Double = 1.6
    public var dimExponent: Double = 0.7

    public init(startAngle: Double, span: Double) {
        self.startAngle = startAngle
        self.span = max(span, 1)
    }

    /// 0 at the start angle, 1 at full strength, linear in the lid angle.
    /// The exponents on blur and dimming shape the feel from there.
    public func progress(at angle: Double) -> Double {
        let raw = (startAngle - angle) / span
        return min(max(raw, 0), 1)
    }

    public func blurStrength(progress: Double) -> Double {
        pow(min(max(progress, 0), 1), blurExponent)
    }

    public func dimStrength(progress: Double) -> Double {
        pow(min(max(progress, 0), 1), dimExponent)
    }

    public static func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
