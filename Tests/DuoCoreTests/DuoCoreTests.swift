import XCTest
@testable import DuoCore

final class FoldGeometryTests: XCTestCase {

    func testCornersAtStartAngleAreTheScreen() {
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, startAngle: 100)
        let c = g.corners(at: 100)
        XCTAssertEqual(c[0].x, 0, accuracy: 1e-6); XCTAssertEqual(c[0].y, 0, accuracy: 1e-6)
        XCTAssertEqual(c[1].x, 1512, accuracy: 1e-6); XCTAssertEqual(c[1].y, 0, accuracy: 1e-6)
        XCTAssertEqual(c[2].x, 1512, accuracy: 1e-6); XCTAssertEqual(c[2].y, 982, accuracy: 1e-6)
        XCTAssertEqual(c[3].x, 0, accuracy: 1e-6); XCTAssertEqual(c[3].y, 982, accuracy: 1e-6)
    }

    func testHingeEdgeNeverMoves() {
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, startAngle: 100)
        for angle in stride(from: 100.0, through: 20.0, by: -10) {
            let c = g.corners(at: angle)
            XCTAssertEqual(c[0].y, 0, accuracy: 1e-6, "hinge at \(angle)")
            XCTAssertEqual(c[1].y, 0, accuracy: 1e-6, "hinge at \(angle)")
        }
    }

    func testPictureHoldsStillAndAlwaysFillsTheGlass() {
        // The far edge climbs past the top of the glass; the sides never draw in.
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, startAngle: 100)
        var lastHeight = 0.0
        for angle in stride(from: 100.0, through: 40.0, by: -10) {
            let c = g.corners(at: angle)
            XCTAssertEqual(c[0].x, 0, accuracy: 1e-9); XCTAssertEqual(c[1].x, 1512, accuracy: 1e-9)
            XCTAssertEqual(c[3].x, 0, accuracy: 1e-9); XCTAssertEqual(c[2].x, 1512, accuracy: 1e-9)
            XCTAssertEqual(c[2].y, c[3].y, accuracy: 1e-9, "top edge stays level")
            if angle <= 80 {
                XCTAssertGreaterThanOrEqual(c[2].y, lastHeight - 1e-6, "height at \(angle)")
            }
            lastHeight = c[2].y
        }
        XCTAssertGreaterThan(lastHeight, 982)
    }

    func testZeroDepthKeepsTheScreen() {
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, startAngle: 100, depth: 0)
        let c = g.corners(at: 50)
        XCTAssertEqual(c[2].y, 982, accuracy: 1e-6)
        XCTAssertEqual(c[3].x, 0, accuracy: 1e-6)
    }

    func testHomographyRoundTrips() {
        let g = FoldGeometry(screenWidth: 1512, screenHeight: 982, startAngle: 100)
        let corners = g.corners(at: 60)
        let m = Homography.matrix(width: 1512, height: 982, to: corners)
        let mapped = Homography.apply(m, to: ScreenPoint(x: 1512, y: 982))
        XCTAssertEqual(mapped.x, corners[2].x, accuracy: 1e-6)
        XCTAssertEqual(mapped.y, corners[2].y, accuracy: 1e-6)
        let back = Homography.apply(m.inverse, to: corners[3])
        XCTAssertEqual(back.x, 0, accuracy: 1e-6)
        XCTAssertEqual(back.y, 982, accuracy: 1e-6)
    }
}

final class FoldCurveTests: XCTestCase {
    func testProgressBoundsAndMonotone() {
        let curve = FoldCurve(startAngle: 100, span: 60)
        XCTAssertEqual(curve.progress(at: 120), 0)
        XCTAssertEqual(curve.progress(at: 100), 0)
        XCTAssertEqual(curve.progress(at: 40), 1)
        XCTAssertEqual(curve.progress(at: 10), 1)
        var last = 0.0
        for angle in stride(from: 100.0, through: 40.0, by: -1) {
            let p = curve.progress(at: angle)
            XCTAssertGreaterThanOrEqual(p, last)
            last = p
        }
        XCTAssertEqual(curve.progress(at: 70), 0.5, accuracy: 1e-9)
    }
}

final class DampedSpringTests: XCTestCase {
    func testSettlesWithoutOvershoot() {
        var spring = DampedSpring(value: 100, frequency: 14)
        var minimum = 100.0
        for _ in 0..<600 {
            spring.advance(toward: 60, dt: 1.0 / 120)
            minimum = min(minimum, spring.value)
        }
        XCTAssertEqual(spring.value, 60, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(minimum, 59.99)
        XCTAssertTrue(spring.isSettled(at: 60))
    }
}

final class AngleTrackerTests: XCTestCase {
    func testVelocityAndPrediction() {
        var tracker = AngleTracker()
        tracker.reset(to: 120, at: 0)
        tracker.ingest(110, at: 0.1)
        tracker.ingest(100, at: 0.2)
        XCTAssertLessThan(tracker.velocity, -50)
        XCTAssertTrue(tracker.isClosing(at: 0.25, within: 1))
        XCTAssertLessThan(tracker.predictedAngle(at: 0.3), 100)
    }

    func testStillLidHasNoVelocity() {
        var tracker = AngleTracker()
        tracker.reset(to: 120, at: 0)
        tracker.ingest(110, at: 0.1)
        tracker.ingest(110, at: 0.7)
        XCTAssertEqual(tracker.velocity, 0)
        XCTAssertEqual(tracker.predictedAngle(at: 0.8), 110)
    }
}

final class FoldDeciderTests: XCTestCase {
    func testRestingBelowStartDoesNotActivate() {
        var tracker = AngleTracker()
        tracker.reset(to: 80, at: 0)
        var decider = FoldDecider(startAngle: 100)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 0.1), .idle)
    }

    func testClosingActivatesAndOpeningReleases() {
        var tracker = AngleTracker()
        tracker.reset(to: 130, at: 0)
        var decider = FoldDecider(startAngle: 100)
        tracker.ingest(120, at: 0.1)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 0.1), .armed)
        tracker.ingest(105, at: 0.2)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 0.2), .armed)
        tracker.ingest(95, at: 0.3)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 0.3), .active)
        // Still active just above the start angle (hysteresis).
        tracker.ingest(102, at: 1.0)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 1.0), .active)
        tracker.ingest(106, at: 1.2)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: true, time: 1.2), .idle)
    }

    func testDisabledIsAlwaysIdle() {
        var tracker = AngleTracker()
        tracker.reset(to: 130, at: 0)
        var decider = FoldDecider(startAngle: 100)
        tracker.ingest(90, at: 0.1)
        XCTAssertEqual(decider.update(tracker: tracker, enabled: false, time: 0.1), .idle)
    }
}

final class SemanticVersionTests: XCTestCase {
    func testParsingAndOrder() {
        XCTAssertEqual(SemanticVersion("1.2.3")?.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("v2.0")?.description, "2.0.0")
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertTrue(SemanticVersion("1.0.9")! < SemanticVersion("1.1.0")!)
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.9")!)
    }
}

final class PresetTests: XCTestCase {
    func testPresetsMatchThemselves() {
        for preset in EffectPreset.allCases {
            XCTAssertEqual(EffectPreset.matching(preset.settings), preset)
        }
        var custom = EffectSettings.duo
        custom.blurRadius += 1
        XCTAssertNil(EffectPreset.matching(custom))
    }

    func testSweepEndsAndStaysInRange() {
        let sweep = ScriptedSweep(startedAt: 10, open: 120, shut: 40)
        XCTAssertEqual(sweep.angle(at: 10), 120)
        XCTAssertEqual(sweep.angle(at: 10 + sweep.closing)!, 40, accuracy: 1e-9)
        XCTAssertNil(sweep.angle(at: 10 + sweep.duration + 0.01))
        for t in stride(from: 10.0, to: 10 + sweep.duration, by: 0.05) {
            let a = sweep.angle(at: t)!
            XCTAssertGreaterThanOrEqual(a, 40 - 1e-9)
            XCTAssertLessThanOrEqual(a, 120 + 1e-9)
        }
    }
}
