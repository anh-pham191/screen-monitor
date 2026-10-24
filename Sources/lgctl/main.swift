import Foundation
import LGKit

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

func hex(_ text: String) -> UInt8? { UInt8(text, radix: 16) }

let args = Array(CommandLine.arguments.dropFirst())
let usage = "usage: lgctl read <hex> [--raw] | set <hex> <hex> | caps | info"

guard let command = args.first else { fail(usage, status: 2) }

switch (command, args.count) {
case ("read", 2...3):
    guard let code = hex(args[1]), args.count == 2 || args[2] == "--raw" else { fail(usage, status: 2) }
    guard let transport = findExternalTransport() else { fail("LG not connected", status: 1) }
    let ddc = DDCController(transport: transport)
    do {
        let reading = try ddc.read(code)
        print("0x\(String(code, radix: 16)) current=\(reading.current) max=\(reading.maximum)")
        if args.count == 3, let raw = ddc.lastRawReply {
            print(raw.map { String(format: "%02x", $0) }.joined(separator: " "))
        }
    } catch {
        fail("\(error)", status: 1)
    }
case ("set", 3):
    guard let code = hex(args[1]), let value = UInt16(args[2], radix: 16) else { fail(usage, status: 2) }
    guard let transport = findExternalTransport() else { fail("LG not connected", status: 1) }
    do {
        try DDCController(transport: transport).write(code, value: value)
        print("ok")
    } catch {
        fail("\(error)", status: 1)
    }
case ("caps", 1):
    guard let transport = findExternalTransport() else { fail("LG not connected", status: 1) }
    do {
        let text = try DDCController(transport: transport).capabilities()
        print(text)
        let caps = Capabilities.parse(text)
        print("model: \(caps.model ?? "unknown")")
        print("mccs: \(caps.mccsVersion ?? "unknown")")
        let inputs = caps.vcp[0x60] ?? []
        print("inputs (60): \(inputs.map { String(format: "%02x", $0) }.joined(separator: " "))")
    } catch {
        fail("\(error)", status: 1)
    }
case ("info", 1):
    guard let details = DisplayDetailsReader.read() else { fail("LG not connected", status: 1) }
    if let edid = details.edid {
        print("name: \(edid.name ?? "unknown")")
        print("manufacturer: \(edid.manufacturerID)")
        print("product code: \(edid.productCode)")
        print("serial: \(edid.serialString ?? String(edid.serialNumber))")
        print("manufactured: week \(edid.week), \(edid.year)")
        print("size: \(edid.widthCm) × \(edid.heightCm) cm")
    }
    print("connection: \(details.connection ?? "unknown")")
    print("resolution: \(details.pixelWidth) × \(details.pixelHeight) px, looks like \(details.pointWidth) × \(details.pointHeight)")
    print("refresh: \(details.refreshHz.map { "\(Int($0.rounded())) Hz" } ?? "unknown")")
default:
    fail(usage, status: 2)
}
