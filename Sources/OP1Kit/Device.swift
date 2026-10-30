import Foundation
import IOKit.hid

/// The OP1 8k's vendor HID interface, opened through IOKit.
public final class OP1Device {
    private let device: IOHIDDevice
    public let firmwareRevision: Int

    /// Finds the interface that carries the 1041-byte settings report and opens it.
    public static func open() throws -> OP1Device {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: OP1.vendorID,
            kIOHIDProductIDKey: OP1.productID,
        ] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { throw OP1Error.notFound }
        guard let device = set.first(where: { intProperty($0, kIOHIDMaxFeatureReportSizeKey) >= OP1.settingsReportSize }) else {
            throw OP1Error.notFound
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnNotPermitted { throw OP1Error.notPermitted }
        guard result == kIOReturnSuccess else { throw OP1Error.io("opening the mouse", result) }
        return OP1Device(device: device)
    }

    private init(device: IOHIDDevice) {
        self.device = device
        firmwareRevision = intProperty(device, kIOHIDVersionNumberKey)
    }

    deinit { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    /// Firmware as the USB descriptor reports it, e.g. "1.24".
    public var firmwareString: String {
        String(format: "%x.%02x", firmwareRevision >> 8, firmwareRevision & 0xFF)
    }

    public func readSettings() throws -> Settings {
        var lastError: Error = OP1Error.badResponse("no reply")
        for _ in 0..<5 {
            try setFeature(command(OP1.opLoadSettings))
            usleep(80_000)
            do {
                return try Settings(report: try getFeature(OP1.settingsReportID, length: OP1.settingsReportSize))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Writes the settings, then reads them back and checks they match.
    public func writeSettings(_ settings: Settings) throws {
        guard settings.looksValid else { throw OP1Error.refused("refusing to write a settings block that does not look valid") }
        try setFeature(settings.storeReport)
        usleep(300_000)
        let check = try readSettings()
        guard check == settings else { throw OP1Error.badResponse("settings read back after writing do not match") }
    }

    /// Read-only diagnostic: raw replies to the settings and firmware queries, as hex.
    public func rawReplies() -> String {
        var out = ""
        for (op, id, length) in [(OP1.opLoadSettings, OP1.settingsReportID, OP1.settingsReportSize),
                                 (OP1.opFirmwareVersion, OP1.commandReportID, OP1.commandSize)] {
            do {
                try setFeature(command(op))
                usleep(80_000)
                let reply = try getFeature(id, length: length)
                out += String(format: "op %02X -> report %02X, %d bytes\n", op, id, reply.count)
                for row in stride(from: 0, to: min(reply.count, 96), by: 16) {
                    out += reply[row ..< min(row + 16, reply.count)].map { String(format: "%02x", $0) }.joined(separator: " ") + "\n"
                }
            } catch {
                out += String(format: "op %02X: ", op) + "\(error)\n"
            }
        }
        return out
    }

    // MARK: HID feature reports. Buffers include the report ID in byte 0, as hidapi does.

    func setFeature(_ report: [UInt8]) throws {
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(report[0]), $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw OP1Error.io("sending report \(String(format: "0x%02X", report[0]))", result) }
    }

    func getFeature(_ id: UInt8, length: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: length)
        buffer[0] = id
        var count = CFIndex(length)
        let result = buffer.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), $0.baseAddress!, &count)
        }
        guard result == kIOReturnSuccess else { throw OP1Error.io("reading report \(String(format: "0x%02X", id))", result) }
        return Array(buffer.prefix(count))
    }
}

/// Input Monitoring access. The OP1's settings live on an interface that also reports
/// as a keyboard, so macOS asks the user before any app may open it.
public enum InputMonitoring {
    public static var isGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    /// Shows the system prompt the first time; afterwards returns the saved answer.
    @discardableResult
    public static func request() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
}

/// Saves the settings block to ~/Library/Application Support/OP1Control/backups before a write.
public func backup(_ settings: Settings) throws -> URL {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/OP1Control/backups")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let url = dir.appending(path: "settings-\(stamp).bin")
    try Data(settings.bytes).write(to: url)
    return url
}

private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
}

/// Current polling rate as macOS sees it, from the mouse interface's USB report interval.
public func systemReportedPollingHz() -> Int? {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [
        kIOHIDVendorIDKey: OP1.vendorID,
        kIOHIDProductIDKey: OP1.productID,
        kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDPrimaryUsageKey: kHIDUsage_GD_Mouse,
    ] as CFDictionary)
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
          let mouse = set.first else { return nil }
    let micros = intProperty(mouse, kIOHIDReportIntervalKey)
    return micros > 0 ? 1_000_000 / micros : nil
}
