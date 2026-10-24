import Foundation

/// One refresh pass over the VCP codes the app shows. Pure: the caller supplies the read.
public struct MonitorReadout: Equatable, Sendable {
    /// The sliders and mute toggle are meaningless unless all of these answer.
    public static let requiredCodes: [UInt8] = [VCP.brightness, VCP.contrast, VCP.volume, VCP.mute]

    /// Every reading that came back, for Details.
    public let raw: [UInt8: VCPReading]
    public let isComplete: Bool

    /// MCCS mute: 1 is muted, 2 is not.
    public var muted: Bool? { isComplete ? raw[VCP.mute].map { $0.current == 1 } : nil }

    public static func read(_ read: (UInt8) throws -> VCPReading) -> MonitorReadout {
        var raw: [UInt8: VCPReading] = [:]
        for code in requiredCodes {
            // A silent LG costs several retries per code, so stop at the first miss.
            guard let reading = try? read(code) else { return MonitorReadout(raw: raw, isComplete: false) }
            raw[code] = reading
        }
        // The LG often doesn't report its input, so a failure here isn't a disconnect.
        if let input = try? read(VCP.inputSource) { raw[VCP.inputSource] = input }
        return MonitorReadout(raw: raw, isComplete: true)
    }
}

/// Text shown in the header card and the Details window.
public enum DetailsFormat {
    public static let missing = "—"

    public static func reading(_ reading: VCPReading?) -> String {
        reading.map { "\($0.current) / \($0.maximum)" } ?? missing
    }

    public static func hexList(_ values: [UInt8]) -> String {
        values.map { InputConfig.formatHex(UInt16($0)) }.joined(separator: " ")
    }

    public static func headerSubtitle(_ d: DisplayDetails) -> String {
        [d.connection, "\(d.pixelWidth) × \(d.pixelHeight)", d.refreshHz.map(hz)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    public static func resolution(_ d: DisplayDetails) -> String {
        "\(d.pixelWidth) × \(d.pixelHeight) px, looks like \(d.pointWidth) × \(d.pointHeight)"
    }

    public static func refresh(_ d: DisplayDetails) -> String {
        d.refreshHz.map(hz) ?? missing
    }

    private static func hz(_ value: Double) -> String { "\(Int(value.rounded())) Hz" }
}

extension InputConfig {
    /// Unreadable data (not JSON, wrong types) falls back to defaults; missing keys are handled by the decoder.
    public static func decodeOrDefault(_ data: Data?) -> InputConfig {
        data.flatMap { try? JSONDecoder().decode(InputConfig.self, from: $0) } ?? InputConfig()
    }
}
