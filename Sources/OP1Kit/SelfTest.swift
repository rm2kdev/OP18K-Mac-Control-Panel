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
        report[16 + Settings.pollingOffset] = 1
        report[16 + Settings.cpiLevelCountOffset] = 4
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
        return failures
    }
}
