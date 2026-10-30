import SwiftUI
import OP1Kit

struct ContentView: View {
    static let width: CGFloat = 500

    @ObservedObject var model: MouseModel

    var body: some View {
        Form {
            Section { MouseHeader(model: model) }
            if model.needsPermission {
                Section { PermissionNotice(model: model) }
            } else if let notice = model.notice {
                Section { NoticeRow(notice: notice) }
            }
            if model.connected {
                PollingSection(model: model)
                DPISection(model: model)
            } else if model.hasRead && !model.needsPermission && !model.isBusy {
                Section { NotConnectedView(model: model) }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .toolbar {
            // Push the actions to the trailing edge; the window has no title to fill the space.
            ToolbarSpacer(.flexible)
            ToolbarItemGroup {
                Button("Read Settings Again", systemImage: "arrow.clockwise") { model.refresh() }
                    .help("Read the settings from the mouse again (⌘R)")
                    .disabled(model.isBusy)
                Button("Revert", systemImage: "arrow.uturn.backward") { model.revert() }
                    .help("Drop the changes you haven't applied")
                    .disabled(!model.hasChanges || model.isBusy)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button("Apply") { model.apply() }
                    .buttonStyle(.borderedProminent)
                    .help("Write the polling rate and DPI levels to the mouse (⌘S)")
                    .disabled(!model.canApply)
            }
        }
        .animation(.default, value: model.connected)
        .animation(.default, value: model.notice)
    }
}

// MARK: Header

/// What the window is about: the mouse, its firmware, and whether it is connected.
struct MouseHeader: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.14), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("OP1 8k")
                    .font(.title3.weight(.semibold))
                Text(model.firmware.map { "Endgame Gear · Firmware \($0)" } ?? "Endgame Gear")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            status
        }
        .help(model.systemHz.map { "macOS sees a USB report interval of \($0) Hz. That stays at 8000 Hz; the polling rate below decides how often the mouse really reports." } ?? "")
    }

    @ViewBuilder private var status: some View {
        if model.isBusy && !model.connected {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading…")
            }
            .foregroundStyle(.secondary)
        } else if model.connected {
            StatusLabel(text: "Connected", color: .green)
        } else if model.needsPermission {
            StatusLabel(text: "No access", color: .orange)
        } else {
            StatusLabel(text: "Not connected", color: .secondary)
        }
    }
}

/// A colored dot with a word, so the status never rests on color alone.
struct StatusLabel: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

// MARK: Notices and empty states

struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.text)
                if let detail = notice.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: notice.kind == .done ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(notice.kind == .done ? .green : .orange)
        }
    }
}

struct PermissionNotice: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Input Monitoring")
                        .font(.headline)
                    Text("The OP1 also reports itself as a keyboard, so macOS asks before an app can talk to it. Turn on OP1 Control in Privacy & Security, then quit and reopen this app.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
            }
            Button("Open Privacy Settings…") { model.openPrivacySettings() }
                .padding(.leading, 28)
        }
        .padding(.vertical, 4)
    }
}

struct NotConnectedView: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cable.connector")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Plug in your OP1 8k")
                .font(.headline)
            Text("Connect the mouse with its USB cable, then read its settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { model.refresh() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: Polling rate

struct PollingSection: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        Section {
            LabeledContent("Supported") {
                Picker("Supported", selection: model.pollingRate) {
                    ForEach(PollingRate.official) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            // Both pickers share one value; each shows no selection when the rate is in the other.
            LabeledContent("Experimental") {
                Picker("Experimental", selection: model.pollingRate) {
                    ForEach(PollingRate.allCases.filter(\.isExperimental)) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Rates Endgame Gear's own tools don't offer")
            }
            MeasureRow(model: model)
        } header: {
            Text("Polling Rate")
        } footer: {
            Group {
                if model.pollingRate.wrappedValue.isExperimental {
                    Text("Endgame Gear doesn't offer \(model.pollingRate.wrappedValue.label). After you apply it, measure to check the mouse really reports at that rate.")
                } else {
                    Text("1000 Hz is smoothest on macOS. Higher rates flood the window server and make drags stutter.")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Counts the reports the mouse sends while it moves, and compares them with the rate on the mouse.
struct MeasureRow: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                if let ends = model.measureEnds {
                    ProgressView(timerInterval: ends.addingTimeInterval(-MouseModel.measureSeconds)...ends,
                                 countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.linear)
                        .frame(width: 64)
                } else if let hz = model.measuredHz {
                    result(hz)
                }
                Button("Measure") { model.measure() }
                    .disabled(model.measuring)
                    .help("Count the reports the mouse sends while you move it (⇧⌘M)")
            }
        } label: {
            Text("Measured rate")
            Text(model.measureNote ?? "Move the mouse for \(Int(MouseModel.measureSeconds)) seconds.")
        }
    }

    private func result(_ hz: Int) -> some View {
        let expected = model.measuredAgainst?.rawValue ?? hz
        let matches = abs(hz - expected) * 100 <= expected * 15
        return Label {
            Text(verbatim: "≈ \(hz) Hz").monospacedDigit()
        } icon: {
            Image(systemName: matches ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(matches ? .green : .orange)
        }
        .help(matches ? "Matches the \(expected) Hz set on the mouse" : "The mouse is set to \(expected) Hz")
    }
}

// MARK: DPI

struct DPISection: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        Section {
            LabeledContent("Levels in use") {
                Picker("Levels in use", selection: model.activeLevels) {
                    ForEach(1...MouseSettings.dpiLevelCount, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Toggle("Separate X and Y", isOn: model.separate)
            ForEach(0..<MouseSettings.dpiLevelCount, id: \.self) { level in
                DPIRow(model: model, level: level)
            }
        } header: {
            Text("DPI")
                // The DPI fields appear once the mouse is read; keep them from opening focused.
                .background(NoInitialFocus())
        } footer: {
            Text("The DPI button under the mouse steps through the levels in use.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DPIRow: View {
    @ObservedObject var model: MouseModel
    let level: Int

    var body: some View {
        let inUse = level < model.activeLevels.wrappedValue
        LabeledContent {
            HStack(spacing: 16) {
                if model.separateXY {
                    DPIField(axis: "X", level: level, value: model.dpi(level, .x))
                    DPIField(axis: "Y", level: level, value: model.dpi(level, .y))
                } else {
                    DPIField(axis: nil, level: level, value: model.dpi(level, .both))
                }
            }
            .opacity(inUse ? 1 : 0.45)
        } label: {
            Text("Level \(level + 1)")
            if !inUse { Text("Not in use") }
        }
    }
}

/// A DPI number with a stepper. Values snap to the nearest valid DPI when the field commits.
struct DPIField: View {
    let axis: String?
    let level: Int
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 4) {
            if let axis {
                Text(axis).foregroundStyle(.secondary)
            }
            TextField("DPI", value: $value, format: .number.grouping(.never))
                .labelsHidden()
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .accessibilityLabel("Level \(level + 1) \(axis.map { "\($0) " } ?? "")DPI")
            Stepper("", value: $value, in: MouseSettings.dpiRange, step: MouseSettings.dpiStep)
                .labelsHidden()
        }
        .help("50 to 26000 DPI, in steps of 50")
    }
}

/// Clears the window's first responder when it appears, so no field opens focused
/// with its text selected. Tab still moves into the fields.
struct NoInitialFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
        }
    }
}
