import CoreGraphics
import Foundation
import LGKit

/// Warmth for screens without hardware control, through their colour tables: each channel of the
/// screen's own table is scaled, which removes blue the way Night Shift does. macOS puts the
/// tables back when the app quits.
///
/// Never calls `CGDisplayRestoreColorSyncSettings()`: that resets every display, including
/// Night Shift on the others. Warmth 0 writes the captured table back instead.
@MainActor
final class ColorTables {
    private struct Table: Equatable {
        var red: [Float]
        var green: [Float]
        var blue: [Float]
    }

    /// Each display's table as it was before the first write, kept for the life of the process.
    /// Never recaptured: reading after a write would compound the warmth.
    private var bases: [CGDirectDisplayID: Table] = [:]
    /// What was last written to each warmed display; empty when nothing is warm.
    private var written: [CGDirectDisplayID: Table] = [:]
    nonisolated(unsafe) private var check: Timer?

    deinit {
        // Timer isn't Sendable, but invalidate is the only call made on it and that's on main.
        check?.invalidate()
    }

    /// The full wanted state: effective warmth per software display. Any display warmed before
    /// but missing here (gone, or now the hardware screen) gets its own table back.
    func update(_ warmths: [CGDirectDisplayID: Int]) {
        for id in written.keys where warmths[id] == nil { restore(id) }
        for (id, warmth) in warmths {
            guard warmth > 0 else {
                if written[id] != nil { restore(id) }
                continue
            }
            guard let base = base(of: id) else { continue }
            let m = ColorTemperature.multipliers(warmth: warmth)
            let table = Table(red: ColorTemperature.scaled(base.red, by: m.red),
                              green: ColorTemperature.scaled(base.green, by: m.green),
                              blue: ColorTemperature.scaled(base.blue, by: m.blue))
            // Written even when unchanged: after a wake or screen change macOS may have reset it.
            if write(table, to: id) { written[id] = table } else { written.removeValue(forKey: id) }
        }
        updateCheck()
    }

    private func restore(_ id: CGDirectDisplayID) {
        written.removeValue(forKey: id)
        if let base = bases[id] { _ = write(base, to: id) }
    }

    private func base(of id: CGDirectDisplayID) -> Table? {
        if let base = bases[id] { return base }
        guard let table = read(id) else { return nil }
        bases[id] = table
        return table
    }

    private func read(_ id: CGDirectDisplayID) -> Table? {
        let reported = CGDisplayGammaTableCapacity(id)
        let capacity = reported > 0 ? reported : 256
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &count) == .success,
              count > 0 else { return nil }
        let n = Int(count)
        return Table(red: Array(red.prefix(n)), green: Array(green.prefix(n)), blue: Array(blue.prefix(n)))
    }

    private func write(_ table: Table, to id: CGDirectDisplayID) -> Bool {
        CGSetDisplayTransferByTable(id, UInt32(table.red.count), table.red, table.green, table.blue) == .success
    }

    // MARK: Check

    /// Something else (a display reconfiguration, another app) can reset a table; put ours back.
    private func verify() {
        for (id, table) in written {
            guard let current = read(id) else { continue }
            if !Self.matches(current, table) { _ = write(table, to: id) }
        }
    }

    private static func matches(_ a: Table, _ b: Table) -> Bool {
        func close(_ x: Float?, _ y: Float?) -> Bool {
            guard let x, let y else { return false }
            return abs(x - y) < 1e-3
        }
        return close(a.red.last, b.red.last) && close(a.green.last, b.green.last) && close(a.blue.last, b.blue.last)
    }

    /// Runs only while some screen is warm.
    private func updateCheck() {
        if !written.isEmpty, check == nil {
            let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.verify() }
            }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            check = t
        } else if written.isEmpty, let t = check {
            t.invalidate()
            check = nil
        }
    }
}
