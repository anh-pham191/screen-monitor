import ServiceManagement
import SwiftUI
import LGKit

/// One Section per feature area, so later features each add their own section here.
struct SettingsView: View {
    var body: some View {
        Form {
            InputsSection()
            GeneralSection()
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Inputs

private struct InputsSection: View {
    var body: some View {
        Section {
            ForEach(Input.allCases, id: \.self) { InputValueField(input: $0) }
        } header: {
            Text("Inputs")
        } footer: {
            Text("The LG lists 0x0F for its USB-C port. Not tested yet; if it doesn’t switch, try another value from Details › Inputs advertised by monitor.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct InputValueField: View {
    let input: Input
    @EnvironmentObject private var model: MonitorModel
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(input.label) {
            VStack(alignment: .trailing, spacing: 2) {
                TextField(input.label, text: $text)
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80)
                    .focused($focused)
                    .onSubmit(commit)
                if invalid {
                    Text("Use a hex value such as 0x0F").font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .onAppear(perform: showStored)
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func showStored() {
        text = InputConfig.formatHex(model.inputConfig.value(for: input))
    }

    private func commit() {
        guard let value = InputConfig.parseHex(text) else {
            invalid = true
            showStored()
            return
        }
        invalid = false
        model.inputConfig.set(value, for: input)
        showStored()
    }
}

// MARK: General

private struct GeneralSection: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        Section("General") {
            Toggle(isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: setLaunchAtLogin)) {
                Text("Launch at login")
                Text("Keeps the menu bar icon ready after a restart.")
            }
            .toggleStyle(.switch)
            if status == .requiresApproval {
                HStack {
                    Text("Approve in System Settings").foregroundStyle(.orange)
                    Spacer()
                    Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        // Login items can change in System Settings while the app runs.
        .onAppear { status = SMAppService.mainApp.status }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
