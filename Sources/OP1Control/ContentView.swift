import SwiftUI
import OP1Kit

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
                if let hz = model.systemHz {
                    LabeledContent("USB report interval", value: "\(hz) Hz")
                }
            }
            pollingSection
            DPISection(model: model)
            measureSection
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
                    .help("Read the settings from the mouse again")
                Button("Revert") { model.revert() }
                    .disabled(!model.hasChanges)
                    .help("Drop edits that were not applied")
                Button("Apply") { model.apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasChanges)
                    .help("Write the polling rate and DPI levels to the mouse")
            }
        }
        .disabled(model.isBusy)
    }

    private var pollingSection: some View {
        Section {
            Picker("Polling rate", selection: model.pollingRate) {
                ForEach(PollingRate.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!model.connected)
        } footer: {
            Text("1000 Hz is smoothest on macOS. Higher rates flood the window server and make drags stutter.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var measureSection: some View {
        Section {
            LabeledContent("Measured rate") {
                HStack {
                    if let hz = model.measuredHz {
                        Text(verbatim: "≈ \(hz) Hz")
                    }
                    Button(model.measuring ? "Measuring…" : "Measure") { model.measure() }
                        .disabled(model.measuring)
                }
            }
        } footer: {
            Text(model.measureNote ?? "Counts the updates the mouse actually sends while you move it for 4 seconds.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DPISection: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        Section {
            Picker("DPI levels", selection: model.activeLevels) {
                ForEach(1...MouseSettings.dpiLevelCount, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Separate X and Y", isOn: model.separate)
            ForEach(0..<MouseSettings.dpiLevelCount, id: \.self) { level in
                let active = level < model.activeLevels.wrappedValue
                LabeledContent("Level \(level + 1)") {
                    HStack(spacing: 12) {
                        if model.separateXY {
                            DPIField(label: "X", level: level, value: model.dpi(level, .x))
                            DPIField(label: "Y", level: level, value: model.dpi(level, .y))
                        } else {
                            DPIField(label: nil, level: level, value: model.dpi(level, .both))
                        }
                    }
                }
                .opacity(active ? 1 : 0.4)
            }
        } header: {
            Text("DPI")
        } footer: {
            Text("The DPI button on the bottom of the mouse cycles through the active levels. 50 to 26000, in steps of 50.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!model.connected)
    }
}

/// A DPI number with a stepper. Values snap to the nearest valid DPI when the field commits.
struct DPIField: View {
    let label: String?
    let level: Int
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 4) {
            if let label {
                Text(label).foregroundStyle(.secondary)
            }
            TextField("DPI", value: $value, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .accessibilityLabel("Level \(level + 1) \(label.map { "\($0) " } ?? "")DPI")
            Stepper("", value: $value, in: MouseSettings.dpiRange, step: MouseSettings.dpiStep)
                .labelsHidden()
        }
    }
}
