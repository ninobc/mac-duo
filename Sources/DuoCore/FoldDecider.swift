import Foundation

/// The rules for when the fold is on screen. Pure, so it can be tested
/// without a lid.
public struct FoldDecider: Sendable {

    public enum Phase: Sendable, Equatable {
        /// Nothing is happening.
        case idle
        /// The lid is closing towards the start angle: capture is warming up.
        case armed
        /// The fold is on screen.
        case active
    }

    public var startAngle: Double
    /// Degrees above the start angle the lid must open to before release.
    public var hysteresis: Double = 4
    /// Degrees above the start angle where warming up begins.
    public var armCeiling: Double = 70
    /// How long after the last closing movement the fold may still start.
    public var closingMemory: TimeInterval = 1.5
    /// The fold stays up at least this long once started.
    public var minimumDuration: TimeInterval = 0.35

    public private(set) var phase: Phase = .idle
    public private(set) var activatedAt: TimeInterval = -.infinity

    public init(startAngle: Double) {
        self.startAngle = startAngle
    }

    /// Feeds one sample. Returns the phase after it.
    @discardableResult
    public mutating func update(tracker: AngleTracker, enabled: Bool, time: TimeInterval) -> Phase {
        guard enabled else {
            phase = .idle
            return phase
        }
        let angle = tracker.angle
        switch phase {
        case .active:
            if time - activatedAt < minimumDuration { return phase }
            if angle >= startAngle + hysteresis {
                phase = .idle
            }
        case .armed, .idle:
            let closing = tracker.isClosing(at: time, within: closingMemory)
            if closing, tracker.predictedAngle(at: time) <= startAngle {
                phase = .active
                activatedAt = time
            } else if closing, angle <= startAngle + armCeiling {
                phase = .armed
            } else {
                phase = .idle
            }
        }
        return phase
    }

    public mutating func forceIdle() {
        phase = .idle
    }

    public mutating func forceActive(at time: TimeInterval) {
        phase = .active
        activatedAt = time
    }
}
