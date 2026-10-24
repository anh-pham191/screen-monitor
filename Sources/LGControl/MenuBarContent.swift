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
