import Foundation
import OP1Kit

let usage = """
usage: op1ctl info              show polling rate and firmware
       op1ctl rate <hz>         set polling rate: 1000, 2000, 4000 or 8000
       op1ctl dpi <level> <dpi> [<y-dpi>]
                                set a DPI level (1-4), 50-26000 in steps of 50
       op1ctl dpi-levels <n>    set how many levels the DPI button cycles through (1-4)
       op1ctl dump              print the raw settings block
       op1ctl restore <file>    write back a settings backup
       op1ctl selftest          check the protocol code (no mouse needed)
"""

func printDPI(_ settings: Settings) {
    for i in 0..<Settings.dpiLevelCount {
        let state = i < settings.activeDPILevels ? "" : "  (off)"
        print("DPI level \(i + 1):   \(settings.dpi(i).label)\(state)")
    }
}

/// Reads, changes, backs up and writes the settings, then shows the DPI levels.
func modify(_ change: (inout Settings) -> Void) throws {
    let mouse = try OP1Device.open()
    let current = try mouse.readSettings()
    guard current.looksValid else {
        throw OP1Error.refused("the settings read from the mouse do not look like an OP1 8k v1. Nothing was written.")
    }
    var edited = current
    change(&edited)
    if edited == current { print("No change."); return }
    print("Backup:        \(try backup(current).path)")
    try mouse.writeSettings(edited)
    printDPI(edited)
}

func run(_ args: [String]) throws {
    switch args.first {
    case "info":
        let mouse = try OP1Device.open()
        let settings = try mouse.readSettings()
        print("Firmware:      \(mouse.firmwareString)")
        print("Polling rate:  \(settings.pollingRate?.label ?? "unknown (divider \(settings.pollingDivider))")")
        if let hz = systemReportedPollingHz() { print("macOS sees:    \(hz) Hz") }
        printDPI(settings)
        print("Settings look valid: \(settings.looksValid ? "yes" : "NO")")

    case "dpi":
        guard (3...4).contains(args.count), let level = Int(args[1]), (1...4).contains(level),
              let x = Int(args[2]), let y = Int(args.count == 4 ? args[3] : args[2]) else {
            throw OP1Error.refused("usage: op1ctl dpi <level 1-4> <dpi> [<y-dpi>]")
        }
        try modify { $0.setDPI(level - 1, DPILevel(x: x, y: y)) }

    case "dpi-levels":
        guard args.count == 2, let n = Int(args[1]), (1...4).contains(n) else {
            throw OP1Error.refused("dpi-levels must be 1, 2, 3 or 4")
        }
        try modify { $0.activeDPILevels = n }

    case "dump":
        let settings = try OP1Device.open().readSettings()
        for row in stride(from: 0, to: settings.bytes.count, by: 16) {
            let line = settings.bytes[row ..< row + 16].map { String(format: "%02x", $0) }.joined(separator: " ")
            print(String(format: "%04x  ", row) + line)
        }

    case "rate":
        guard args.count == 2, let hz = Int(args[1]), let rate = PollingRate(rawValue: hz) else {
            throw OP1Error.refused("rate must be 1000, 2000, 4000 or 8000")
        }
        let mouse = try OP1Device.open()
        var settings = try mouse.readSettings()
        guard settings.looksValid else {
            throw OP1Error.refused("the settings read from the mouse do not look like an OP1 8k v1. Nothing was written.")
        }
        if settings.pollingRate == rate { print("Already \(rate.label)."); return }
        print("Backup:        \(try backup(settings).path)")
        settings.pollingRate = rate
        try mouse.writeSettings(settings)
        print("Polling rate:  \(rate.label) (saved on the mouse)")
        usleep(500_000)
        if let seen = systemReportedPollingHz() { print("macOS sees:    \(seen) Hz") }

    case "restore":
        guard args.count == 2 else { throw OP1Error.refused(usage) }
        let saved = try Settings(bytes: [UInt8](Data(contentsOf: URL(filePath: args[1]))))
        try OP1Device.open().writeSettings(saved)
        print("Restored \(args[1])")

    case "selftest":
        let failures = SelfTest.run()
        failures.forEach { print("FAIL \($0)") }
        if !failures.isEmpty { exit(1) }
        print("PASS all checks")

    default:
        print(usage)
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("op1ctl: \(error)\n".utf8))
    exit(1)
}
