import SwiftUI
import Combine
import OP1Kit

// ObservableObject and property wrappers rather than @Observable and @State:
// the Command Line Tools ship without the SwiftUI macro plugins.

@main
struct OP1ControlApp: App {
    @StateObject private var model = MouseModel()

    init() {
        // `open OP1Control.app --args --dump-raw <file>` writes the raw replies and quits.
        // Runs as the app so it uses the app's Input Monitoring permission. Read-only.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--dump-raw"), i + 1 < args.count {
            let text = (try? OP1Device.open().rawReplies()) ?? "could not open the mouse\n"
            try? text.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
            exit(0)
        }
    }

    var body: some Scene {
        Window("OP1 Control", id: "main") {
            ContentView(model: model)
                .frame(width: 400)
                .fixedSize()
                .task { model.start() }
        }
        .windowResizability(.contentSize)
    }
}

final class MouseModel: ObservableObject {
    @Published var firmware: String?
    @Published var current: PollingRate?
    @Published var selected: PollingRate = .hz1000
    @Published var systemHz: Int?
    @Published var message: String?
    @Published var isError = false
    @Published var isBusy = false
    @Published var needsPermission = false
    @Published var measuring = false
    @Published var measuredHz: Int?
    @Published var measureNote: String?

    var connected: Bool { firmware != nil }

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
            self.current = settings.pollingRate
            if let rate = settings.pollingRate, rate != .hz8000 { self.selected = rate }
            self.message = settings.looksValid ? nil : "These settings don't look like an OP1 8k. Writing is disabled."
        }
    }

    func apply() {
        let rate = selected
        run {
            let mouse = try OP1Device.open()
            var settings = try mouse.readSettings()
            guard settings.looksValid else {
                throw OP1Error.refused("The settings on this mouse don't look like an OP1 8k. Nothing was changed.")
            }
            let saved = try backup(settings)
            settings.pollingRate = rate
            try mouse.writeSettings(settings)
            self.current = rate
            self.message = "Saved \(rate.label) to the mouse. Backup of the old settings: \(saved.lastPathComponent)"
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

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

struct ContentView: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        Form {
            if model.needsPermission {
                Section {
                    Text("OP1 Control needs Input Monitoring to talk to the mouse. macOS asks for it because the OP1 also reports itself as a keyboard. Turn on OP1 Control, then quit and reopen this app.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Privacy Settings") { model.openPrivacySettings() }
                }
            }
            Section {
                LabeledContent("Mouse", value: model.connected ? "Endgame Gear OP1 8k" : "Not connected")
                if let firmware = model.firmware {
                    LabeledContent("Firmware", value: firmware)
                }
                LabeledContent("Polling rate on mouse", value: model.current?.label ?? "–")
                if let hz = model.systemHz {
                    LabeledContent("USB report interval", value: "\(hz) Hz")
                }
            }
            Section {
                LabeledContent("Measured rate") {
                    HStack {
                        if let hz = model.measuredHz {
                            Text("≈ \(hz) Hz")
                        }
                        Button(model.measuring ? "Measuring…" : "Measure") { model.measure() }
                            .disabled(model.measuring)
                    }
                }
                Text(model.measureNote ?? "Counts the updates the mouse actually sends while you move it for 4 seconds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Picker("New rate", selection: $model.selected) {
                    ForEach(PollingRate.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("1000 Hz is smoothest on macOS. Higher rates flood the window server and make drags stutter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = model.message {
                Text(message)
                    .foregroundStyle(model.isError ? .red : .secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                Button("Apply") { model.apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.connected || model.selected == model.current)
            }
        }
        .disabled(model.isBusy)
    }
}
