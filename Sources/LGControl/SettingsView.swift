import ServiceManagement
import SwiftUI
import LGKit

/// One Section per feature area, so later features each add their own section here.
struct SettingsView: View {
    var body: some View {
        Form {
            InputsSection()
            KeyboardSection()
            WindowsSection()
            BrightnessSyncSection()
            GeneralSection()
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Inputs

private struct InputsSection: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        Section {
            Picker("Switch command", selection: Binding(
                get: { model.inputConfig.command },
                set: { model.inputConfig.setCommand($0) })) {
                ForEach(InputCommand.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            ForEach(Input.allCases, id: \.self) { InputValueField(input: $0) }
        } header: {
            Text("Inputs")
        } footer: {
            Text("LG monitors switch inputs reliably only with LG’s own command. Standard (VCP 0x60) makes this LG bounce back to the Mac. USB-C 0xD1 is not tested yet.")
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
        // Changing the switch command resets the values, so show the new ones.
        .onChange(of: model.inputConfig.command) { _, _ in invalid = false; showStored() }
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

// MARK: Keyboard

private struct KeyboardSection: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        Section {
            if !model.accessibilityTrusted {
                HStack {
                    Text("Accessibility permission needed for keyboard keys and screen split")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open System Settings") { Accessibility.openSettings() }
                }
            }
            Toggle(isOn: $model.keysEnabled) {
                Text("Control brightness and volume keys")
                Text("Brightness keys change the LG while the pointer is on it. Volume and mute change the LG while it’s the sound output. Hold ⌥⇧ for smaller steps.")
            }
            .toggleStyle(.switch)
            if model.keysEnabled && model.accessibilityTrusted && !model.keyTapActive {
                Text("Keyboard keys couldn’t start — try toggling them off and on, or relaunch.")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Keyboard")
        }
        // The grant can change in System Settings while the app runs.
        .onAppear { model.recheckAccessibility() }
    }
}

// MARK: Windows

private struct WindowsSection: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        Section {
            Toggle(isOn: $model.splitEnabled) {
                Text("Screen split (drag a window onto the LG)")
                Text("While you drag a window on the LG, two halves appear. Drop it on one to fill that half.")
            }
            .toggleStyle(.switch)
        } header: {
            Text("Windows")
        }
    }
}

// MARK: Brightness

private struct BrightnessSyncSection: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        Section {
            Toggle(isOn: $model.syncEnabled) {
                Text("Follow MacBook brightness")
                Text("The LG keeps the difference it has when you turn this on. Changing the LG yourself sets a new difference.")
            }
            .toggleStyle(.switch)
            LabeledContent("Offset") {
                HStack(spacing: 10) {
                    Text(Self.format(model.syncOffset)).monospacedDigit().foregroundStyle(.secondary)
                    Button("Reset") { model.resetSyncOffset() }
                        .disabled(model.syncOffset == 0)
                }
            }
        } header: {
            Text("Brightness")
        }
    }

    private static func format(_ offset: Int) -> String {
        offset > 0 ? "+\(offset)" : offset < 0 ? "−\(-offset)" : "0"
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
