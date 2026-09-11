import AppKit
import Observation
import QuartzCore
import DuoCore
import DuoRender

/// Runs the fold: watches the lid, warms the capture as the lid comes down,
/// puts the picture up at the start angle and drives it every frame.
@MainActor
@Observable
final class FoldController {

    enum Status: Equatable {
        case noSensor
        case needsPermission
        case ready
        case off
    }

    private(set) var angle: Double = 0
    private(set) var isActive = false
    private(set) var isPreviewing = false
    private(set) var sensorAvailable = false

    var status: Status {
        if !sensorAvailable { return .noSensor }
        if !ScreenRecordingPermission.isGranted { return .needsPermission }
        return preferences.isEnabled ? .ready : .off
    }

    var sensorResolution: String { monitor.resolutionLabel }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let monitor = LidMonitor()
    @ObservationIgnored private let stream = ScreenStream()
    @ObservationIgnored private let snapshot = ScreenSnapshot()
    @ObservationIgnored private let overlay = FoldOverlay()
    @ObservationIgnored private var decider: FoldDecider
    @ObservationIgnored private var spring = DampedSpring(frequency: 9)
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastFrame: CFTimeInterval = 0
    @ObservationIgnored private var lastPublish: CFTimeInterval = 0
    @ObservationIgnored private var snapshotTimer: Timer?
    @ObservationIgnored private var captureInFlight = false
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var isScreenLocked = false
    @ObservationIgnored private var layout: (id: CGDirectDisplayID?, frame: CGRect?) = (nil, nil)
    @ObservationIgnored private var scrubAngle: Double?
    @ObservationIgnored private var reveal: Reveal?
    @ObservationIgnored private var activationTime: CFTimeInterval = 0
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var lastPermission = ScreenRecordingPermission.isGranted

    /// The focus-on-wake timeline: the frosted desktop comes into focus.
    private struct Reveal {
        let startedAt: CFTimeInterval
        let duration: CFTimeInterval = 0.9
        func progress(at time: CFTimeInterval) -> Double {
            let t = min(max((time - startedAt) / duration, 0), 1)
            // Ease out: fast at first, settling gently.
            return 1 - (1 - pow(1 - t, 3))
        }
        func isOver(at time: CFTimeInterval) -> Bool { time - startedAt >= duration + 0.05 }
    }

    /// Degrees above the start angle where pre-warming begins.
    private static let armCeiling: Double = 70

    init(preferences: Preferences) {
        self.preferences = preferences
        decider = FoldDecider(startAngle: preferences.effect.startAngle)
    }

    // MARK: Lifecycle

    /// Only answers whether the sensor exists, for windows shown before `start()`.
    func probeSensor() {
        sensorAvailable = monitor.isAvailable
    }

    func start() {
        sensorAvailable = monitor.isAvailable
        Log.app.notice("start: sensor \(self.sensorAvailable), screen recording \(ScreenRecordingPermission.isGranted), model \(MacModel.identifier, privacy: .public)")
        overlay.warmUp()
        observeSystem()
        watchPermission()
        guard sensorAvailable else { return }
        monitor.onSample = { [weak self] tracker, time in self?.handle(tracker: tracker, at: time) }
        monitor.onFailure = { [weak self] in self?.endFold() }
        monitor.start()
        angle = monitor.tracker.angle
        layout = (NSScreen.builtIn?.displayID, NSScreen.builtIn?.frame)
        Task {
            await snapshot.warm()
            try? await Task.sleep(for: .milliseconds(600))
            await stream.warm()
        }
    }

    func stop() {
        monitor.stop()
        stopDisplayLink()
        overlay.dismiss(animated: false)
        stopWarming()
        overlay.endLive()
        isActive = false
    }

    // MARK: Preview and scrub

    /// Plays one close-and-open without the lid moving.
    func preview() {
        guard reveal == nil, !isActive || isPreviewing else { return }
        guard ScreenRecordingPermission.isGranted else {
            FileLog.write("fold", "preview refused: Screen Recording is not granted")
            return
        }
        let effect = preferences.effect
        let sweep = ScriptedSweep(
            startedAt: CACurrentMediaTime() + 0.05,
            open: min(effect.startAngle + 30, 135),
            shut: max(effect.startAngle - effect.span * 1.1, 8)
        )
        isPreviewing = true
        monitor.override = { time in sweep.angle(at: time) }
        monitor.setRate(.moving)
        decider.forceIdle()
        Log.fold.notice("preview sweep \(sweep.open, format: .fixed(precision: 0))° → \(sweep.shut, format: .fixed(precision: 0))°")
        FileLog.write("fold", String(format: "preview sweep %.0f° → %.0f°", sweep.open, sweep.shut))
    }

    /// Holds the fold at one angle while a slider is being dragged.
    func scrub(to angle: Double?) {
        guard ScreenRecordingPermission.isGranted, sensorAvailable || angle != nil else { return }
        if let angle {
            scrubAngle = angle
            if !isPreviewing {
                isPreviewing = true
                monitor.setRate(.moving)
            }
            monitor.override = { [weak self] _ in self?.scrubAngle }
            if !isActive {
                let now = CACurrentMediaTime()
                decider.forceActive(at: now)
                beginFold(at: now, snapping: true)
            }
        } else {
            scrubAngle = nil
            monitor.override = nil
            finishPreview()
        }
    }

    private func finishPreview() {
        guard isPreviewing else { return }
        isPreviewing = false
        monitor.override = nil
        monitor.resetBaseline()
        decider.forceIdle()
        endFold()
    }

    // MARK: Sampling

    private func handle(tracker: AngleTracker, at time: CFTimeInterval) {
        guard !isSuspended else { return }
        publish(tracker.angle, at: time)

        if isPreviewing, monitor.override == nil, scrubAngle == nil {
            // The scripted sweep has run out.
            finishPreview()
            return
        }
        if scrubAngle != nil {
            // A slider is holding the fold; the decider stays out of it.
            if isActive, overlay.isVisible, displayLink == nil { startDisplayLink() }
            return
        }

        let effect = preferences.effect
        decider.startAngle = effect.startAngle
        decider.armCeiling = Self.armCeiling
        let previous = decider.phase
        let phase = decider.update(tracker: tracker, enabled: preferences.isEnabled && reveal == nil, time: time)

        switch (previous, phase) {
        case (_, .active) where !isActive:
            beginFold(at: time, snapping: false)
        case (.active, .idle), (.active, .armed):
            endFold()
        case (_, .armed):
            warmCapture()
        case (.armed, .idle):
            stopWarming()
        default:
            break
        }
        if isActive, !overlay.isVisible, !captureInFlight {
            present()
        }
        if isActive, overlay.isVisible, displayLink == nil {
            startDisplayLink()
        }

        let wantsFast = isPreviewing || isActive || phase == .armed
        monitor.setRate(wantsFast ? .moving : (tracker.angle <= effect.startAngle + Self.armCeiling + 25 ? .watching : .resting))
    }

    private func publish(_ value: Double, at time: CFTimeInterval) {
        guard time - lastPublish > 0.1 || abs(value - angle) > 1 else { return }
        lastPublish = time
        if abs(angle - value) > 0.005 { angle = value }
    }

    // MARK: Warm-up

    private func warmCapture() {
        guard ScreenRecordingPermission.isGranted else { return }
        if preferences.effect.livePicture {
            snapshotTimer?.invalidate()
            snapshotTimer = nil
            stream.start()
        } else {
            stream.stop()
            overlay.endLive()
            guard snapshotTimer == nil else { return }
            Task { _ = await snapshot.capture() }
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.captureSnapshotForWarmUp() }
            }
            RunLoop.main.add(timer, forMode: .common)
            snapshotTimer = timer
        }
    }

    private func captureSnapshotForWarmUp() {
        Task { _ = await snapshot.capture() }
    }

    private func stopWarming() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        stream.stop()
        overlay.endLive()
        snapshot.discard()
    }

    // MARK: Fold

    private func beginFold(at time: CFTimeInterval, snapping: Bool) {
        guard ScreenRecordingPermission.isGranted else {
            Log.fold.notice("fold wanted but screen recording is not granted")
            FileLog.write("fold", "wanted, but Screen Recording is not granted")
            decider.forceIdle()
            return
        }
        isActive = true
        activationTime = time
        // Ease in from the start angle, so a lid already past it does not pop.
        spring.snap(to: snapping ? monitor.tracker.angle : max(monitor.tracker.angle, preferences.effect.startAngle))
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        Log.fold.notice("fold begins at \(self.monitor.tracker.angle, format: .fixed(precision: 1))°, velocity \(self.monitor.tracker.velocity, format: .fixed(precision: 0))°/s")
        FileLog.write("fold", String(format: "begins at %.1f°, velocity %.0f°/s, live %d", monitor.tracker.angle, monitor.tracker.velocity, preferences.effect.livePicture ? 1 : 0))
        present()
    }

    private func endFold() {
        guard isActive else { return }
        isActive = false
        Log.fold.notice("fold ends at \(self.monitor.tracker.angle, format: .fixed(precision: 1))°")
        FileLog.write("fold", String(format: "ends at %.1f°", monitor.tracker.angle))
        stopDisplayLink()
        overlay.dismiss(animated: true)
        snapshot.discard()
        // Let the fade finish before the stream goes away.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, !self.isActive, self.decider.phase != .armed else { return }
            self.stream.stop()
            self.overlay.endLive()
        }
    }

    private func present() {
        guard let screen = NSScreen.builtIn else { return }
        if preferences.effect.livePicture, overlay.showLive(on: screen) {
            startDisplayLink()
            if let frame = stream.takeFrame() {
                overlay.absorb(frame)
                return
            }
            if let image = snapshot.image {
                overlay.seed(image)
                return
            }
            requestSeed()
            return
        }
        if let image = snapshot.image {
            overlay.showStill(image, on: screen) { [weak self] in self?.startDisplayLink() }
            return
        }
        captureInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let image = await self.snapshot.capture()
            self.captureInFlight = false
            guard self.isActive, !self.overlay.isVisible, let image, let screen = NSScreen.builtIn else { return }
            self.overlay.showStill(image, on: screen) { [weak self] in self?.startDisplayLink() }
        }
    }

    private func requestSeed() {
        captureInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let image = await self.snapshot.capture()
            self.captureInFlight = false
            guard self.isActive, !self.overlay.isPictureReady, let image else { return }
            self.overlay.seed(image)
        }
    }

    // MARK: Frames

    private func startDisplayLink() {
        stopDisplayLink()
        guard let window = overlay.hostWindow else { return }
        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        lastFrame = CACurrentMediaTime()
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastFrame, 1.0 / 240), 1.0 / 20)
        lastFrame = now
        if let frame = stream.takeFrame() {
            overlay.absorb(frame)
        }
        if let reveal {
            drawReveal(reveal, at: now)
            return
        }
        let target = scrubAngle ?? monitor.tracker.extrapolatedAngle(at: now)
        spring.advance(toward: target, dt: dt)
        draw(angle: spring.value, at: now)
    }

    private func draw(angle: Double, at time: CFTimeInterval) {
        overlay.render(FrameParameters.make(effect: preferences.effect, screenSize: overlay.screenSize, angle: angle, time: time))
    }

    private func drawReveal(_ reveal: Reveal, at time: CFTimeInterval) {
        let effect = preferences.effect
        let progress = reveal.progress(at: time)
        overlay.render(FrameParameters.make(effect: effect, screenSize: overlay.screenSize, angle: effect.startAngle,
                                            progressOverride: progress, flat: true, time: time))
        if reveal.isOver(at: time) {
            self.reveal = nil
            stopDisplayLink()
            overlay.dismiss(animated: true, duration: 0.12)
            snapshot.discard()
        }
    }

    // MARK: Focus on wake

    private func beginReveal() {
        guard preferences.focusOnWake, preferences.isEnabled, ScreenRecordingPermission.isGranted,
              !isActive, reveal == nil, let screen = NSScreen.builtIn else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let image = await self.snapshot.capture(), !self.isActive, self.reveal == nil else { return }
            self.reveal = Reveal(startedAt: CACurrentMediaTime() + 0.05)
            self.overlay.showStill(image, on: screen) { [weak self] in self?.startDisplayLink() }
            Log.fold.notice("focus-on-wake reveal")
            FileLog.write("fold", "focus-on-wake reveal")
        }
    }

    /// Screen Recording can be granted while the app runs; notice it, log it,
    /// and get the capture filters ready.
    private func watchPermission() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermission() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func checkPermission() {
        let granted = ScreenRecordingPermission.isGranted
        guard granted != lastPermission else { return }
        lastPermission = granted
        FileLog.write("app", "screen recording \(granted ? "granted" : "revoked")")
        if granted {
            Task {
                await snapshot.warm()
                await stream.warm()
            }
        }
    }

    // MARK: System events

    private func observeSystem() {
        // Remote hooks for QA: `Scripts/duoctl preview` and `Scripts/duoctl scrub 60`.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name("com.mac-duo.app.preview"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preview() }
        }
        distributed.addObserver(forName: Notification.Name("com.mac-duo.app.scrub"), object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                let value = (note.object as? String).flatMap(Double.init)
                self?.scrub(to: value)
            }
        }
        distributed.addObserver(forName: Notification.Name("com.mac-duo.app.reveal"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginReveal() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isScreenLocked = true }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasLocked = self.isScreenLocked
                self.isScreenLocked = false
                if wasLocked, !self.isSuspended { self.scheduleReveal() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    private var revealScheduled = false
    private func scheduleReveal() {
        guard !revealScheduled else { return }
        revealScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            self.revealScheduled = false
            guard !self.isScreenLocked, !self.isSuspended else { return }
            self.beginReveal()
        }
    }

    private func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        Log.app.notice("suspend")
        FileLog.write("app", "suspend")
        reveal = nil
        stopDisplayLink()
        overlay.dismiss(animated: false)
        stopWarming()
        monitor.override = nil
        scrubAngle = nil
        isPreviewing = false
        isActive = false
        captureInFlight = false
        decider.forceIdle()
    }

    private func resume() {
        guard isSuspended else { return }
        isSuspended = false
        Log.app.notice("resume, locked \(self.isScreenLocked)")
        FileLog.write("app", "resume, screen locked \(isScreenLocked)")
        monitor.resetBaseline()
        monitor.setRate(.resting)
        if !isScreenLocked { scheduleReveal() }
    }

    private func screensChanged() {
        let screen = NSScreen.builtIn
        let fresh = (screen?.displayID, screen?.frame)
        guard fresh.0 != layout.id || fresh.1 != layout.frame else { return }
        layout = fresh
        Log.app.notice("built-in display changed")
        if isActive { endFold() }
        reveal = nil
        stopWarming()
        stream.invalidateFilter()
        snapshot.invalidateFilter()
        Task {
            await snapshot.warm()
            await stream.warm()
        }
    }

    // MARK: Diagnostics

    func diagnostics() -> String {
        """
        \(AppInfo.name) \(AppInfo.version) (\(AppInfo.build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Model \(MacModel.identifier)
        Sensor \(sensorAvailable ? "available, \(monitor.resolutionLabel)" : "not found")
        Angle \(String(format: "%.2f", angle))°
        Screen recording \(ScreenRecordingPermission.isGranted ? "granted" : "not granted")
        Enabled \(preferences.isEnabled), focus on wake \(preferences.focusOnWake)
        Preset \(preferences.preset?.title ?? "Custom")
        Built-in display \(NSScreen.builtIn.map { "\(Int($0.frame.width))×\(Int($0.frame.height)) @\($0.backingScaleFactor)x" } ?? "none")
        """
    }
}
