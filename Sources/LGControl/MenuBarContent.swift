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
            // One row of six: the panel is 300 pt wide, so labels stay short and nothing wraps.
            HStack(spacing: 4) {
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
            let total = keepAwake.activePreset?.duration ?? 0
            RingCard(progress: KeepAwakePolicy.ringProgress(remaining: remaining, total: total),
                     title: KeepAwakePolicy.clockText(remaining),
                     subtitle: keepAwake.timerEnd.map {
                         "until " + $0.formatted(Date.FormatStyle().hour().minute())
                     } ?? "",
                     stop: keepAwake.stop)
        case .otherInput where keepAwake.decision.hold:
            // No stop button: the away rule is a setting, and the card can't switch it off.
            RingCard(progress: 1, title: "PS5", subtitle: "while the PS5 is on", stop: nil)
        default:
            EmptyView()
        }
    }
}

private struct RingCard: View {
    let progress: Double
    let title: String
    let subtitle: String
    let stop: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(2)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let stop {
                Button(action: stop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop Keep Awake")
            }
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
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
