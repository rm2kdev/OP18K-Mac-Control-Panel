import Foundation
import IOKit.hid

/// Counts the OP1's mouse input reports to measure the rate it really sends at.
/// The USB report interval macOS shows is fixed when the mouse is plugged in,
/// so it does not tell you what the polling-rate setting is doing.
public final class ReportRateMeter {
    private let manager: IOHIDManager
    private var timestamps: [UInt64] = []

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: OP1.vendorID,
            kIOHIDProductIDKey: OP1.productID,
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
    }

    /// Starts counting on the current run loop. Call `stop()` after a few seconds of movement.
    public func start() throws {
        timestamps.removeAll(keepingCapacity: true)
        timestamps.reserveCapacity(64_000)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, _, _, _, _, _ in
            let meter = Unmanaged<ReportRateMeter>.fromOpaque(context!).takeUnretainedValue()
            meter.timestamps.append(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnNotPermitted { throw OP1Error.notPermitted }
        guard result == kIOReturnSuccess else { throw OP1Error.io("listening to the mouse", result) }
    }

    /// Stops counting. Returns the busiest 250 ms stretch as reports per second,
    /// or nil when the mouse barely moved.
    public func stop() -> Int? {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return Self.peakRate(timestamps)
    }

    static func peakRate(_ times: [UInt64], window: UInt64 = 250_000_000) -> Int? {
        guard times.count >= 100 else { return nil }
        var best = 0
        var start = 0
        for end in times.indices {
            while times[end] - times[start] > window { start += 1 }
            best = max(best, end - start + 1)
        }
        return Int(Double(best) * 1_000_000_000 / Double(window))
    }
}
