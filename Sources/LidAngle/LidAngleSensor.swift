import Foundation
import IOKit
import IOKit.hid

/// The MacBook hinge angle, read from the lid angle sensor.
///
/// Apple silicon MacBooks (and the 2019 16-inch MacBook Pro) expose the hinge
/// angle as a HID feature report on the `AppleSPUHIDDevice` with vendor
/// `0x05AC`, product `0x8104`, usage page `0x20` (sensor), usage `0x8A`
/// (orientation). Two reports carry it:
///
/// - Report `7`: five bytes, `[7, b0, b1, b2, b3]`, little-endian hundredths
///   of a degree.
/// - Report `1`: three bytes, `[1, lo, hi]`, whole degrees.
///
/// Reading needs no permission. The hardware refreshes about every 100 ms.
/// Zero is closed; most lids open to roughly 130°.
public final class LidAngleSensor: @unchecked Sendable {

    public enum Resolution: Sendable {
        case hundredths
        case whole

        var reportID: CFIndex {
            switch self {
            case .hundredths: return 7
            case .whole: return 1
            }
        }

        public var label: String {
            switch self {
            case .hundredths: return "0.01°"
            case .whole: return "1°"
            }
        }
    }

    /// The most recent raw read, for diagnostics.
    public struct Trace: Sendable {
        public var status: IOReturn = kIOReturnSuccess
        public var bytes: [UInt8] = []
    }

    public private(set) var resolution: Resolution?
    public private(set) var lastTrace = Trace()

    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var buffer = [UInt8](repeating: 0, count: 64)

    public var isAvailable: Bool { device != nil && resolution != nil }

    public init() {
        open()
    }

    deinit {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    /// The hinge angle in degrees, or `nil` if the read failed.
    public func read() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let resolution, let bytes = report(resolution.reportID) else { return nil }
        let degrees: Double
        switch resolution {
        case .hundredths:
            guard bytes.count >= 5 else { return nil }
            let raw = UInt32(bytes[1]) | UInt32(bytes[2]) << 8 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 24
            degrees = Double(raw) / 100
        case .whole:
            guard bytes.count >= 3 else { return nil }
            degrees = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
        }
        guard (0...360).contains(degrees) else { return nil }
        return degrees
    }

    private func open() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: NSDictionary = [
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        self.manager = manager

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices {
            device = candidate
            if let bytes = report(7), bytes.count >= 5 {
                resolution = .hundredths
                return
            }
            if let bytes = report(1), bytes.count >= 3 {
                resolution = .whole
                return
            }
        }
        device = nil
    }

    private func report(_ id: CFIndex) -> [UInt8]? {
        guard let device else {
            lastTrace = Trace(status: kIOReturnNoDevice, bytes: [])
            return nil
        }
        var length = CFIndex(buffer.count)
        let status = buffer.withUnsafeMutableBufferPointer { pointer -> IOReturn in
            guard let base = pointer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, id, base, &length)
        }
        guard status == kIOReturnSuccess, length > 0 else {
            lastTrace = Trace(status: status, bytes: [])
            return nil
        }
        let bytes = Array(buffer[0..<Int(length)])
        lastTrace = Trace(status: status, bytes: bytes)
        return bytes
    }
}
