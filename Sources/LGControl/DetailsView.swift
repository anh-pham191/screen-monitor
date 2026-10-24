import SwiftUI
import LGKit

struct DetailsView: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        Form {
            Section("Display") {
                if let d = model.details {
                    if let edid = d.edid {
                        row("Name", edid.name ?? DetailsFormat.missing)
                        row("Manufacturer", edid.manufacturerID)
                        row("Product code", String(edid.productCode))
                        row("Serial", edid.serialString ?? String(edid.serialNumber))
                        row("Manufactured", "Week \(edid.week), \(edid.year)")
                        row("Size", "\(edid.widthCm) × \(edid.heightCm) cm")
                    }
                    row("Connection", d.connection ?? DetailsFormat.missing)
                    row("Resolution", DetailsFormat.resolution(d))
                    row("Refresh", DetailsFormat.refresh(d))
                } else {
                    Text("No external display found").foregroundStyle(.secondary)
                }
            }
            Section("Current values") {
                row("Brightness", DetailsFormat.reading(model.raw[VCP.brightness]), mono: true)
                row("Contrast", DetailsFormat.reading(model.raw[VCP.contrast]), mono: true)
                row("Volume", DetailsFormat.reading(model.raw[VCP.volume]), mono: true)
                row("Mute", DetailsFormat.reading(model.raw[VCP.mute]), mono: true)
                row("Input", DetailsFormat.reading(model.raw[VCP.inputSource]), mono: true)
            }
            Section("Monitor capabilities") {
                row("Model", model.capabilities?.model ?? DetailsFormat.missing)
                row("MCCS version", model.capabilities?.mccsVersion ?? DetailsFormat.missing)
                LabeledContent("Inputs advertised by monitor") {
                    if model.loadingCapabilities {
                        ProgressView().controlSize(.small)
                    } else if let error = model.capabilitiesError {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text(model.capabilities?.vcp[VCP.inputSource].map(DetailsFormat.hexList) ?? DetailsFormat.missing)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                // Best-effort: shows exactly what the LG sent, including anything the parser skipped.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capabilities string")
                    Text(model.capabilitiesRaw ?? DetailsFormat.missing)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 600)
        .toolbar {
            Button("Refresh") {
                model.refresh()
                model.loadDetails(forceCapabilities: true)
            }
        }
        .onAppear { model.loadDetails() }
    }

    private func row(_ title: String, _ value: String, mono: Bool = false) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
    }
}
