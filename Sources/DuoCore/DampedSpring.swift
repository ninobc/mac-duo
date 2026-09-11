import Foundation

/// Follows a stepping target smoothly. The sensor updates about ten times a
/// second; this runs at the display rate and never overshoots.
public struct DampedSpring: Sendable {
    public var value: Double
    public var velocity: Double = 0

    /// Natural frequency in radians per second. Higher hugs the target.
    public var frequency: Double

    public init(value: Double = 0, frequency: Double = 14) {
        self.value = value
        self.frequency = frequency
    }

    /// Semi-implicit Euler; stable while `frequency * dt < 2`.
    public mutating func advance(toward target: Double, dt: Double) {
        let step = min(max(dt, 0), 1.0 / 20)
        let acceleration = frequency * frequency * (target - value) - 2 * frequency * velocity
        velocity += acceleration * step
        value += velocity * step
    }

    public mutating func snap(to target: Double) {
        value = target
        velocity = 0
    }

    public func isSettled(at target: Double, tolerance: Double = 0.01) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 10
    }
}
