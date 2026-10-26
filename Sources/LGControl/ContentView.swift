import SwiftUI
import LGKit

struct ContentView: View {
    @EnvironmentObject private var model: MonitorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeaderCard()
            // Always shown: they work even while a refresh says the LG isn't answering, and
            // these are how Anh gets it back. `switchTo` finds the transport again itself.
            VStack(alignment: .leading, spacing: 6) {
                Text("Input").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                InputSegments()
                if !model.connected {
                    Text("Input buttons always work, so you can switch the LG back to this Mac.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if model.connected {
                PictureBox()
                SoundBox()
            } else {
                NotConnectedBox()
            }
            Spacer(minLength: 0)
            HStack {
                Button("Details") {
                    openWindow(id: "details")
                    AppPresentation.bringToFront()
                }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .simultaneousGesture(TapGesture().onEnded { AppPresentation.bringToFront() })
                    .help("Settings")
            }
        }
        .padding(20)
        .frame(width: 480)
        .frame(minHeight: 560)
        .onAppear { if model.details == nil { model.loadDetails() } }
    }
}

/// LG name, how it's connected, and whether it's answering DDC.
struct HeaderCard: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(systemName: "display").font(.system(size: 28, weight: .light))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.details?.edid?.name ?? "LG").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(model.connected ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text(model.connected ? "Connected" : "Not answering")
                        .font(.caption)
                        .foregroundStyle(model.connected ? Color.green : Color.orange)
                }
            }
            .padding(6)
        }
    }

    private var subtitle: String {
        if !model.connected, let input = model.lastInput, input != model.macPort { return "Showing \(input.label)" }
        return model.details.map(DetailsFormat.headerSubtitle) ?? "No external display found"
    }
}

/// Buttons rather than a segmented Picker: re-pressing the selected input must still send it,
/// because the LG may have been switched from its own buttons.
struct InputSegments: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Input.allCases, id: \.self) { input in
                let selected = model.lastInput == input
                Button { model.switchTo(input) } label: {
                    Text(input.label)
                        .fontWeight(selected ? .semibold : .regular)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(selected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(selected ? 0.18 : 0), radius: 1, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ValueSlider: View {
    let title: String
    let value: Double
    let maximum: Double
    var valueText: String?
    var lowIcon: String?
    var highIcon: String?
    let set: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText ?? String(Int(value.rounded()))).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 10) {
                if let lowIcon { Image(systemName: lowIcon).foregroundStyle(.secondary) }
                Slider(value: Binding(get: { value }, set: set), in: 0...maximum)
                    .accessibilityLabel(title)
                if let highIcon { Image(systemName: highIcon).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct PictureBox: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        GroupBox {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    ValueSlider(title: "Brightness", value: model.brightness, maximum: model.brightnessMax,
                                lowIcon: "sun.min", highIcon: "sun.max", set: model.setBrightness)
                    if model.syncEnabled {
                        Text("Following MacBook").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ValueSlider(title: "Contrast", value: model.contrast, maximum: model.contrastMax,
                            set: model.setContrast)
            }
            .padding(8)
        }
    }
}

private struct SoundBox: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        GroupBox {
            VStack(spacing: 14) {
                ValueSlider(title: "Volume", value: model.volume, maximum: model.volumeMax,
                            valueText: model.muted ? "Muted" : nil,
                            lowIcon: "speaker.fill", highIcon: "speaker.wave.2.fill", set: model.setVolume)
                Toggle("Mute", isOn: Binding(get: { model.muted }, set: model.setMuted))
                    .toggleStyle(.switch)
            }
            .padding(8)
        }
    }
}

private struct NotConnectedBox: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
                Text("LG not connected").font(.headline)
                Text("Brightness, contrast and volume come back as soon as the LG answers — Screen Monitor keeps checking.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                RetryButton()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

struct RetryButton: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        HStack(spacing: 8) {
            Button("Retry") { model.refresh() }
                .buttonStyle(.borderedProminent)
                .disabled(model.refreshing)
            if model.refreshing { ProgressView().controlSize(.small) }
        }
    }
}
