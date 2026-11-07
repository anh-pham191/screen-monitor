import AppKit
import SwiftUI
import LGKit

struct MenuBarContent: View {
    @EnvironmentObject private var model: MonitorModel
    @EnvironmentObject private var software: SoftwareBrightness
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Inputs only mean something while the hardware screen is plugged in; without it (an
            // office with only DisplayLink screens) the panel starts with those screens instead.
            if model.hasHardwareScreen {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.details?.edid?.name ?? "Screen").font(.headline).lineLimit(1)
                    Spacer()
                    Text(model.details?.connection ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                // Shown even while the screen isn't answering: they're the way back to this Mac.
                VStack(spacing: 2) {
                    ForEach(Input.allCases, id: \.self) { input in
                        MenuRow(title: input.label, detail: input == model.macPort ? "This Mac" : nil,
                                checked: model.lastInput == input,
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
                        Text("Not answering").foregroundStyle(.secondary)
                        Spacer()
                        RetryButton()
                    }
                }
            }
            ForEach(Array(software.screens.enumerated()), id: \.element.id) { index, screen in
                if model.hasHardwareScreen || index > 0 { Divider() }
                SoftwareScreenRow(screen: screen)
            }
            if model.hasHardwareScreen || !software.screens.isEmpty { Divider() }
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
    var detail: String?
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
                Text(title).lineLimit(1)
                Spacer()
                if let detail {
                    Text(detail).font(.caption)
                        .foregroundStyle(highlighted ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
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

/// A screen without hardware control: its name as the section label, then a brightness slider
/// that dims it in software.
private struct SoftwareScreenRow: View {
    @EnvironmentObject private var software: SoftwareBrightness
    let screen: SoftwareScreen

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(screen.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            ValueSlider(title: "Brightness", value: Double(screen.level), maximum: 100) {
                software.setLevel(Int($0.rounded()), for: screen.id)
            }
            if software.warmthEnabled {
                ValueSlider(title: "Warmth", value: Double(screen.warmth), maximum: 100) {
                    software.setWarmth(Int($0.rounded()), for: screen.id)
                }
            }
        }
    }
}

private struct KeepAwakeSection: View {
    @EnvironmentObject private var keepAwake: KeepAwakeModel
    @EnvironmentObject private var monitor: MonitorModel

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
            RingCard(progress: 1, title: monitor.lastInput?.label ?? "Other input",
                     subtitle: "while the screen shows it", stop: nil)
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
