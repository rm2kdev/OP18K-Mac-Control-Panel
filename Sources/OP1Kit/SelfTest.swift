// Protocol checks that run without the mouse: `op1ctl selftest`.
// A plain function, because the Command Line Tools ship without XCTest or Swift Testing.

public enum SelfTest {
    /// Returns one line per failed check; empty means all passed.
    public static func run() -> [String] {
        var failures: [String] = []
        func check(_ ok: Bool, _ name: String) { if !ok { failures.append(name) } }

        check(PollingRate.allCases.map(\.divider) == [8, 4, 2, 1], "dividers match the official tool")
        check(PollingRate(divider: 3) == nil, "unknown divider is rejected")

        var report = [UInt8](repeating: 0, count: OP1.settingsReportSize)
        report[0] = 0xA0
        report[1] = 0x01
        report.replaceSubrange(16 ..< 16 + OP1.settingsSize, with: Settings.sample.bytes)
        report[16 + Settings.pollingOffset] = 1
        report[16 + 600] = 0x5A // an unknown byte that must survive

        guard let original = try? Settings(report: report) else { return failures + ["read report parses"] }
        check(original.pollingRate == .hz8000 && original.looksValid, "read report gives 8000 Hz and looks valid")

        for firstByte: UInt8 in [0x00, 0xA1] {
            var macReply = Array(report.prefix(1040)) // as macOS returns it
            macReply[0] = firstByte
            check((try? Settings(report: macReply)) == original, "macOS-style reply parses the same")
        }

        var bad = report
        bad[1] = 0
        check((try? Settings(report: bad)) == nil, "read report with a bad status is rejected")

        var changed = original
        changed.pollingRate = .hz1000
        let store = changed.storeReport
        check(store.count == 1041, "store report is 1041 bytes")
        check(Array(store[0..<16]) == [0xA0, 0x11] + [UInt8](repeating: 0, count: 14), "store report header")
        check(store[1040] == 0, "store report trailing byte")
        check((0..<1024).filter { original.bytes[$0] != changed.bytes[$0] } == [Settings.pollingOffset], "only the polling byte changes")
        check(store[16 + Settings.pollingOffset] == 8 && store[16 + 600] == 0x5A, "store report carries the new rate and unknown bytes")

        let cmd = command(OP1.opLoadSettings)
        check(cmd.count == 64 && cmd[0] == 0xA1 && cmd[1] == 0x12, "load command layout")

        failures += dpiChecks()
        return failures
    }

    static func dpiChecks() -> [String] {
        var failures: [String] = []
        func check(_ ok: Bool, _ name: String) { if !ok { failures.append(name) } }

        // Settings bytes 13...70 as read from a real OP1 8k v1 on firmware 1.24.
        var real = [UInt8](repeating: 0, count: OP1.settingsSize)
        let dump: [UInt8] = [0x02, 0x04, 0xff, 0xff, 0x00, 0x01, 0x01, 0x00, 0x00, 0xff, 0x01, 0x02, 0xff,
                             0x00, 0x00, 0x01, 0x03, 0x00, 0xff, 0x00, 0x01, 0x04, 0x00, 0x90, 0x01, 0x90,
                             0x01, 0x00, 0x20, 0x03, 0x20, 0x03, 0x00, 0x40, 0x06, 0x40, 0x06, 0x00, 0x80,
                             0x0c, 0x80, 0x0c]
        real.replaceSubrange(13 ..< 13 + dump.count, with: dump)
        real[Settings.pollingOffset] = 8
        guard var s = try? Settings(bytes: real) else { return ["real dump parses"] }
        check(s.activeDPILevels == 4, "real dump has 4 DPI levels")
        check((0..<4).map { s.dpi($0) } == [400, 800, 1600, 3200].map { DPILevel($0) }, "real dump DPI is 400/800/1600/3200")
        check(s.looksValid, "real dump looks valid")

        check(Settings.normalizedDPI(10) == 50 && Settings.normalizedDPI(99_999) == 26_000, "DPI clamps to 50...26000")
        check(Settings.normalizedDPI(824) == 800 && Settings.normalizedDPI(825) == 850, "DPI rounds to the nearest 50")

        let before = s
        s.setDPI(1, DPILevel(x: 800, y: 1200))
        let changed = (0..<1024).filter { before.bytes[$0] != s.bytes[$0] }
        check(changed == [40, 43, 44], "split level writes flag and Y only")
        check(s.dpi(1) == DPILevel(x: 800, y: 1200) && s.bytes[40] == 1, "split level reads back")
        s.setDPI(1, DPILevel(800))
        check(s == before, "same X and Y clears the split flag")

        s.activeDPILevels = 9
        check(s.activeDPILevels == 4, "level count clamps to 4")
        s.activeDPILevels = 2

        var fresh = before
        fresh.bytes[13] = 0 // the user pressed the DPI button since the last read
        let merged = fresh.applying(s)
        check(merged.bytes[13] == 0 && merged.activeDPILevels == 2, "Apply keeps the current level byte")
        check(Settings.sample.looksValid, "sample settings look valid")
        return failures
    }
}
