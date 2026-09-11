import Foundation
import QuartzCore
import DuoCore
import LidAngle

/// Polls the sensor and keeps a tracker up to date. Polling speeds up when
/// something is about to happen and slows right down when the lid rests.
@MainActor
final class LidMonitor {

    enum Rate: TimeInterval {
        case resting = 0.25
        case watching = 0.1
        case moving = 0.02
    }

    private let sensor = LidAngleSensor()
    private var timer: Timer?
    private(set) var rate: Rate?
    private(set) var tracker = AngleTracker()
    private var failures = 0

    /// A scripted angle that stands in for the sensor while it runs.
    var override: ((TimeInterval) -> Double?)?

    var isAvailable: Bool { sensor.isAvailable }
    var resolutionLabel: String { sensor.resolution?.label ?? "—" }

    /// Called on every sample with the tracker and the time.
    var onSample: ((AngleTracker, TimeInterval) -> Void)?
    /// Called when the sensor has failed many reads in a row.
    var onFailure: (() -> Void)?

    func start() {
        guard sensor.isAvailable else { return }
        let now = CACurrentMediaTime()
        if let angle = sensor.read() {
            tracker.reset(to: angle, at: now)
        }
        setRate(.resting)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        rate = nil
    }

    func resetBaseline() {
        let now = CACurrentMediaTime()
        if let angle = sensor.read() {
            tracker.reset(to: angle, at: now)
        }
    }

    func setRate(_ wanted: Rate) {
        guard rate != wanted else { return }
        rate = wanted
        timer?.invalidate()
        let timer = Timer(timeInterval: wanted.rawValue, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = wanted.rawValue * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let now = CACurrentMediaTime()
        let reading: Double
        if let override {
            guard let scripted = override(now) else {
                self.override = nil
                resetBaseline()
                return
            }
            reading = scripted
        } else {
            guard let read = sensor.read() else {
                failures += 1
                if failures == 30 {
                    Log.lid.error("sensor failed 30 reads in a row")
                    onFailure?()
                }
                return
            }
            if failures > 0 {
                Log.lid.notice("sensor recovered after \(self.failures) failed reads")
                failures = 0
            }
            reading = read
        }
        tracker.ingest(reading, at: now)
        onSample?(tracker, now)
    }
}
