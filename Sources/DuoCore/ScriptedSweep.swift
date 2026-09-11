import Foundation

/// A pretend lid movement: close, hold, open. Feeds the same path the sensor
/// feeds, so the preview is the real effect.
public struct ScriptedSweep: Sendable {
    public let startedAt: TimeInterval
    public let open: Double
    public let shut: Double
    public var closing: TimeInterval = 1.5
    public var hold: TimeInterval = 0.7
    public var opening: TimeInterval = 0.9

    public init(startedAt: TimeInterval, open: Double, shut: Double) {
        self.startedAt = startedAt
        self.open = open
        self.shut = shut
    }

    public var duration: TimeInterval { closing + hold + opening }

    /// `nil` once the sweep is over.
    public func angle(at time: TimeInterval) -> Double? {
        let t = time - startedAt
        if t < 0 { return open }
        if t < closing {
            return open + (shut - open) * ease(t / closing)
        }
        if t < closing + hold { return shut }
        if t < duration {
            return shut + (open - shut) * ease((t - closing - hold) / opening)
        }
        return nil
    }

    private func ease(_ x: Double) -> Double {
        // Ease in-out, like a hand that starts and stops gently.
        let t = min(max(x, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
