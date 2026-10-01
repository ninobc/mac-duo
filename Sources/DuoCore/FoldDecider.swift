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
    /// Degrees the lid must close from where it last rested before capture
    /// warms or a fold starts. A lid left by the start angle wobbles when the
    /// Mac is typed on or swiped across; that is not someone closing it.
    public var minimumTravel: Double = 2
    /// A fold whose lid is back above the start angle shows nothing. Once
    /// the lid has stayed there this long the fold lets go, hysteresis or
    /// not, so the overlay never holds the screen for nothing.
    public var releaseDelay: TimeInterval = 0.6

    public private(set) var phase: Phase = .idle
    public private(set) var activatedAt: TimeInterval = -.infinity
    /// Where the lid rested before its latest closing movement. `nil` until
    /// the next sample, after a reset.
    public private(set) var restAngle: Double?
    private var aboveStartSince: TimeInterval?

    public init(startAngle: Double) {
        self.startAngle = startAngle
    }

    /// Feeds one sample. Returns the phase after it.
    @discardableResult
    public mutating func update(tracker: AngleTracker, enabled: Bool, time: TimeInterval) -> Phase {
        guard enabled else {
            phase = .idle
            restAngle = nil
            return phase
        }
        let angle = tracker.angle
        switch phase {
        case .active:
            if time - activatedAt < minimumDuration { return phase }
            if angle >= startAngle + hysteresis {
                release(at: angle)
            } else if angle > startAngle {
                let since = aboveStartSince ?? time
                aboveStartSince = since
                if time - since >= releaseDelay { release(at: angle) }
            } else {
                aboveStartSince = nil
            }
        case .armed, .idle:
            let closing = tracker.isClosing(at: time, within: closingMemory)
            // The rest angle follows the lid until it starts closing, then
            // holds the highest point of the movement.
            let rest = closing ? max(restAngle ?? angle, angle) : angle
            restAngle = rest
            let predicted = tracker.predictedAngle(at: time)
            let travelled = rest - min(angle, predicted) >= minimumTravel
            if closing, travelled, predicted <= startAngle {
                phase = .active
                activatedAt = time
                aboveStartSince = nil
            } else if closing, travelled, angle <= startAngle + armCeiling {
                phase = .armed
            } else {
                phase = .idle
            }
        }
        return phase
    }

    private mutating func release(at angle: Double) {
        phase = .idle
        restAngle = angle
        aboveStartSince = nil
    }

    public mutating func forceIdle() {
        phase = .idle
        restAngle = nil
        aboveStartSince = nil
    }

    public mutating func forceActive(at time: TimeInterval) {
        phase = .active
        activatedAt = time
        aboveStartSince = nil
    }
}
