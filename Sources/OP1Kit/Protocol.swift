// Endgame Gear OP1 8k (v1) configuration protocol.
//
// Taken from the official "OP1 8k Configuration Tool" V1.12 for Windows
// (SHA-256 128478d3…7069). It talks to the mouse with two HID feature reports
// on the vendor collection (usage page 0xFF01):
//
//   0xA1, 64 bytes    commands. Byte 1 is the opcode.
//   0xA0, 1041 bytes  the settings block. 16-byte header, then 1024 bytes.
//
// Read settings:  set 0xA1 [A1 12 00…], then get 0xA0. Byte 1 is 0x01 when valid.
// Write settings: set 0xA0 [A0 11 00×14, settings×1024, 00].
// Firmware:       set 0xA1 [A1 02 00…], then get 0xA1. Bytes 17 and 18 are major, minor.
//
// Byte 5 of the settings holds the polling rate as a divider of 8000 Hz.
// The official tool's combo box maps 1000/2000/4000/8000 Hz to 8/4/2/1.
// 500 and 250 Hz use dividers 16 and 32, which the official tools never write.

public enum OP1 {
    public static let vendorID = 0x3367
    public static let productID = 0x1964

    public static let commandReportID: UInt8 = 0xA1
    public static let commandSize = 64
    public static let settingsReportID: UInt8 = 0xA0
    public static let settingsReportSize = 1041
    public static let headerSize = 16
    public static let settingsSize = 1024

    public static let opLoadSettings: UInt8 = 0x12
    public static let opStoreSettings: UInt8 = 0x11
    public static let opFirmwareVersion: UInt8 = 0x02

    /// Byte 1 of a settings read when the mouse sent a complete block.
    public static let statusOK: UInt8 = 0x01
}

public enum PollingRate: Int, CaseIterable, Sendable, Identifiable {
    case hz250 = 250
    case hz500 = 500
    case hz1000 = 1000
    case hz2000 = 2000
    case hz4000 = 4000
    case hz8000 = 8000

    public var id: Int { rawValue }

    public var divider: UInt8 { UInt8(8000 / rawValue) }

    public init?(divider: UInt8) {
        guard divider > 0, 8000 % Int(divider) == 0, let rate = PollingRate(rawValue: 8000 / Int(divider)) else { return nil }
        self = rate
    }

    /// 500 and 250 Hz (dividers 16 and 32) are not offered by Endgame Gear's tools;
    /// Endgame Gear does not support them. On firmware 1.24, 500 Hz measured about 500 Hz and
    /// tracked normally; 250 Hz has not been tried on a mouse.
    public var isExperimental: Bool { rawValue < 1000 }

    public static var official: [PollingRate] { allCases.filter { !$0.isExperimental } }

    public var label: String { "\(rawValue) Hz" }
}

/// The 1024-byte settings block, kept whole so unknown bytes go back unchanged.
public struct Settings: Equatable, Sendable {
    public static let pollingOffset = 5
    public static let cpiLevelCountOffset = 14

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == OP1.settingsSize else {
            throw OP1Error.badResponse("settings block is \(bytes.count) bytes, expected \(OP1.settingsSize)")
        }
        self.bytes = bytes
    }

    /// Parses a full 0xA0 report as read from the mouse.
    public init(report: [UInt8]) throws {
        guard report.count >= OP1.headerSize + OP1.settingsSize else {
            throw OP1Error.badResponse("settings report is \(report.count) bytes")
        }
        // Only byte 1 is checked, as the official tool does. On macOS byte 0 comes back
        // as 00 or A1 rather than the A0 report ID; the rest matches the Windows layout.
        guard report[1] == OP1.statusOK else {
            throw OP1Error.badResponse(String(format: "settings report starts %02X %02X", report[0], report[1]))
        }
        try self.init(bytes: Array(report[OP1.headerSize ..< OP1.headerSize + OP1.settingsSize]))
    }

    public var pollingDivider: UInt8 { bytes[Self.pollingOffset] }

    public var pollingRate: PollingRate? {
        get { PollingRate(divider: pollingDivider) }
        set { if let newValue { bytes[Self.pollingOffset] = newValue.divider } }
    }

    public var cpiLevelCount: UInt8 { bytes[Self.cpiLevelCountOffset] }

    /// True when the fields this tool relies on hold values the official tool can produce.
    /// A block that fails this check is not written back.
    public var looksValid: Bool {
        pollingRate != nil && (1...4).contains(cpiLevelCount)
            && (0..<Self.dpiLevelCount).allSatisfy { i in
                let level = dpi(i)
                return Self.dpiRange.contains(level.x) && Self.dpiRange.contains(level.y)
                    && bytes[Self.dpiOffset(i)] <= 1
            }
    }

    // MARK: DPI
    //
    // Byte 14 is how many levels the DPI button cycles through (1 to 4).
    // Bytes 35 to 54 hold four 5-byte levels: a split flag, then X and Y as
    // little-endian 16-bit values. The official tool clamps to 50...26000,
    // rounds to the nearest 50 and sets the flag when X and Y differ.
    // Byte 13 is the mouse's current level; the official tool never writes it.

    public static let dpiLevelCount = 4
    public static let dpiRange = 50...26000
    public static let dpiStep = 50
    static let dpiTableOffset = 35
    static let dpiEntrySize = 5

    static func dpiOffset(_ level: Int) -> Int { dpiTableOffset + level * dpiEntrySize }

    /// Clamps to 50...26000 and rounds to the nearest 50, as the official tool does.
    public static func normalizedDPI(_ value: Int) -> Int {
        let clamped = min(max(value, dpiRange.lowerBound), dpiRange.upperBound)
        return min((clamped + dpiStep / 2) / dpiStep * dpiStep, dpiRange.upperBound)
    }

    /// How many levels the DPI button cycles through.
    public var activeDPILevels: Int {
        get { Int(cpiLevelCount) }
        set { bytes[Self.cpiLevelCountOffset] = UInt8(min(max(newValue, 1), Self.dpiLevelCount)) }
    }

    public func dpi(_ level: Int) -> DPILevel {
        let o = Self.dpiOffset(level)
        return DPILevel(x: Int(bytes[o + 1]) | Int(bytes[o + 2]) << 8,
                        y: Int(bytes[o + 3]) | Int(bytes[o + 4]) << 8)
    }

    public mutating func setDPI(_ level: Int, _ value: DPILevel) {
        let x = Self.normalizedDPI(value.x), y = Self.normalizedDPI(value.y)
        let o = Self.dpiOffset(level)
        bytes[o] = x != y ? 1 : 0
        bytes[o + 1] = UInt8(x & 0xFF)
        bytes[o + 2] = UInt8(x >> 8)
        bytes[o + 3] = UInt8(y & 0xFF)
        bytes[o + 4] = UInt8(y >> 8)
    }

    /// Copies the fields this app edits (polling rate and DPI) from `edits`,
    /// keeping every other byte, including the current level, as read.
    public func applying(_ edits: Settings) -> Settings {
        var out = self
        out.pollingRate = edits.pollingRate
        out.activeDPILevels = edits.activeDPILevels
        for i in 0..<Self.dpiLevelCount { out.setDPI(i, edits.dpi(i)) }
        return out
    }
}

public struct DPILevel: Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public init(_ both: Int) { self.init(x: both, y: both) }

    public var isSplit: Bool { x != y }
    public var label: String { isSplit ? "\(x) × \(y)" : "\(x)" }
}

extension Settings {
    /// A settings block that matches the mouse this app was built against, for snapshots and self-tests.
    public static var sample: Settings {
        var report = [UInt8](repeating: 0, count: OP1.settingsReportSize)
        report[1] = OP1.statusOK
        var s = try! Settings(report: report)
        s.pollingRate = .hz1000
        s.activeDPILevels = 4
        s.bytes[13] = 2
        for (i, v) in [400, 800, 1600, 3200].enumerated() { s.setDPI(i, DPILevel(v)) }
        return s
    }

    /// The 0xA0 report that stores these settings, laid out as the official tool builds it.
    public var storeReport: [UInt8] {
        var report = [UInt8](repeating: 0, count: OP1.settingsReportSize)
        report[0] = OP1.settingsReportID
        report[1] = OP1.opStoreSettings
        report.replaceSubrange(OP1.headerSize ..< OP1.headerSize + OP1.settingsSize, with: bytes)
        return report
    }
}

public enum OP1Error: Error, CustomStringConvertible {
    case notFound
    case notPermitted
    case io(String, Int32)
    case badResponse(String)
    case refused(String)

    public var description: String {
        switch self {
        case .notFound:
            return "OP1 8k not found. Is it plugged in by USB?"
        case .notPermitted:
            return "macOS blocked access to the mouse. Allow this app under System Settings > Privacy & Security > Input Monitoring, then try again."
        case let .io(what, code):
            return "\(what) failed (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))"
        case let .badResponse(msg):
            return "unexpected reply from the mouse: \(msg)"
        case let .refused(msg):
            return msg
        }
    }
}

func command(_ opcode: UInt8) -> [UInt8] {
    var cmd = [UInt8](repeating: 0, count: OP1.commandSize)
    cmd[0] = OP1.commandReportID
    cmd[1] = opcode
    return cmd
}
