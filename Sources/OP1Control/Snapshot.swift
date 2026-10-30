import AppKit
import SwiftUI
import OP1Kit

/// Renders the window content to PNGs without a mouse or Screen Recording permission,
/// in light and dark, for the states that matter. The toolbar is window chrome and is not included.
enum Snapshot {
    static func run(to directory: String) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var states: [(String, MouseModel)] = []

        let connected = MouseModel()
        connected.firmware = "1.24"
        connected.systemHz = 8000
        connected.show(.sample)
        states.append(("main", connected))

        let split = MouseModel()
        split.firmware = "1.24"
        var s = MouseSettings.sample
        s.activeDPILevels = 2
        s.setDPI(1, DPILevel(x: 800, y: 1200))
        split.show(.sample)
        split.draft = s
        split.separateXY = true
        split.measuredHz = 1000
        states.append(("split", split))

        let none = MouseModel()
        none.needsPermission = true
        none.systemHz = 8000
        states.append(("no-permission", none))

        for (name, model) in states {
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let path = "\(directory)/\(name)-\(mode).png"
                render(ContentView(model: model).frame(width: 420).fixedSize(), appearance: appearance, to: path)
                print("SNAPSHOT \(path)")
            }
        }
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name, to path: String) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }
}
