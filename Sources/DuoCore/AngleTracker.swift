import Foundation

/// Turns raw sensor readings into a velocity and a short-term prediction.
///
/// The sensor refreshes about every 100 ms, so a fast close can be a full
/// refresh ahead of the last reading. The prediction lets the effect start
/// where the lid actually is.
public struct AngleTracker: Sendable {

    public private(set) var angle: Double = 0
    /// Degrees per second. Negative while closing.
    public private(set) var velocity: Double = 0
    public private(set) var lastChange: TimeInterval = 0
    /// The last time the lid was moving down at least `closingSpeed`.
    public private(set) var lastClosing: TimeInterval = -.infinity
    public private(set) var lastOpening: TimeInterval = -.infinity

    private var lastAngle: Double?
    private var hasSample = false

    /// Speed that counts as deliberate movement. A still lid reads under 0.5.
    public var closingSpeed: Double = 2
    /// Below this speed no prediction is applied.
    public var predictionFloor: Double = 40
    /// Latency added to the reading's age when predicting.
    public var sensorLatency: TimeInterval = 0.04

    public init() {}

    public mutating func reset(to angle: Double, at time: TimeInterval) {
        self.angle = angle
        velocity = 0
        lastAngle = angle
        lastChange = time
        lastClosing = -.infinity
        lastOpening = -.infinity
        hasSample = true
    }

    public mutating func ingest(_ reading: Double, at time: TimeInterval) {
        angle = reading
        guard hasSample, let previous = lastAngle else {
            lastAngle = reading
            lastChange = time
            hasSample = true
            return
        }
        if reading != previous {
            let dt = time - lastChange
            if dt > 0.001 {
                let instant = (reading - previous) / dt
                velocity = 0.5 * instant + 0.5 * velocity
            }
            lastAngle = reading
            lastChange = time
        } else if time - lastChange > 0.4 {
            velocity = 0
        }
        if velocity <= -closingSpeed { lastClosing = time }
        if velocity >= closingSpeed { lastOpening = time }
    }

    public func predictedAngle(at time: TimeInterval) -> Double {
        guard velocity < -predictionFloor else { return angle }
        let age = min(max(time - lastChange, 0), 0.12)
        return angle + velocity * (age + sensorLatency)
    }

    public func isClosing(at time: TimeInterval, within memory: TimeInterval) -> Bool {
        time - lastClosing < memory
    }
}
