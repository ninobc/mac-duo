import AppKit
import ScreenCaptureKit

/// One still of the built-in display, used to start the fold before the live
/// stream has a frame, and for the focus-on-wake reveal.
@MainActor
final class ScreenSnapshot {

    private(set) var image: CGImage?
    private var filter: SCContentFilter?
    private var filterDisplay: CGDirectDisplayID?
    private var inFlight: Task<CGImage?, Never>?

    func discard() {
        image = nil
    }

    func invalidateFilter() {
        filter = nil
        filterDisplay = nil
    }

    /// Builds the filter ahead of time; enumerating windows takes ~70 ms.
    func warm() async {
        guard let id = NSScreen.builtIn?.displayID, filter == nil || filterDisplay != id else { return }
        await rebuildFilter(display: id)
    }

    /// Captures once. Concurrent callers share the same capture.
    @discardableResult
    func capture() async -> CGImage? {
        if let inFlight { return await inFlight.value }
        let task = Task<CGImage?, Never> { [weak self] in
            guard let self else { return nil }
            let image = await self.performCapture()
            self.inFlight = nil
            return image
        }
        inFlight = task
        return await task.value
    }

    private func performCapture() async -> CGImage? {
        guard let screen = NSScreen.builtIn, let id = screen.displayID else { return nil }
        if filter == nil || filterDisplay != id {
            await rebuildFilter(display: id)
        }
        guard let filter else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.colorSpaceName = ScreenStream.colourSpace
        do {
            let started = CACurrentMediaTime()
            let captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            image = captured
            Log.capture.debug("snapshot in \((CACurrentMediaTime() - started) * 1000, format: .fixed(precision: 0)) ms")
            return captured
        } catch {
            Log.capture.error("snapshot failed: \(String(describing: error), privacy: .public)")
            invalidateFilter()
            return nil
        }
    }

    private func rebuildFilter(display id: CGDirectDisplayID) async {
        filter = await ContentFilterBuilder.make(display: id)
        filterDisplay = filter == nil ? nil : id
    }
}

/// Builds a display filter that leaves this app's own windows out, so the
/// overlay never captures itself.
enum ContentFilterBuilder {
    @MainActor
    static func make(display id: CGDirectDisplayID) async -> SCContentFilter? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
            let own = content.applications.filter { $0.bundleIdentifier == AppInfo.bundleID }
            if own.isEmpty {
                Log.capture.notice("own app not listed by ScreenCaptureKit; overlay may capture itself")
            }
            return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        } catch {
            Log.capture.error("shareable content failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
