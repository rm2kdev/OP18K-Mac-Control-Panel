import AppKit
import SwiftUI
import OP1Kit

/// Renders the window to PNGs without a mouse or Screen Recording permission,
/// in light and dark, for the states that matter. The window frame is drawn too,
/// so the toolbar shows; glass in it is flattened.
enum Snapshot {
    static func run(to directory: String) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        func connected() -> MouseModel {
            let m = MouseModel()
            m.firmware = "1.24"
            m.systemHz = 8000
            m.hasRead = true
            m.show(.sample)
            return m
        }

        var states: [(String, MouseModel)] = []

        let main = connected()
        main.measuredHz = 998
        main.measuredAgainst = .hz1000
        states.append(("main", main))

        let split = connected()
        var s = MouseSettings.sample
        s.activeDPILevels = 2
        s.setDPI(1, DPILevel(x: 800, y: 1200))
        split.draft = s
        split.separateXY = true
        split.measureEnds = Date().addingTimeInterval(2)
        split.measureNote = "Keep the mouse moving."
        states.append(("split", split))

        let saved = connected()
        var e = MouseSettings.sample
        e.pollingRate = .hz500
        saved.show(e)
        saved.notice = Notice(kind: .done, text: "Saved to the mouse.",
                              detail: "The old settings are backed up as settings-2026-10-31T09-12-44Z.bin.")
        saved.measuredHz = 731
        saved.measuredAgainst = .hz500
        states.append(("saved", saved))

        let unplugged = MouseModel()
        unplugged.hasRead = true
        states.append(("not-connected", unplugged))

        let none = MouseModel()
        none.needsPermission = true
        none.hasRead = true
        states.append(("no-permission", none))

        for (name, model) in states {
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let path = "\(directory)/\(name)-\(mode).png"
                render(ContentView(model: model).frame(width: ContentView.width).fixedSize()
                    .toolbar(removing: .title),
                       appearance: appearance, to: path)
                print("SNAPSHOT \(path)")
            }
        }
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name, to path: String) {
        let controller = NSHostingController(rootView: view)
        controller.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: controller)
        // Content below the title bar, so the two captures below can be stacked.
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(controller.view.fittingSize)
        // Off screen, so the snapshot run doesn't flash windows at the user.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        // Let SwiftUI install the toolbar and lay out before drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        // The window frame draws the title bar and toolbar but not the SwiftUI content,
        // so capture both and draw the content over the frame.
        guard let frameView = window.contentView?.superview,
              let chrome = capture(frameView), let content = capture(controller.view) else { return }
        let image = NSImage(size: frameView.bounds.size)
        image.lockFocus()
        // The frame always captures with a light title bar, so dark snapshots leave
        // the toolbar out and show a plain title bar instead.
        if appearance == .darkAqua {
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                frameView.bounds.fill()
            }
        } else {
            chrome.draw(in: frameView.bounds)
        }
        content.draw(in: controller.view.convert(controller.view.bounds, to: frameView))
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        }
        window.orderOut(nil)
    }

    private static func capture(_ view: NSView) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
}
