import SwiftUI
import Combine
import OP1Kit

// OP1Kit.Settings, named apart from SwiftUI's Settings scene.
typealias MouseSettings = OP1Kit.Settings

// ObservableObject and property wrappers rather than @Observable and @State:
// the Command Line Tools ship without the SwiftUI macro plugins.

@main
struct OP1ControlApp: App {
    @StateObject private var model = MouseModel()

    init() {
        let args = CommandLine.arguments
        // `open OP1Control.app --args --dump-raw <file>` writes the raw replies and quits.
        // Runs as the app so it uses the app's Input Monitoring permission. Read-only.
        if let i = args.firstIndex(of: "--dump-raw"), i + 1 < args.count {
            let text = (try? OP1Device.open().rawReplies()) ?? "could not open the mouse\n"
            try? text.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
            exit(0)
        }
        // `OP1Control --snapshot <dir>` renders the window in light and dark with sample settings and quits.
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(to: args[i + 1])
            exit(0)
        }
    }

    var body: some Scene {
        Window("OP1 Control", id: "main") {
            ContentView(model: model)
                .frame(width: 420)
                .fixedSize()
                // The title would push Apply into the toolbar's overflow menu at this width.
                .toolbar(removing: .title)
                .task { model.start() }
        }
        .windowResizability(.contentSize)
    }
}

final class MouseModel: ObservableObject {
    @Published var firmware: String?
    /// The settings as last read from the mouse.
    @Published var loaded: MouseSettings?
    /// The settings with the user's edits, written by Apply.
    @Published var draft: MouseSettings?
    @Published var separateXY = false
    @Published var systemHz: Int?
    @Published var message: String?
    @Published var isError = false
    @Published var isBusy = false
    @Published var needsPermission = false
    @Published var measuring = false
    @Published var measuredHz: Int?
    @Published var measureNote: String?

    var connected: Bool { loaded != nil }
    var hasChanges: Bool { draft != nil && draft != loaded }

    func start() {
        if !InputMonitoring.isGranted && !InputMonitoring.request() {
            needsPermission = true
            systemHz = systemReportedPollingHz()
            return
        }
        refresh()
    }

    func refresh() {
        needsPermission = !InputMonitoring.isGranted
        run {
            let mouse = try OP1Device.open()
            let settings = try mouse.readSettings()
            self.firmware = mouse.firmwareString
            self.show(settings)
            self.message = settings.looksValid ? nil : "These settings don't look like an OP1 8k. Writing is disabled."
        }
    }

    func show(_ settings: MouseSettings) {
        loaded = settings
        draft = settings
        separateXY = (0..<MouseSettings.dpiLevelCount).contains { settings.dpi($0).isSplit }
    }

    func apply() {
        guard let edits = draft else { return }
        run {
            let mouse = try OP1Device.open()
            let current = try mouse.readSettings()
            guard current.looksValid else {
                throw OP1Error.refused("The settings on this mouse don't look like an OP1 8k. Nothing was changed.")
            }
            let saved = try backup(current)
            let updated = current.applying(edits)
            try mouse.writeSettings(updated)
            self.show(updated)
            self.message = "Saved to the mouse. Backup of the old settings: \(saved.lastPathComponent)"
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    func revert() {
        guard let loaded else { return }
        show(loaded)
        message = nil
    }

    // MARK: Bindings into the draft

    var pollingRate: Binding<PollingRate> {
        Binding(get: { self.draft?.pollingRate ?? .hz1000 },
                set: { self.draft?.pollingRate = $0 })
    }

    var activeLevels: Binding<Int> {
        Binding(get: { self.draft?.activeDPILevels ?? MouseSettings.dpiLevelCount },
                set: { self.draft?.activeDPILevels = $0 })
    }

    enum Axis { case both, x, y }

    func dpi(_ level: Int, _ axis: Axis) -> Binding<Int> {
        Binding(
            get: {
                guard let value = self.draft?.dpi(level) else { return MouseSettings.dpiRange.lowerBound }
                return axis == .y ? value.y : value.x
            },
            set: { newValue in
                guard var value = self.draft?.dpi(level) else { return }
                switch axis {
                case .both: value = DPILevel(newValue)
                case .x: value.x = newValue
                case .y: value.y = newValue
                }
                self.draft?.setDPI(level, value)
            })
    }

    /// Turning separate X and Y off sets each level's Y to its X.
    var separate: Binding<Bool> {
        Binding(get: { self.separateXY }, set: { on in
            self.separateXY = on
            guard !on, var d = self.draft else { return }
            for i in 0..<MouseSettings.dpiLevelCount { d.setDPI(i, DPILevel(d.dpi(i).x)) }
            self.draft = d
        })
    }

    // MARK: Measure

    func measure() {
        let meter = ReportRateMeter()
        do { try meter.start() } catch {
            measureNote = "\(error)"
            return
        }
        measuring = true
        measuredHz = nil
        measureNote = "Move the OP1 in fast circles…"
        Task {
            try? await Task.sleep(for: .seconds(4))
            measuredHz = meter.stop()
            measureNote = measuredHz == nil ? "The mouse barely moved. Try again and keep it moving." : nil
            measuring = false
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    private func run(_ body: @escaping () async throws -> Void) {
        isBusy = true
        Task {
            do {
                try await body()
                isError = false
            } catch OP1Error.notPermitted {
                needsPermission = true
                message = nil
            } catch {
                message = "\(error)"
                isError = true
            }
            systemHz = systemReportedPollingHz()
            isBusy = false
        }
    }
}
