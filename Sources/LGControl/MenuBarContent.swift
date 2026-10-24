import AppKit
import SwiftUI
import LGKit

struct MenuBarContent: View {
    @EnvironmentObject private var model: MonitorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.details?.edid?.name ?? "LG").font(.headline)
                Spacer()
                Text(model.details?.connection ?? "").font(.caption).foregroundStyle(.secondary)
            }
            // Always shown, like the main window: they're the way back when the LG isn't answering.
            VStack(spacing: 2) {
                ForEach(Input.allCases, id: \.self) { input in
                    MenuRow(title: input.label, checked: model.lastInput == input,
                            highlighted: model.lastInput == input) { model.switchTo(input) }
                }
            }
            Divider()
            if model.connected {
                ValueSlider(title: "Brightness", value: model.brightness, maximum: model.brightnessMax,
                            set: model.setBrightness)
                ValueSlider(title: "Volume", value: model.volume, maximum: model.volumeMax,
                            valueText: model.muted ? "Muted" : nil, set: model.setVolume)
            } else {
                HStack {
                    Text("LG not connected").foregroundStyle(.secondary)
                    Spacer()
                    RetryButton()
                }
            }
            Divider()
            KeepAwakeSection()
            Divider()
            VStack(spacing: 2) {
                MenuRow(title: "Open Screen Monitor") {
                    openWindow(id: "main")
                    AppPresentation.bringToFront()
                }
                MenuRow(title: "Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { if model.details == nil { model.loadDetails() } }
    }
}

private struct MenuRow: View {
    let title: String
    var checked: Bool?
    var highlighted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let checked {
                    Image(systemName: "checkmark").opacity(checked ? 1 : 0).font(.caption)
                }
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        if highlighted { return AnyShapeStyle(Color.accentColor) }
        return hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
    }
}

private struct KeepAwakeSection: View {
    @EnvironmentObject private var keepAwake: KeepAwakeModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Keep Awake").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if keepAwake.decision.hold, let reason = KeepAwakeState.reasonLabel(keepAwake.decision.reason) {
                    Text(reason).font(.system(size: 11)).foregroundStyle(.green)
                }
            }
            card
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(KeepAwakePreset.allCases, id: \.self) { preset in
                    PresetButton(label: preset.label, on: keepAwake.activePreset == preset) {
                        keepAwake.start(preset)
                    }
                }
            }
            if case .lowBattery(let threshold) = keepAwake.lastStop {
                Text("Stopped: battery below \(threshold)%").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var card: some View {
        switch keepAwake.decision.reason {
        case .timer(let remaining) where keepAwake.decision.hold:
            HStack(spacing: 10) {
                Image(systemName: "clock").font(.system(size: 18)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(KeepAwakePolicy.longText(remaining))
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                    if let end = keepAwake.timerEnd {
                        Text("Until \(end.formatted(Date.FormatStyle().hour().minute()))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Stop") { keepAwake.stop() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        case .ps5 where keepAwake.decision.hold:
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller").font(.system(size: 18)).foregroundStyle(Color.accentColor)
                Text("Keeping awake while the PS5 is on").font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        default:
            EmptyView()
        }
    }
}

private struct PresetButton: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.background),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.4)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
