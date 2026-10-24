# LG Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that controls the LG UltraFine over DDC/CI: brightness, contrast, volume and mute, input switching between Mac, PS5 and Windows, a Details screen, a menu bar backup, and launch at login.

**Architecture:** A Swift package with three targets. `LGKit` is a library holding the DDC protocol, transport, parsers and pure app logic, all unit-tested with a fake transport. `lgctl` is a small CLI used to verify things on the real monitor. `LGControl` is the SwiftUI app. A shell script packages `LGControl` into an ad-hoc-signed `.app` in `~/Applications`.

**Tech Stack:** Swift 6.3 toolchain (language mode 5), SwiftUI, AppKit, IOKit, private `IOAVService` API, ServiceManagement, Swift Testing, Swift Package Manager, macOS 14+ deployment target, Command Line Tools only (no Xcode).

**Spec:** `docs/superpowers/specs/2026-10-24-lg-control-design.md`

## Global Constraints

- Project root: `<repo root>`. Git is local only (no remote). Before the first commit: `git config user.name "Anh Pham"` and `git config user.email 10724369+anh-pham191@users.noreply.github.com`. Set these per repo, never with `--global`.
- `Package.swift`: `// swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, `swiftLanguageModes: [.v5]`.
- Tests run **only** through `scripts/test.sh`; plain `swift test` cannot find the `Testing` module with Command Line Tools.
- DDC wire constants (verified on the hardware): I2C chip address `0x37`, data address `0x51`, checksum seed `0x6E ^ 0x51`. The LG needs a 50 ms wait between a get request and reading the reply, and 3 attempts for a read. Each set is written twice, 20 ms apart.
- Input values: Mac/HDMI 1 = `0x11`, PS5/HDMI 2 = `0x12` (both verified), Windows/USB-C = `0x0F` (default: the LG advertises inputs `11 12 0F 00` in its capabilities string, read on 2026-10-24, and 0x0F is the only non-HDMI one; not yet switch-tested, and changeable in Settings).
- Do not validate the checksum on DDC replies (the reply checksum convention was not verified on this LG). Validate the reply's structure instead.
- Never call the private API on the main thread. All DDC I/O runs on one serial background `DispatchQueue`.
- UI labels, exactly: `Mac (HDMI 1)`, `PS5 (HDMI 2)`, `Windows (USB-C)`, `Brightness`, `Contrast`, `Volume`, `Mute`, `Details`, `LG not connected`, `Retry`, `Launch at login`, `Open LG Control`, `Quit`.
- App bundle: name `LG Control.app`, bundle id `com.anhpham.lgcontrol`, `LSMinimumSystemVersion` `14.0`, installed to `~/Applications/LG Control.app`.
- Comments explain *why*, not *what*. NZ English in prose and UI copy.

## Review Focus

1. **Monitor missing, asleep or not answering** (another input, cable out). Reads fail after 3 attempts with `DDCError.noReply`, with no endless retry and no main-thread block. The UI shows `LG not connected` and `Retry`, but keeps the input buttons so the Mac can always switch the LG back. Pinned in Task 3 (`readGivesUpAfterThreeAttempts`) and Task 6 (manual checks M5 and M9).
2. **Dragging a slider fast.** Only the first value and the final value are guaranteed to be written, with at most one write per 100 ms. Pinned in Task 4 (`coalescesRapidSubmits`).
3. **Garbage or mismatched DDC replies** (wrong VCP code, an "unsupported" result byte, a short buffer). These are rejected rather than shown as values. Pinned in Task 1 (`rejectsMismatchedReplies`).
4. **Invalid hex typed into Settings** (`""`, `"zz"`, `"10000"`). It is rejected and the previous value is kept. Pinned in Task 4 (`parseHexRejectsBadInput`).
5. **Switching to the PS5 with the lid closed** (no built-in screen). The input still switches, and the window doesn't move. Pinned in Task 4 (`noMoveWithoutBuiltInScreen`).

---

### Task 1: Package scaffold and DDC packets

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`, `*.app`, `.DS_Store`), `scripts/test.sh`
- Create: `Sources/LGKit/DDCPacket.swift`
- Create: placeholders so the package builds: `Sources/lgctl/main.swift` (prints usage), `Sources/LGControl/LGControlApp.swift` (minimal `@main` SwiftUI `App` with one empty `Window("LG Control", id: "main")`)
- Test: `Tests/LGKitTests/DDCPacketTests.swift`

**Interfaces:**
- Produces:
  - `public enum VCP { public static let brightness: UInt8 = 0x10, contrast: UInt8 = 0x12, inputSource: UInt8 = 0x60, volume: UInt8 = 0x62, mute: UInt8 = 0x8D }`
  - `public struct VCPReading: Equatable, Sendable { public let current: UInt16; public let maximum: UInt16 }`
  - `public enum DDCPacket` with `static let chipAddress: UInt32 = 0x37`, `static let dataAddress: UInt32 = 0x51`, `static func getRequest(_ code: UInt8) -> [UInt8]`, `static func setRequest(_ code: UInt8, value: UInt16) -> [UInt8]`, `static func capabilitiesRequest(offset: UInt16) -> [UInt8]`, `static func parseGetReply(_ bytes: [UInt8], code: UInt8) -> VCPReading?`, `static func parseCapabilitiesReply(_ bytes: [UInt8], offset: UInt16) -> [UInt8]?`
- Targets: library `LGKit`; executable `lgctl` (depends on `LGKit`); executable `LGControl` (depends on `LGKit`); test target `LGKitTests` (depends on `LGKit`).

- [ ] **Step 1: Initialise git and the package**

Run `git init` in the project root and set the identity from Global Constraints. Write `Package.swift`, `.gitignore` and the two placeholder sources. Write `scripts/test.sh` (mark it executable):

```bash
#!/usr/bin/env bash
# Command Line Tools ship Swift Testing outside the default search paths.
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
```

- [ ] **Step 2: Write the failing tests** in `Tests/LGKitTests/DDCPacketTests.swift` (`import Testing`, `@testable import LGKit`):

```swift
@Test func getRequestBrightness() { #expect(DDCPacket.getRequest(0x10) == [0x82, 0x01, 0x10, 0xAC]) }
@Test func setRequestHDMI2() { #expect(DDCPacket.setRequest(0x60, value: 0x12) == [0x84, 0x03, 0x60, 0x00, 0x12, 0xCA]) }
@Test func capabilitiesRequestOffset32() { #expect(DDCPacket.capabilitiesRequest(offset: 32) == [0x83, 0xF3, 0x00, 0x20, 0x6F]) }
@Test func parsesBrightnessReply() {
    let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x1A, 0x00]
    #expect(DDCPacket.parseGetReply(reply, code: 0x10) == VCPReading(current: 26, maximum: 100))
}
@Test func rejectsMismatchedReplies() {
    let ok: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x1A, 0x00]
    #expect(DDCPacket.parseGetReply(ok, code: 0x12) == nil)              // different VCP code
    var unsupported = ok; unsupported[3] = 0x01
    #expect(DDCPacket.parseGetReply(unsupported, code: 0x10) == nil)     // result byte says unsupported
    var wrongOpcode = ok; wrongOpcode[2] = 0x00
    #expect(DDCPacket.parseGetReply(wrongOpcode, code: 0x10) == nil)
    #expect(DDCPacket.parseGetReply(Array(ok.prefix(9)), code: 0x10) == nil)
    #expect(DDCPacket.parseGetReply([UInt8](repeating: 0, count: 11), code: 0x10) == nil)
}
@Test func parsesCapabilitiesChunk() {
    // [src, 0x80|len, 0xE3, offHi, offLo, data..., chk]; len counts opcode + offset + data
    let reply: [UInt8] = [0x6E, 0x86, 0xE3, 0x00, 0x20, 0x28, 0x70, 0x72, 0x00]
    #expect(DDCPacket.parseCapabilitiesReply(reply, offset: 32) == [0x28, 0x70, 0x72])
    #expect(DDCPacket.parseCapabilitiesReply(reply, offset: 0) == nil)   // offset mismatch
    #expect(DDCPacket.parseCapabilitiesReply([0x6E, 0x83, 0xE3, 0x00, 0x20, 0x00], offset: 32) == [])  // end marker
}
```

- [ ] **Step 3: Run the tests to verify they fail.** Run `scripts/test.sh`. Expected: compile errors, because `DDCPacket` isn't defined.

- [ ] **Step 4: Implement `DDCPacket` and `VCP`** in `Sources/LGKit/DDCPacket.swift`.
  - Request checksum = `0x6E ^ 0x51 ^` XOR of every request byte.
  - `parseGetReply` accepts the reply only when `count >= 11`, `[1] & 0x80 != 0`, `[2] == 0x02`, `[3] == 0x00` and `[4] == code`. Then maximum = `[6..7]` and current = `[8..9]`, both big-endian. Don't compare `[1]` to `0x88`: the hardware probe never checked that byte, and Task 3 Step 7 confirms it on the monitor.
  - `parseCapabilitiesReply` takes `n = [1] & 0x7F` and requires `[2] == 0xE3`, `n >= 3`, offset `[3..4] == offset`, and `count >= 5 + (n - 3)`. It returns `bytes[5 ..< 5 + n - 3]`.

- [ ] **Step 5: Run the tests to verify they pass.** Run `scripts/test.sh`. Expected: all 6 tests pass. `swift build` also succeeds for all three targets.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore scripts Sources Tests docs
git commit -m "feat: scaffold LG Control package with DDC packet encoding"
```

---

### Task 2: EDID and capabilities parsers

**Files:**
- Create: `Sources/LGKit/EDID.swift`, `Sources/LGKit/Capabilities.swift`
- Test: `Tests/LGKitTests/EDIDTests.swift`, `Tests/LGKitTests/CapabilitiesTests.swift`

**Interfaces:**
- Produces:
  - `public struct EDIDInfo: Equatable, Sendable` with `public let` fields `manufacturerID: String`, `productCode: UInt16`, `serialNumber: UInt32`, `week: Int`, `year: Int`, `widthCm: Int`, `heightCm: Int`, `name: String?`, `serialString: String?`, and a `public init` taking all of them (memberwise, in this order) with `public static func parse(_ bytes: [UInt8]) -> EDIDInfo?`
  - `public struct Capabilities: Equatable, Sendable` with `public let` fields `model: String?`, `mccsVersion: String?`, `vcp: [UInt8: [UInt8]]`, and a `public init(model:mccsVersion:vcp:)` (code → allowed values, empty if none listed) with `public static func parse(_ text: String) -> Capabilities`

- [ ] **Step 1: Write the failing tests.** The EDID test uses the real 128-byte base block captured from this LG:

```swift
let lgEDID = "00ffffffffffff001e6dbb5c0100000001240103803c2278ea1c95af5047aa260f5054210800d1c0614045400101010101010101010108e80030f2705a80b0588a0058542100001e000000fd00283c1e873c000a202020202020000000fc004c4720554c54524146494e450a000000ff0044454d4f31323334353637380a017b"
// helper: hex string → [UInt8]

@Test func parsesLGEDID() {
    #expect(EDIDInfo.parse(bytes(lgEDID)) == EDIDInfo(manufacturerID: "GSM", productCode: 23739, serialNumber: 1,
        week: 1, year: 2026, widthCm: 60, heightCm: 34, name: "LG ULTRAFINE", serialString: "DEMO12345678"))
}
@Test func rejectsBadEDID() {
    #expect(EDIDInfo.parse(Array(bytes(lgEDID).prefix(127))) == nil)       // too short
    var badSum = bytes(lgEDID); badSum[127] &+= 1
    #expect(EDIDInfo.parse(badSum) == nil)                                  // checksum
    var badHeader = bytes(lgEDID); badHeader[0] = 0xFF
    #expect(EDIDInfo.parse(badHeader) == nil)
}
@Test func parsesCapabilitiesString() {
    let caps = Capabilities.parse("(prot(monitor)type(LCD)model(ULTRAFINE)cmds(01 02 03 0C E3 F3)vcp(02 10 12 14(05 08 0B) 60(11 12 0F 1B) 62 8D(01 02) D6(01 04))mccs_ver(2.1))")
    #expect(caps.model == "ULTRAFINE")
    #expect(caps.mccsVersion == "2.1")
    #expect(caps.vcp[0x60] == [0x11, 0x12, 0x0F, 0x1B])
    #expect(caps.vcp[0x10] == [])
    #expect(caps.vcp.count == 8)
}
@Test func capabilitiesToleratesGarbage() {
    #expect(Capabilities.parse("") == Capabilities(model: nil, mccsVersion: nil, vcp: [:]))
    #expect(Capabilities.parse("(vcp(10 12").vcp.isEmpty == false)          // truncated string: keep what parsed
}
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh`. Expected: compile errors.

- [ ] **Step 3: Implement `EDIDInfo.parse`.**
  - Require at least 128 bytes, the header `00 FF FF FF FF FF FF 00`, and a sum of bytes 0–127 that is 0 mod 256.
  - Manufacturer ID: bytes 8–9 as big-endian, three 5-bit letters (`value + 64`).
  - Product code: bytes 10–11, little-endian. Serial number: bytes 12–15, little-endian. Week: byte 16. Year: `1990 + byte 17`. Size: bytes 21 and 22.
  - Name and serial string: from the descriptors at offsets 54, 72, 90 and 108, where the tag `0xFC` is the name and `0xFF` is the serial. Text is bytes `+5 ..< +18`, cut at `0x0A`, with trailing spaces trimmed.

- [ ] **Step 4: Implement `Capabilities.parse`.** Write a small tokenising scan; regular expressions can't handle the nested parentheses. Read `model(...)` and `mccs_ver(...)` as text. Inside `vcp(...)`, read each hex code and the optional parenthesised hex list that follows it. If the input ends early, return whatever has parsed so far.

- [ ] **Step 5: Run the tests to verify they pass.** Run `scripts/test.sh`. Expected: all tests pass.

- [ ] **Step 6: Commit** with the message `feat: parse EDID and DDC capabilities strings`.

---

### Task 3: DDC controller, IOAVService transport, `lgctl` read/set/caps

**Files:**
- Create: `Sources/LGKit/DDCController.swift`, `Sources/LGKit/AVServiceTransport.swift`
- Modify: `Sources/lgctl/main.swift`
- Test: `Tests/LGKitTests/DDCControllerTests.swift`

**Interfaces:**
- Consumes: `DDCPacket`, `VCPReading` (Task 1).
- Produces:
  - `public protocol I2CTransport: AnyObject { func write(dataAddress: UInt32, bytes: [UInt8]) -> Bool; func read(dataAddress: UInt32, count: Int) -> [UInt8]? }`
  - `public enum DDCError: Error, Equatable { case noReply(code: UInt8); case writeFailed(code: UInt8) }`
  - `public final class DDCController: @unchecked Sendable` with `public init(transport: I2CTransport, sleep: @escaping (useconds_t) -> Void = { usleep($0) })`, `public func read(_ code: UInt8) throws -> VCPReading`, `public func write(_ code: UInt8, value: UInt16) throws`, `public func capabilities() throws -> String`. All three calls are serialised with an `NSLock`, because callers may come from any thread.
  - `public final class AVServiceTransport: I2CTransport` and `public func findExternalTransport() -> I2CTransport?`: the first `DCPAVServiceProxy` with `Location == "External"`, wrapped with `IOAVServiceCreateWithService`.

- [ ] **Step 1: Write the failing tests** using a test-only `final class FakeTransport: I2CTransport`, defined in the test file. Its `init(reads: [[UInt8]?])` queues read replies, where `nil` (or an empty queue) means a failed read. It records every write's bytes in `writes: [[UInt8]]` and every read's `count` in `readCounts: [Int]`, and `var writeSucceeds = true` is returned from `write`. The tests also use a recording `sleep` closure:

```swift
@Test func readSendsRequestWaitsAndParses() throws {
    let t = FakeTransport(reads: [[0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x1A, 0x00]])
    var sleeps: [useconds_t] = []
    let c = DDCController(transport: t, sleep: { sleeps.append($0) })
    #expect(try c.read(VCP.brightness) == VCPReading(current: 26, maximum: 100))
    #expect(t.writes == [DDCPacket.getRequest(0x10)])
    #expect(sleeps.first == 50_000)
    #expect(t.readCounts == [11])
}
@Test func readRetriesThenSucceeds() throws {
    let t = FakeTransport(reads: [nil, [UInt8](repeating: 0, count: 11), [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x05, 0x00]])
    #expect(try DDCController(transport: t, sleep: { _ in }).read(0x10).current == 5)
    #expect(t.writes.count == 3)
}
@Test func readGivesUpAfterThreeAttempts() {
    let t = FakeTransport(reads: [nil, nil, nil, nil])
    #expect(throws: DDCError.noReply(code: 0x10)) { try DDCController(transport: t, sleep: { _ in }).read(0x10) }
    #expect(t.writes.count == 3)
}
@Test func writeSendsPacketTwice() throws {
    let t = FakeTransport(reads: [])
    var sleeps: [useconds_t] = []
    try DDCController(transport: t, sleep: { sleeps.append($0) }).write(VCP.inputSource, value: 0x12)
    #expect(t.writes == [DDCPacket.setRequest(0x60, value: 0x12), DDCPacket.setRequest(0x60, value: 0x12)])
    #expect(sleeps.contains(20_000))
}
@Test func enforcesGapBetweenCommands() throws {
    let t = FakeTransport(reads: [[0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x1A, 0x00]])
    var sleeps: [useconds_t] = []
    let c = DDCController(transport: t, sleep: { sleeps.append($0) })   // sleeps are no-ops, so ~no real time passes
    try c.write(VCP.brightness, value: 30)
    let before = sleeps.count
    _ = try c.read(VCP.brightness)
    #expect(sleeps[before] > 40_000 && sleeps[before] <= 50_000)        // gap sleep comes before the get request
}
@Test func writeThrowsWhenBothAttemptsFail() {
    let t = FakeTransport(reads: []); t.writeSucceeds = false
    #expect(throws: DDCError.writeFailed(code: 0x60)) { try DDCController(transport: t, sleep: { _ in }).write(0x60, value: 0x12) }
}
@Test func capabilitiesConcatenatesChunksUntilEmpty() throws {
    let t = FakeTransport(reads: [
        [0x6E, 0x86, 0xE3, 0x00, 0x00, 0x28, 0x76, 0x63, 0x00],   // "(vc" at offset 0
        [0x6E, 0x85, 0xE3, 0x00, 0x03, 0x70, 0x29, 0x00],          // "p)" at offset 3
        [0x6E, 0x83, 0xE3, 0x00, 0x05, 0x00],                      // end
    ])
    #expect(try DDCController(transport: t, sleep: { _ in }).capabilities() == "(vcp)")
    #expect(t.writes == [DDCPacket.capabilitiesRequest(offset: 0), DDCPacket.capabilitiesRequest(offset: 3), DDCPacket.capabilitiesRequest(offset: 5)])
}
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh`. Expected: compile errors.

- [ ] **Step 3: Implement `DDCController`.**
  - `read` makes up to 3 attempts. Each attempt writes `getRequest`, sleeps 50 000 µs, reads 11 bytes and parses. Between failed attempts it sleeps another 50 000 µs.
  - `write` sends the packet, sleeps 20 000 µs, sends it again, then sleeps another 20 000 µs (as the probe did). It throws `writeFailed` only when both sends return `false`.
  - Gap between commands: the controller records when its last operation finished, using `DispatchTime.now()`. Before any new `read`, `write` or capabilities chunk, it sleeps for whatever is left of 50 000 µs. This applies once per operation, not per retry, and there is no gap sleep before the very first operation; `readSendsRequestWaitsAndParses` relies on that. The tests pass a no-op or recording `sleep`, so this must go through the injected `sleep` closure.
  - Capabilities timing: each chunk writes `capabilitiesRequest(offset:)`, sleeps 50 000 µs, then reads 38 bytes.
  - `capabilities` reads chunks of 38 bytes, starting at offset 0. Each chunk is retried up to 3 times, and the offset advances by the chunk's data length. It stops on an empty chunk or once 2048 bytes are collected. It throws `noReply(code: 0xF3)` if a chunk fails 3 times. The result is a Latin-1 string with trailing `0x00` bytes stripped.

- [ ] **Step 4: Implement `AVServiceTransport` and `findExternalTransport()`.** Declare the private symbols exactly as the verified probe (a one-off probe script (not in the repo)) did:

```swift
typealias IOAVService = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?
@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32, _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32, _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32) -> IOReturn
```

Create the service with `IOAVServiceCreateWithService(kCFAllocatorDefault, s)?.takeRetainedValue()`, and only for entries whose `Location` property is `"External"`. Pass chip address `0x37` and data address `0x51` (`DDCPacket.dataAddress`) on every read and write. Success means `kIOReturnSuccess`. Use `IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), …)` and release every `io_object_t`.

- [ ] **Step 5: Implement `lgctl` commands** in `Sources/lgctl/main.swift`:
  - `lgctl read <hex>` prints `0x10 current=26 max=100`.
  - `lgctl set <hex> <hex>` prints `ok` or the error.
  - `lgctl caps` prints the capabilities string, then its parsed `model`, `mccs` and the input values listed under `60`.
  - Anything else prints usage and exits with status 2. If no external display is found, print `LG not connected` and exit with status 1.

- [ ] **Step 6: Run the tests to verify they pass.** Run `scripts/test.sh`. Expected: all tests pass.

- [ ] **Step 7: Verify on the real monitor (read-only).** `lgctl read <hex> --raw` also prints the raw 11 reply bytes in hex. Run `swift run lgctl read 10 --raw && swift run lgctl read 62 && swift run lgctl caps`. Record the raw bytes in the task report, including the value of byte `[1]`. Expected: two lines like `0x10 current=<n> max=100`, then either a capabilities string or a clear error message. The capabilities result is best-effort, so record whatever it prints in the task report. **Do not run `lgctl set` in this task**, because it changes the monitor Anh is using.

- [ ] **Step 8: Commit** with the message `feat: talk DDC/CI to the LG over IOAVService`.

---

### Task 4: Pure app logic (inputs, write coalescing, window placement)

**Files:**
- Create: `Sources/LGKit/InputConfig.swift`, `Sources/LGKit/LatestValueWriter.swift`, `Sources/LGKit/WindowPlacement.swift`
- Test: `Tests/LGKitTests/AppLogicTests.swift`

**Interfaces:**
- Produces:
  - `public enum Input: String, CaseIterable, Codable, Sendable { case mac, ps5, windows }` with `public var label: String`, giving `"Mac (HDMI 1)"`, `"PS5 (HDMI 2)"` and `"Windows (USB-C)"`
  - `public struct InputConfig: Codable, Equatable, Sendable { public var mac: UInt16 = 0x11; public var ps5: UInt16 = 0x12; public var windows: UInt16 = 0x0F; public init() {}; public func value(for: Input) -> UInt16; public mutating func set(_ value: UInt16, for: Input); public static func parseHex(_ text: String) -> UInt16?; public static func formatHex(_ value: UInt16) -> String }`
  - `public final class LatestValueWriter<Value: Sendable>: @unchecked Sendable` with `public init(queue: DispatchQueue, interval: TimeInterval, write: @escaping (Value) -> Void)` and `public func submit(_ value: Value)`
  - `public enum WindowPlacement { public static func shouldMoveToBuiltIn(target: Input, windowOnExternal: Bool, builtInAvailable: Bool) -> Bool }`

- [ ] **Step 1: Write the failing tests**:

```swift
@Test func defaultInputValues() {
    let c = InputConfig()
    #expect([c.value(for: .mac), c.value(for: .ps5), c.value(for: .windows)] == [0x11, 0x12, 0x0F])
    #expect(Input.allCases.map(\.label) == ["Mac (HDMI 1)", "PS5 (HDMI 2)", "Windows (USB-C)"])
}
@Test func parseHexAcceptsCommonForms() {
    #expect(InputConfig.parseHex("1B") == 0x1B)
    #expect(InputConfig.parseHex(" 0x0f ") == 0x0F)
    #expect(InputConfig.parseHex("0XD1") == 0xD1)
    #expect(InputConfig.formatHex(0x1B) == "0x1B")
}
@Test func parseHexRejectsBadInput() {
    for bad in ["", "  ", "zz", "0x", "10000", "-1", "1 2"] { #expect(InputConfig.parseHex(bad) == nil, "\(bad)") }
}
@Test func inputConfigRoundTripsJSON() throws {
    var c = InputConfig(); c.set(0x1B, for: .windows)
    #expect(try JSONDecoder().decode(InputConfig.self, from: JSONEncoder().encode(c)) == c)
}
@Test func coalescesRapidSubmits() {
    let queue = DispatchQueue(label: "test.ddc")
    let lock = NSLock(); var written: [Int] = []
    let w = LatestValueWriter<Int>(queue: queue, interval: 0.1) { v in lock.lock(); written.append(v); lock.unlock() }
    for v in 1...10 { w.submit(v) }
    Thread.sleep(forTimeInterval: 0.4)   // synchronous on purpose: NSLock is unavailable in async contexts
    lock.lock(); defer { lock.unlock() }
    #expect(written.first == 1)
    #expect(written.last == 10)
    #expect(written.count <= 3)
}
@Test func movesOnlyWhenLeavingTheMacFromTheExternalScreen() {
    #expect(WindowPlacement.shouldMoveToBuiltIn(target: .ps5, windowOnExternal: true, builtInAvailable: true))
    #expect(WindowPlacement.shouldMoveToBuiltIn(target: .windows, windowOnExternal: true, builtInAvailable: true))
    #expect(!WindowPlacement.shouldMoveToBuiltIn(target: .mac, windowOnExternal: true, builtInAvailable: true))
    #expect(!WindowPlacement.shouldMoveToBuiltIn(target: .ps5, windowOnExternal: false, builtInAvailable: true))
}
@Test func noMoveWithoutBuiltInScreen() {
    #expect(!WindowPlacement.shouldMoveToBuiltIn(target: .ps5, windowOnExternal: true, builtInAvailable: false))
}
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh`. Expected: compile errors.

- [ ] **Step 3: Implement the three files.**
  - `parseHex` trims whitespace, strips an optional `0x`/`0X` prefix, and parses base 16 into `UInt16`. Empty or invalid input gives `nil`.
  - `formatHex` gives `0x` followed by at least two upper-case hex digits.
  - `LatestValueWriter`: when idle, write the value on `queue` straight away and start a cool-down of `interval`. During the cool-down, keep only the latest pending value. When the cool-down ends, write the pending value if there is one and start a new cool-down; otherwise go idle. Guard the state with an `NSLock`.

- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh`. Expected: all tests pass.

- [ ] **Step 5: Commit** with the message `feat: add input config, write coalescing and window placement rules`.

---

### Task 5: Display details reader and `lgctl info`

**Files:**
- Create: `Sources/LGKit/DisplayDetails.swift`
- Modify: `Sources/lgctl/main.swift`

**Interfaces:**
- Consumes: `EDIDInfo.parse` (Task 2).
- Produces: `public struct DisplayDetails: Equatable, Sendable` with `public let` fields `edid: EDIDInfo?`, `connection: String?`, `pixelWidth: Int`, `pixelHeight: Int`, `pointWidth: Int`, `pointHeight: Int`, `refreshHz: Double?` and `public enum DisplayDetailsReader { public static func read() -> DisplayDetails? }`, which returns `nil` when there is no non-built-in display.

There's no unit test, because the reader is a thin wrapper over the IORegistry and CoreGraphics, and the parsing it relies on is tested in Task 2. It is verified on the hardware in Step 3.

- [ ] **Step 1: Implement `DisplayDetailsReader.read()`.**
  - Display: from `CGGetOnlineDisplayList`, take the first display where `CGDisplayIsBuiltin == 0`. Points come from `CGDisplayBounds`. Pixels and refresh come from `CGDisplayCopyDisplayMode` (`pixelWidth`, `pixelHeight`, `refreshRate`; treat `0` as `nil`).
  - EDID: walk the IOService plane recursively (`IORegistryCreateIterator` with `kIORegistryIterateRecursively`) and take the first entry whose `Metadata` property is a dictionary containing an `EDID` `Data`. Connection is that dictionary's `DFP Type Description` (on this machine, `"HDMI"`).

- [ ] **Step 2: Add `lgctl info`.** It prints one `key: value` line per field: `name`, `manufacturer`, `product code`, `serial`, `manufactured` (`week 1, 2026`), `size` (`60 × 34 cm`), `connection`, `resolution` (`<px> px, looks like <pt>`) and `refresh` (`60 Hz`).

- [ ] **Step 3: Verify on the real monitor.** Run `swift run lgctl info`. Expected: `name: LG ULTRAFINE`, `manufacturer: GSM`, `serial: DEMO12345678`, `manufactured: week 1, 2026`, `connection: HDMI`, and a `resolution` line whose "looks like" figure matches System Settings › Displays (it was 1920 × 1080 on 2026-10-24). The px figure may be the scaled backing size, not 3840 × 2160; report it rather than treating it as a failure. Also run `scripts/test.sh`, and expect it to still pass.

- [ ] **Step 4: Commit** with the message `feat: read LG display details from EDID and CoreGraphics`.

---

### Task 6: SwiftUI app, menu bar, settings, launch at login, packaging

**Files:**
- Create: `Sources/LGControl/MonitorModel.swift`, `Sources/LGControl/ContentView.swift`, `Sources/LGControl/DetailsView.swift`, `Sources/LGControl/SettingsView.swift`, `Sources/LGControl/MenuBarContent.swift`, `Sources/LGControl/WindowMover.swift`
- Modify: `Sources/LGControl/LGControlApp.swift`
- Create: `scripts/build-app.sh`, `Resources/Info.plist`
- Create: `README.md` (what it is, `scripts/build-app.sh`, `scripts/test.sh`, `lgctl` usage, and the USB-C value note)

**Interfaces:**
- Consumes: `DDCController`, `findExternalTransport`, `VCP`, `VCPReading`, `DDCError` (Task 3); `Capabilities` (Task 2); `Input`, `InputConfig`, `LatestValueWriter`, `WindowPlacement` (Task 4); `DisplayDetailsReader`, `DisplayDetails` (Task 5).
- Produces: `@MainActor final class MonitorModel: ObservableObject`, with these published members:
  - `connected: Bool`
  - `brightness`, `contrast`, `volume: Double`, plus their maxima
  - `muted: Bool`
  - `lastInput: Input?`
  - `inputConfig: InputConfig`
  - `details: DisplayDetails?`
  - `capabilities: Capabilities?`, `capabilitiesError: String?`

  And these methods: `refresh()`, `setBrightness(_:)`, `setContrast(_:)`, `setVolume(_:)`, `setMuted(_:)`, `switchTo(_ input: Input)`, `loadDetails()`.

- [ ] **Step 1: Implement `MonitorModel`.**
  - Concurrency: one serial `DispatchQueue(label: "com.anhpham.lgcontrol.ddc")` runs all DDC I/O. The `DDCController?` instance is a private property that is **only read or written on that queue**, never from the main actor. Results are published back with `DispatchQueue.main.async`. Make one `LatestValueWriter` per slider (interval 0.1 s), sharing that queue.
  - State: besides the published values, publish `hasTransport: Bool` (an external AV service was found) and `raw: [UInt8: VCPReading]` (the last good reading per code, for Details).
  - `refresh()`:
    - If a refresh is already running, return straight away, so repeated Retry presses don't pile up.
    - On the queue, find the transport again and set `hasTransport`. Read `0x10`, `0x12`, `0x62` and `0x8D`, which must all succeed, and `0x60`, whose failure is ignored. Store every good reading in `raw`.
    - Mute is `1` = muted and `2` = not muted. If the transport is missing or any of the four required reads throws, set `connected = false`.
  - Persistence: `lastInput` and `inputConfig` (JSON) are stored in `UserDefaults` under `lastInput` and `inputConfig`.
  - `switchTo`: if `WindowPlacement.shouldMoveToBuiltIn(...)` is true, call `WindowMover.moveAppWindowsToBuiltInScreen()` first. Then write `VCP.inputSource` with `inputConfig.value(for:)` and set `lastInput`.
  - `loadDetails()` is called from `DetailsView.onAppear` and by its `Refresh` button. It reads `DisplayDetailsReader.read()` every time, but fetches `capabilities()` only when it isn't cached yet, because a fetch takes seconds. `Refresh` clears the cache. A failure sets `capabilitiesError` and doesn't affect `connected`.
  - Hot-plug: observe `NSApplication.didChangeScreenParametersNotification` and call `refresh()`.

- [ ] **Step 2: Implement `WindowMover`.**
  - `static func moveAppWindowsToBuiltInScreen()`: the built-in screen is the `NSScreen` whose `deviceDescription["NSScreenNumber"]` display ID has `CGDisplayIsBuiltin != 0`. Only windows that are visible, have `styleMask.contains(.titled)` and have `canBecomeMain` count; this skips the status-item and menu bar panel windows. Each one that isn't on the built-in screen is re-centred inside that screen's `visibleFrame`, keeping its size and clamping it to fit.
  - `static func isWindowOnExternal() -> Bool` (same window filter) and `static func builtInAvailable() -> Bool` feed `WindowPlacement`.

- [ ] **Step 3: Implement the views and the app.**
  - `ContentView`:
    - `Brightness`, `Contrast` and `Volume` sliders (0…max), each showing its integer value, and a `Mute` toggle.
    - A row of three input buttons using `Input.label`; `lastInput` is visually selected.
    - A `Details` button that opens `Window("Details", id: "details")`.
    - When `!connected`, the sliders and the mute toggle are replaced by `LG not connected` and a `Retry` button that calls `refresh()`. **The three input buttons stay visible whenever `hasTransport` is true**, even when reads fail. Reads may fail while the LG shows the PS5, and `Mac (HDMI 1)` must still be there to bring it back. The same rule applies in `MenuBarContent`.
  - `DetailsView`: a `Form` with the Task 5 fields, the current raw values from `model.raw` (brightness, contrast, volume, mute and input as `current/max`; any code missing from `raw` shows `—`), `MCCS version` and `Model`, and `Inputs advertised by monitor` (the hex list under `0x60`, or `capabilitiesError`). It has a `Refresh` button.
  - `SettingsView` (the SwiftUI `Settings` scene):
    - One hex text field per input. On commit, use `InputConfig.parseHex`; an invalid value reverts to the stored value and shows a short red hint.
    - A `Launch at login` toggle backed by `SMAppService.mainApp.register()`/`unregister()`, which re-reads `SMAppService.mainApp.status` on appear and shows any thrown error inline. When the status is `.requiresApproval`, it shows `Approve in System Settings` with a button that calls `SMAppService.openSystemSettingsLoginItems()`. The README notes that after reinstalling, you toggle it off and on (the ad-hoc signature changes on every build) and that it doesn't work under `swift run`.
  - `MenuBarContent` (in `MenuBarExtra("LG Control", systemImage: "display")` with **`.menuBarExtraStyle(.window)`**; the default menu style can't show a slider): the three input buttons, a `Brightness` slider, `Open LG Control` (`openWindow(id: "main")` plus `NSApp.activate()`) and `Quit`.
  - `LGControlApp`: the scenes `Window("LG Control", id: "main")`, `Window("Details", id: "details")`, `Settings` and `MenuBarExtra`, with one shared `MonitorModel` as a `@StateObject`. An `NSApplicationDelegateAdaptor` returns `false` from `applicationShouldTerminateAfterLastWindowClosed`, so the menu bar icon stays.

- [ ] **Step 4: Implement packaging.**
  - `Resources/Info.plist` holds the values from Global Constraints, plus `CFBundleExecutable = LGControl`, `CFBundleName = LG Control`, `CFBundlePackageType = APPL`, `CFBundleShortVersionString = 1.0` and `CFBundleVersion = 1`.
  - `scripts/build-app.sh` (`set -euo pipefail`):
    1. `swift build -c release --product LGControl`.
    2. Assemble `.build/LG Control.app/Contents/{MacOS/LGControl,Info.plist}`. Copy the binary from `"$(swift build -c release --show-bin-path)/LGControl"`.
    3. Sign it: `codesign --force --sign - ".build/LG Control.app"`.
    4. Run `pkill -x LGControl || true` and `mkdir -p ~/Applications`.
    5. Replace `~/Applications/LG Control.app`, then print the installed path.

- [ ] **Step 5: Verify the build.** Run `scripts/test.sh`, expecting everything to pass. Run `scripts/build-app.sh`, expecting it to exit 0 and print `~/Applications/LG Control.app`. Run `open ~/Applications/"LG Control.app"`, and check with `pgrep -x LGControl` that the process is running, then quit it (`pkill -x LGControl`).

- [ ] **Step 6: Manual check with Anh (the orchestrator runs this with Anh; subagents don't).** Each item passes or fails:
  - M1: The window opens and the sliders show the current values (brightness around 26, volume around 12).
  - M2: Dragging Brightness changes the LG smoothly, with no lag spiral, and it finishes on the final value.
  - M3: `PS5 (HDMI 2)` moves the window to the MacBook screen and the LG shows the PS5. `Mac (HDMI 1)` brings it back.
  - M4: The menu bar icon's input buttons do the same.
  - M5: With the LG cable unplugged (or the LG turned off), Retry shows `LG not connected` without freezing. Replugging and pressing Retry recovers.
  - M6: Details shows `LG ULTRAFINE`, `DEMO12345678`, `HDMI`, `3840 × 2160`.
  - M7: The `Launch at login` toggle shows up in System Settings › General › Login Items.
  - M9: While the LG shows the PS5, the main window (now on the MacBook screen) still shows the three input buttons, even if it says `LG not connected`.
  - M8: The USB-C button switches to Windows. If it doesn't, try `0x1B`, `0x10` or a value from `Inputs advertised by monitor` in Settings.

- [ ] **Step 7: Commit** with the message `feat: add LG Control SwiftUI app, menu bar and packaging`.

---

## Scope extension: Tasks 7–9 (replace MonitorControl and LG Screen Split)

These implement spec goals 6–8 (the section "Scope extension (2026-10-24)"). Each one builds on Task 6's `MonitorModel` and app. Extra global constraints:

- Accessibility permission comes from `AXIsProcessTrustedWithOptions`. When it's missing, Settings shows `Accessibility permission needed for keyboard keys and screen split` with an `Open System Settings` button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`). Features that need it stay off; nothing crashes.
- New UserDefaults keys: `keysEnabled` (Bool, default true), `syncEnabled` (Bool, default false), `syncOffset` (Int, default 0), `splitEnabled` (Bool, default true).
- New UI labels, exactly: `Control brightness and volume keys`, `Follow MacBook brightness`, `Offset`, `Screen split (drag a window onto the LG)`.

### Task 7: Stable signing, Accessibility, media keys and the on-screen indicator

**Files:**
- Create: `scripts/make-signing-cert.sh`, `Sources/LGKit/MediaKeys.swift`, `Sources/LGControl/MediaKeyTap.swift`, `Sources/LGControl/HUD.swift`, `Sources/LGControl/AudioOutput.swift`, `Sources/LGControl/Accessibility.swift`
- Modify: `scripts/build-app.sh`, `Sources/LGControl/MonitorModel.swift`, `Sources/LGControl/SettingsView.swift`, `README.md`
- Test: `Tests/LGKitTests/MediaKeysTests.swift`

**Interfaces:**
- Produces (in LGKit):
  - `public enum MediaKey: Equatable, Sendable { case brightnessUp, brightnessDown, volumeUp, volumeDown, mute }`
  - `public struct MediaKeyEvent: Equatable, Sendable { public let key: MediaKey; public let isDown: Bool; public let isRepeat: Bool; public init(key:isDown:isRepeat:); public static func decode(subtype: Int16, data1: Int) -> MediaKeyEvent?; public static func decode(keyCode: Int64, isDown: Bool, isRepeat: Bool) -> MediaKeyEvent? }`. The second decoder exists because Apple Silicon MacBook keyboards send the brightness keys as plain keyDown/keyUp events, not NX_SYSDEFINED.
  - `public enum KeyRoute: Equatable, Sendable { case lg, passThrough }`
  - `public enum KeyRouter { public static func route(_ key: MediaKey, pointerOnLG: Bool, lgIsSoundOutput: Bool, lgConnected: Bool) -> KeyRoute }`
  - `public enum Stepper { public static func step(current: UInt16, maximum: UInt16, up: Bool, fine: Bool) -> UInt16 }`
- Consumes: `MonitorModel` (Task 6). `MonitorModel` gains `func handleMediaKey(_ event: MediaKeyEvent, fine: Bool)`, which routes through the same `LatestValueWriter`s as the sliders.

- [ ] **Step 0: Spike the real key path (listen-only, read-only).** Build a throwaway `lgctl keylog` subcommand, or a scratch binary that isn't committed. It installs a **listen-only** `CGEvent.tapCreate` for systemDefined, keyDown and keyUp, and prints the type, keycode, subtype and data1. The controller asks Anh to press brightness down/up, mute, volume down/up and one letter key, and the log is recorded in the report. If the real codes differ from the 144/145 and NX 0/1/7 expectations, report NEEDS_CONTEXT with the log before going on. The tap needs Accessibility (or Input Monitoring) for the terminal running it; if it's denied, report NEEDS_CONTEXT.

- [ ] **Step 1: Write the failing tests**:

```swift
// NX_SYSDEFINED media keys: subtype 8; keyCode = (data1 & 0xFFFF0000) >> 16; state = (data1 & 0xFF00) >> 8 (0x0A down, 0x0B up); repeat = data1 & 0x1
func data1(_ code: Int, down: Bool, rep: Bool = false) -> Int { (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (rep ? 1 : 0) }

@Test func decodesMediaKeys() {
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(2, down: true)) == MediaKeyEvent(key: .brightnessUp, isDown: true, isRepeat: false))
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(3, down: false))?.key == .brightnessDown)
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(0, down: true, rep: true)) == MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: true))
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(1, down: true))?.key == .volumeDown)
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(7, down: true))?.key == .mute)
}
@Test func decodesBrightnessKeyCodes() {
    // Apple Silicon built-in keyboards: keyDown/keyUp with keycode 144 = brightness up, 145 = brightness down
    #expect(MediaKeyEvent.decode(keyCode: 144, isDown: true, isRepeat: false) == MediaKeyEvent(key: .brightnessUp, isDown: true, isRepeat: false))
    #expect(MediaKeyEvent.decode(keyCode: 145, isDown: false, isRepeat: false)?.key == .brightnessDown)
    #expect(MediaKeyEvent.decode(keyCode: 0, isDown: true, isRepeat: false) == nil)     // the "a" key: not ours
    #expect(MediaKeyEvent.decode(keyCode: 122, isDown: true, isRepeat: false) == nil)   // F1 in F-key mode: not ours
}
@Test func ignoresOtherSystemEvents() {
    #expect(MediaKeyEvent.decode(subtype: 7, data1: data1(2, down: true)) == nil)   // not a media-key subtype
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(16, down: true)) == nil)  // play/pause: not ours
}
@Test func routesKeysByPointerAndSoundOutput() {
    #expect(KeyRouter.route(.brightnessUp, pointerOnLG: true, lgIsSoundOutput: false, lgConnected: true) == .lg)
    #expect(KeyRouter.route(.brightnessUp, pointerOnLG: false, lgIsSoundOutput: true, lgConnected: true) == .passThrough)
    #expect(KeyRouter.route(.volumeUp, pointerOnLG: false, lgIsSoundOutput: true, lgConnected: true) == .lg)
    #expect(KeyRouter.route(.mute, pointerOnLG: true, lgIsSoundOutput: false, lgConnected: true) == .passThrough)
    #expect(KeyRouter.route(.brightnessUp, pointerOnLG: true, lgIsSoundOutput: true, lgConnected: false) == .passThrough)
}
@Test func stepsLikeMacOS() {
    #expect(Stepper.step(current: 26, maximum: 100, up: true, fine: false) == 31)    // 16 steps of 6.25: next boundary 31.25 → 31
    #expect(Stepper.step(current: 25, maximum: 100, up: true, fine: false) == 31)
    #expect(Stepper.step(current: 26, maximum: 100, up: false, fine: false) == 25)
    #expect(Stepper.step(current: 98, maximum: 100, up: true, fine: false) == 100)
    #expect(Stepper.step(current: 0, maximum: 100, up: false, fine: false) == 0)
    #expect(Stepper.step(current: 26, maximum: 100, up: true, fine: true) == 27)     // 64 steps: 1.5625 → next multiple
    #expect(Stepper.step(current: 0, maximum: 0, up: true, fine: false) == 0)       // unknown max: no-op
    #expect(Stepper.step(current: 31, maximum: 100, up: true, fine: false) == 38)   // must not stick on a rounded boundary
    #expect(Stepper.step(current: 38, maximum: 100, up: false, fine: false) == 31)
    var v: UInt16 = 0; for _ in 0..<16 { v = Stepper.step(current: v, maximum: 100, up: true, fine: false) }
    #expect(v == 100)                                                                // 16 presses go from 0 to 100
}
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh`. Expected: compile errors.

- [ ] **Step 3: Implement the LGKit pieces.**
  - `decode` accepts only subtype 8 and key codes 0, 1, 2, 3 and 7. Anything else returns `nil`.
  - `KeyRouter`: when `!lgConnected`, everything passes through. Brightness keys follow `pointerOnLG`; volume and mute keys follow `lgIsSoundOutput`.
  - `Stepper` works with step boundaries `b(k) = round(k × maximum / n)` for k = 0…n (n = 16, or 64 when `fine`).
    - Up: return the smallest `b(k)` strictly greater than `current`, or `maximum` if there is none.
    - Down: return the largest `b(k)` strictly less than `current`, or 0 if there is none.
    - `maximum == 0` returns `current`.
    - A rounded-boundary formula like `floor(current/unit)+1` gets stuck: it maps 31 back to 31. Don't use it.

- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh`.

- [ ] **Step 5: Implement the app pieces.**
  - `MediaKeyTap`:
    - Create a session-level `CGEvent.tapCreate` for `NSEvent.EventType.systemDefined` (raw event type 14) at `.headInsertEventTap`. Decode the event with `NSEvent(cgEvent:)` (`subtype.rawValue`, `data1`).
    - For `.lg` routes, consume key-down and repeat events by returning `nil`, and call `MonitorModel.handleMediaKey` on the main actor. Consume the matching key-up as well. Everything else is passed back unchanged.
    - "Fine" is when `event.modifierFlags` contains both `.option` and `.shift`.
    - The tap is re-enabled on `tapDisabledByTimeout` and `tapDisabledByUserInput`.
    - It only starts when Accessibility is trusted and `keysEnabled` is on. Toggling either one starts or stops it.
  - `pointerOnLG` is true when `NSEvent.mouseLocation` lies in the frame of the non-built-in `NSScreen`.
  - `AudioOutput.lgIsSoundOutput()`: the CoreAudio default output device (`kAudioHardwarePropertyDefaultOutputDevice`) has a `kAudioObjectPropertyName` equal to the LG's EDID name (`LG ULTRAFINE`), or a name containing `LG`. On this machine it's `LG ULTRAFINE`.
  - `HUD`:
    - One borderless, non-activating `NSPanel` at `.statusBar` level that ignores mouse events and is centred on the LG about 140 pt above its bottom edge.
    - Its content is SwiftUI on an `NSVisualEffectView` (`.hudWindow` material), 200 × 200 pt, corner radius 18: an SF Symbol (`sun.max.fill`, `speaker.wave.2.fill` or `speaker.slash.fill`) above a 16-segment bar.
    - It shows for 1.5 s after the last update, then fades out over 0.2 s.
    - Mute toggles 0x8D (1 ↔ 2). Volume keys while muted unmute first.
  - `Accessibility`: `isTrusted()` uses `AXIsProcessTrusted()`, and `prompt()` uses `AXIsProcessTrustedWithOptions` with the prompt option. Settings shows the permission row from the extra global constraints, plus the `Control brightness and volume keys` toggle.
  - `make-signing-cert.sh`:
    - Generate a self-signed certificate named `LG Control Local Signing` with OpenSSL: RSA 2048, 10 years, `extendedKeyUsage=codeSigning`, `keyUsage=digitalSignature`, `basicConstraints=CA:false`.
    - Import it into the login keychain as a `.p12` with `security import … -T /usr/bin/codesign`, then run `security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db`. This step prompts Anh for a password once.
    - If the identity already exists (`security find-identity -v -p codesigning | grep "LG Control Local Signing"`), exit 0 with a message.
  - `build-app.sh`: sign with `LG Control Local Signing` when `security find-identity -p codesigning` lists it; otherwise sign ad hoc and print `warning: ad-hoc signed; Accessibility permission will reset on every build — run scripts/make-signing-cert.sh once`.
  - README: add the one-time certificate step, how to grant Accessibility, and how the keys behave.

- [ ] **Step 6: Verify.**
  - Run `scripts/test.sh` (expect it to pass) and `scripts/build-app.sh` (expect exit 0).
  - The controller then runs the manual checks with Anh:
    - K1: With the pointer on the LG, brightness keys change the LG and show the HUD on the LG.
    - K2: With the pointer on the MacBook, brightness keys change the MacBook as normal.
    - K3: Volume keys change the LG, and mute works.
    - K4: After a rebuild, Accessibility is still granted (with the certificate installed).

- [ ] **Review amendments (binding; they override conflicting text above):**
  - **Tap:** `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest:` a mask of systemDefined (14), keyDown and keyUp`)`.
    - Pass `self` through `userInfo` with `Unmanaged`, and add `CFMachPortCreateRunLoopSource` to the main run loop.
    - In the callback, handle `.tapDisabledByTimeout` and `.tapDisabledByUserInput` FIRST by re-enabling the tap and returning the event.
    - For keyDown and keyUp, read `.keyboardEventKeycode` and `.keyboardEventAutorepeat` and use the keycode decoder.
    - For systemDefined only, build `NSEvent(cgEvent:)` and read `subtype` and `data1`. Never read `subtype` for any other type: NSEvent raises an exception.
    - "Fine" comes from `event.flags` containing `.maskAlternate` and `.maskShift`.
  - Remember which key-downs were consumed (by key), and consume the matching key-up even if the pointer has moved since.
  - When the reading's maximum is 0 (unknown), pass the key through.
  - **Same shortcuts as a normal Mac (Anh, 2026-10-24):** the keys are the standard brightness keys (F1/F2) and volume/mute keys (F10–F12), with ⌥⇧ for quarter-steps. With ⌥ alone, or any modifier set other than none or exactly ⌥⇧, always pass through, so macOS's own shortcuts (⌥ plus a key opens Displays or Sound settings) keep working. No custom hotkeys.
  - `handleMediaKey` updates the published `brightness`/`volume` straight away (converting `Double` ⇄ `UInt16` by rounding), so repeated presses build on each other. Then it writes through the slider's `LatestValueWriter`.
  - Accessibility: while it isn't trusted, poll `AXIsProcessTrusted()` every 1 s and start the tap once it is.
  - `pointerOnLG` uses `NSMouseInRect(NSEvent.mouseLocation, lgScreen.frame, false)`.
  - `AudioOutput` matches the device name exactly against the LG's EDID name (`DisplayDetails.edid?.name`, falling back to `LG ULTRAFINE`). There is no loose "contains LG" match.
  - HUD panel:
    - style mask `[.borderless, .nonactivatingPanel]`
    - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
    - `hidesOnDeactivate = false` and `ignoresMouseEvents = true`
    - shown with `orderFrontRegardless()`, never `makeKeyAndOrderFront`
  - `make-signing-cert.sh`:
    - Use `/usr/bin/openssl` (LibreSSL), with `-addext` for the three extensions. Homebrew OpenSSL 3 builds `.p12` files that `security import` rejects.
    - Use a random non-empty temporary password for `-passout`, and pass the same value to `security import -P`.
    - Then run `security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db`, which prompts once, so codesign doesn't prompt on every build.
    - Delete the temporary key, certificate and `.p12` with a `trap`.
    - Check whether it already exists with `security find-certificate -c "LG Control Local Signing"`, not `find-identity -v`.
  - `build-app.sh` signs by the identity's SHA-1 hash, taken from the first `security find-identity -p codesigning | grep "LG Control Local Signing"` line, so a duplicate name isn't ambiguous. It signs the whole `.app`.
  - README: run `scripts/make-signing-cert.sh` once; quit MonitorControl, because two key taps fight; and the "toggle Launch at login after reinstall" note only applies to ad-hoc builds.

- [ ] **Step 7: Commit** with the message `feat: control the LG with the brightness and volume keys`.

### Task 8: Follow MacBook brightness

**Files:**
- Create: `Sources/LGKit/BrightnessSync.swift`, `Sources/LGControl/BuiltInBrightness.swift`
- Modify: `Sources/LGControl/MonitorModel.swift`, `Sources/LGControl/SettingsView.swift`, `Sources/LGControl/ContentView.swift`
- Test: `Tests/LGKitTests/BrightnessSyncTests.swift`

**Interfaces:**
- Produces: `public enum BrightnessSync { public static func target(builtIn: Double, offset: Int, maximum: UInt16) -> UInt16; public static func offset(lg: UInt16, builtIn: Double, maximum: UInt16) -> Int; public static func isMeaningfulChange(from old: Double, to new: Double) -> Bool }`. `builtIn` is 0…1. `target` = clamp(round(builtIn × maximum) + offset, 0, maximum), with `offset` in the same units as `maximum`. `isMeaningfulChange` is `abs(new - old) >= 0.01`.
- Consumes: `MonitorModel.setBrightness` (Task 6) and `Stepper` (Task 7). `MonitorModel` gains `syncEnabled: Bool` and `syncOffset: Int`, both published and persisted.

- [ ] **Step 1: Write the failing tests**:

```swift
@Test func targetFollowsBuiltInWithOffset() {
    #expect(BrightnessSync.target(builtIn: 0.5, offset: 0, maximum: 100) == 50)
    #expect(BrightnessSync.target(builtIn: 0.5, offset: -24, maximum: 100) == 26)
    #expect(BrightnessSync.target(builtIn: 0.95, offset: 20, maximum: 100) == 100)   // clamped
    #expect(BrightnessSync.target(builtIn: 0.05, offset: -20, maximum: 100) == 0)    // clamped
}
@Test func offsetFromManualChange() {
    #expect(BrightnessSync.offset(lg: 26, builtIn: 0.5, maximum: 100) == -24)
    #expect(BrightnessSync.offset(lg: 50, builtIn: 0.5, maximum: 100) == 0)
}
@Test func ignoresTinyChanges() {
    #expect(!BrightnessSync.isMeaningfulChange(from: 0.465, to: 0.47))
    #expect(BrightnessSync.isMeaningfulChange(from: 0.465, to: 0.48))
}
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh`. Expected: compile errors.

- [ ] **Step 3: Implement `BrightnessSync`, then run the tests to verify they pass.**

- [ ] **Step 4: Implement the app pieces.**
  - `BuiltInBrightness.read() -> Double?` uses `DisplayServicesGetBrightness`, loaded with `dlopen` and `dlsym` from `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices` (verified on this Mac), for the display where `CGDisplayIsBuiltin != 0`. It returns `nil` when there's no built-in display or the call fails.
  - `MonitorModel`:
    - While `syncEnabled` is on, a 0.5 s `Timer` reads the built-in brightness. A meaningful change sets the LG to `target(...)` through the brightness writer.
    - A manual LG brightness change (slider, menu bar or keys) while sync is on sets `syncOffset = offset(...)` and persists it.
    - Turning sync on applies the target straight away.
  - Settings gets a `Follow MacBook brightness` toggle and a read-only `Offset` value with a `Reset` button that sets 0. The main window shows a small `Following MacBook` caption under Brightness while sync is on.

- [ ] **Step 5: Verify.**
  - Run `scripts/test.sh` and `scripts/build-app.sh`.
  - Manual check S1 with Anh: with sync on, changing the MacBook brightness moves the LG within about 1 s.
  - Manual check S2: dragging the LG slider and then changing the MacBook brightness keeps the new relative difference.

- [ ] **Review amendments (binding; they override conflicting text above):**
  - **Sync writes:** they go through a private `applySync(target:)` that writes through the brightness writer and updates the published `brightness`, and **never recomputes `syncOffset`**. Only the slider, the menu bar and the keys (the manual paths) recompute the offset. Otherwise, clamping wears the offset away (built-in 0.95 with offset +20 would become 5).
  - **Change detection:** compare each poll with the built-in value that was last *applied*, not with the previous poll, so a slow auto-brightness ramp still arrives.
  - **The private call:**
    - Its signature is `@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32`, with 0 meaning success.
    - The value is a `Float`; convert it to `Double`.
    - The read is a cheap local call. It's exempt from the "no private API on the main thread" constraint, which is about DDC I/O. The DDC write still goes through the DDC queue.
  - **Turning sync on:** first set `syncOffset = offset(lg: current, builtIn: now)`, so the LG doesn't jump, then start polling.
  - **`Reset`:** sets the offset to 0 and immediately applies the target.
  - Add a test: `BrightnessSync.target(builtIn: 0.95, offset: 20, maximum: 100) == 100`, and `offset` is unchanged by a sync write. That second part is a design rule; cover it in MonitorModel if it's practical, otherwise state it in the report.

- [ ] **Step 6: Commit** with the message `feat: let the LG follow the MacBook brightness`.

### Task 9: Screen split by dragging (halves)

**Files:**
- Create: `Sources/LGKit/SnapZones.swift`, `Sources/LGControl/WindowDragMonitor.swift`, `Sources/LGControl/SnapOverlay.swift`
- Modify: `Sources/LGControl/LGControlApp.swift`, `Sources/LGControl/SettingsView.swift`, `README.md`
- Test: `Tests/LGKitTests/SnapZonesTests.swift`

**Interfaces:**
- Produces: `public enum SnapZones { public static func halves(of visibleFrame: CGRect) -> [CGRect]; public static func zoneIndex(at point: CGPoint, in zones: [CGRect]) -> Int?; public static func axRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect }`
  - `halves` returns [left, right], using Cocoa coordinates (bottom-left origin). The left half's width is `floor(w/2)`, and the right half takes the rest.
  - `axRect` flips to the top-left origin that the Accessibility API uses: `y' = primaryScreenHeight - rect.maxY`. Also add `public static func axPoint(fromCocoa p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint`, which returns `(p.x, primaryScreenHeight - p.y)`. `primaryScreenHeight` is always `NSScreen.screens[0].frame.height` (the screen at origin 0,0), never `NSScreen.main`.

- [ ] **Step 1: Write the failing tests**:

```swift
@Test func halvesSplitVisibleFrame() {
    let f = CGRect(x: 1512, y: 0, width: 1921, height: 1055)
    #expect(SnapZones.halves(of: f) == [CGRect(x: 1512, y: 0, width: 960, height: 1055), CGRect(x: 2472, y: 0, width: 961, height: 1055)])
}
@Test func findsZoneUnderPointer() {
    let zones = SnapZones.halves(of: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    #expect(SnapZones.zoneIndex(at: CGPoint(x: 10, y: 500), in: zones) == 0)
    #expect(SnapZones.zoneIndex(at: CGPoint(x: 1900, y: 500), in: zones) == 1)
    #expect(SnapZones.zoneIndex(at: CGPoint(x: 3000, y: 500), in: zones) == nil)
}
@Test func convertsToAccessibilityCoordinates() {
    #expect(SnapZones.axRect(fromCocoa: CGRect(x: 0, y: 0, width: 960, height: 1055), primaryScreenHeight: 1080) == CGRect(x: 0, y: 25, width: 960, height: 1055))
    #expect(SnapZones.axPoint(fromCocoa: CGPoint(x: 100, y: 1000), primaryScreenHeight: 1080) == CGPoint(x: 100, y: 80))
}
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh`. Expected: compile errors.

- [ ] **Step 3: Implement `SnapZones`, then run the tests to verify they pass.**

- [ ] **Step 4: Implement the app pieces.**
  - `WindowDragMonitor` (runs only when Accessibility is trusted and `splitEnabled` is on):
    - It uses `NSEvent.addGlobalMonitorForEvents` for `.leftMouseDown`, `.leftMouseDragged` and `.leftMouseUp`.
    - **Mouse down:** use `AXUIElementCopyElementAtPosition` on the system-wide element, with the pointer converted to Accessibility coordinates, to find the element under the pointer. Walk `kAXParentAttribute` up to the element whose role is `kAXWindowRole`. Record its `kAXPositionAttribute`. Ignore this app's own windows (compare the pid).
    - **Drag:** once the window's position has moved more than 4 pt from the recorded one (it's really being dragged, not resized) and the pointer is on the LG, show the overlay and highlight `zoneIndex`.
    - **Mouse up:** if there's a highlighted zone, set `kAXPositionAttribute` and then `kAXSizeAttribute` to the zone's `axRect`, then hide the overlay. A failed Accessibility call is logged and ignored.
  - `SnapOverlay`: one borderless, click-through `NSPanel` covering the LG's `visibleFrame` at `.floating` level. It draws two rounded zones with an 8 pt inset, a translucent `controlAccentColor` fill at 0.15, and the highlighted zone at 0.35 with a 2 pt border.
  - Settings gets the `Screen split (drag a window onto the LG)` toggle, and the README gets the macOS tiling note.

- [ ] **Step 5: Verify.**
  - Run `scripts/test.sh` and `scripts/build-app.sh`.
  - Manual check P1 with Anh: dragging a Finder or Safari window on the LG shows two zones, and dropping it on the right snaps it to the right half.
  - Manual check P2: dragging on the MacBook screen shows nothing.
  - Manual check P3: this app's own window doesn't trigger the zones.

- [ ] **Review amendments (binding; they override conflicting text above):**
  - Call `AXUIElementSetMessagingTimeout(systemWide, 0.1)`, and use the same 0.1 s timeout on each window element. A hung app must never freeze LG Control.
  - On mouse down, try `kAXWindowAttribute` on the hit element first, then walk the parents.
  - Record both `kAXPositionAttribute` and `kAXSizeAttribute`. It counts as a drag only when the position has moved more than 4 pt **and** the size is unchanged; resizing from the left or top edge moves the position too.
  - During a drag, read the window position at most every 50 ms.
  - On drop, set the size, then the position, then the size again, so a window coming from a smaller screen isn't clamped.
  - `SnapOverlay` uses the same panel settings as Task 7's HUD (non-activating, all Spaces, `orderFrontRegardless`, ignores mouse events).

- [ ] **Step 6: Commit** with the message `feat: snap windows to LG halves by dragging`.

---

### Task 10: Switch inputs with LG's own command (bug fix)

Requirements and tests: see the brief `.superpowers/sdd/2026-10-24-lg-control/task-10-brief.md` (copied here in substance): `DDCPacket.setRequest(_:value:dataAddress:)` with seed `0x6E ^ dataAddress` (`setRequest(0xF4, value: 0x91, dataAddress: 0x50) == [0x84, 0x03, 0xF4, 0x00, 0x91, 0xDC]`); `DDCController.write(_:value:dataAddress:)`; `InputCommand { lg (0xF4 @ 0x50), standard (0x60 @ 0x51) }`; `InputConfig.command` default `.lg` with 0x90 / 0x91 / 0xD1, `defaults(for:)`, `setCommand(_:)`, lenient legacy decoding as `.standard`; `MonitorModel.switchTo` uses the command; Settings picker + footer; `lgctl set … --addr <hex>`; README. Manual check with Anh: PS5 sticks, Mac returns, USB-C (0xD1) if the Windows machine is on.

---

## Keep Awake: Tasks 12–13

Spec: the "Keep Awake (2026-10-24 evening)" section of the spec. Design: the Claude Design artboard "Keep Awake: menu bar panel and Settings" (`KeepAwake.dc.html` on the canvas). Extra global constraints:
- UserDefaults keys: `keepAwakePS5` (Bool, default true) and `keepAwakeBatteryThreshold` (Int, default 20, clamped to 5…50).
- UI copy, exactly: `Keep Awake`, the preset labels `15 min`, `30 min`, `1 h`, `2 h`, `5 h`, `10 h`, `Stop`, `Until <time>` (second line of the countdown card), `Keep awake while the LG shows the PS5`, `Stop when battery is below`, `Stopped: battery below <N>%`, and the badge `PS5`.
- Never hold a power assertion without a matching release path. The app's `applicationWillTerminate` releases it too.

### Task 12: Keep Awake policy (LGKit, pure)

**Files:** Create `Sources/LGKit/KeepAwake.swift`, `Tests/LGKitTests/KeepAwakeTests.swift`.

**Interfaces (Produces):**
- `public enum KeepAwakePreset: Int, CaseIterable, Sendable` with minutes 15, 30, 60, 120, 300, 600. It has `public var label: String` ("15 min", "30 min", "1 h", "2 h", "5 h", "10 h") and `public var duration: TimeInterval`.
- `public struct KeepAwakeInputs: Equatable, Sendable { public var timerEnd: Date?; public var now: Date; public var ps5Showing: Bool; public var ps5RuleOn: Bool; public var onBattery: Bool; public var batteryPercent: Int?; public var batteryThreshold: Int; public var ps5Since: Date? }` with a public memberwise init (ps5Since: see the amendments).
- `public enum KeepAwakeReason: Equatable, Sendable { case timer(remaining: TimeInterval), ps5 }`
- `public enum KeepAwakeStop: Equatable, Sendable { case timerFinished, lowBattery(threshold: Int) }`
- `public struct KeepAwakeDecision: Equatable, Sendable { public let hold: Bool; public let reason: KeepAwakeReason?; public let clearTimer: Bool; public let stopped: KeepAwakeStop? }`
- `public enum KeepAwakePolicy`:
  - `static func evaluate(_ i: KeepAwakeInputs) -> KeepAwakeDecision`. The rules, in order:
    1. **Low battery:** `onBattery && batteryPercent != nil && batteryPercent! < batteryThreshold` gives hold=false and reason=nil. clearTimer = (timerEnd != nil), and stopped = .lowBattery(threshold) if a timer was running or the PS5 rule would have held, otherwise nil.
    2. **Timer running:** `timerEnd > now` gives hold=true, reason=.timer(remaining: timerEnd − now), clearTimer=false, stopped=nil.
    3. **Timer expired:** `timerEnd <= now` sets clearTimer=true and stopped=.timerFinished, then falls through to rule 4.
    4. **PS5:** `ps5RuleOn && ps5Showing` gives hold=true and reason=.ps5. When it holds after an expired timer, stopped is nil.
    5. **Otherwise:** hold=false, reason=nil.
  - `static func shortText(_ remaining: TimeInterval) -> String`: `≥ 1 h` gives "1h 5m" (or "2h" when the minutes are 0); `≥ 60 s` gives "45m"; otherwise "<1m". Minutes round UP, so 59 m 30 s shows "1h" and 30 s shows "<1m".
  - `static func longText(_ remaining: TimeInterval) -> String`: "1 h 5 min left", "2 h left", "45 min left", "Less than a minute left". It uses the same rounding up.
  - `static func clampThreshold(_ v: Int) -> Int` snaps to the nearest multiple of 5 within 5…50.

- [ ] Step 1: Write the failing tests:
  - every rule branch, including the battery rule beating the PS5 rule and the timer, an expired timer falling through to the PS5 rule, `batteryPercent == nil` on battery never stopping, plugged in at 3% never stopping, and the threshold being strict (20% with threshold 20 doesn't stop; 19% does);
  - the preset minutes and labels;
  - shortText/longText for 3900 s → "1h 5m" / "1 h 5 min left", 7200 → "2h" / "2 h left", 2700 → "45m" / "45 min left", 3570 → "1h" / "1 h left", 30 → "<1m" / "Less than a minute left";
  - clampThreshold: 3 → 5, 22 → 20, 23 → 25, 99 → 50.
- [ ] Step 2: Run `scripts/test.sh` and confirm it fails to compile (RED).
- [ ] Step 3: Implement.
- [ ] Step 4: Run the tests and confirm they pass (GREEN), then the full suite once.
- [ ] **Review amendments (binding; they override conflicting text above):**
  - Text rounding, exactly: if `remaining < 60`, give "<1m" / "Less than a minute left". Otherwise `m = Int(ceil(remaining / 60))`; when `m >= 60`, h = m / 60 and rest = m % 60. Extra tests: 3599 → "1h", 3601 → "1h 1m", 60 → "1m", 61 → "2m", 59 → "<1m", 899.99 → "15m", 36000 → "10h" (and the matching longText). Rounding up means "1m" shows only at exactly 60 s; that's accepted.
  - Rule 1's "a timer was running" means `timerEnd != nil`, including an expired one. Pin it with a test.
  - `KeepAwakeDecision` gets a public memberwise init and `public static let idle` (hold false, reason nil, clearTimer false, stopped nil), because the app target can't use `@testable`.
  - **PS5 safety cap (Claude's call):** if Anh switches the LG back with its own buttons, the app can't tell, because the LG answers DDC on every input. So the PS5 rule holds for at most 8 hours. Add `ps5Since: Date?` to `KeepAwakeInputs`; the PS5 rule holds only while `now - ps5Since < 8 h`. Test: just under 8 h holds; 8 h or more doesn't. The README documents this limit.
  - clampThreshold tests also cover 7 → 5 and 8 → 10.

- [ ] Step 5: Commit with the message `feat: add the Keep Awake policy`.

### Task 13: Keep Awake in the app

**Files:** Create `Sources/LGControl/PowerAssertion.swift`, `Sources/LGControl/PowerSource.swift`, `Sources/LGControl/KeepAwakeModel.swift`. Modify `LGControlApp.swift` (the MenuBarExtra label badge, the environment object, and the release on terminate), `MenuBarContent.swift` (the Keep Awake section), `SettingsView.swift` (a `KeepAwakeSection` before General), and `README.md`.

**Interfaces (Consumes):** Task 12's `KeepAwakePolicy`, `KeepAwakePreset`, `KeepAwakeInputs`, `KeepAwakeReason` and `KeepAwakeStop`, plus `MonitorModel.lastInput` (published).

- `final class PowerAssertion`: `func hold(reason: String)` creates two assertions with `IOPMAssertionCreateWithName`, `kIOPMAssertionTypePreventUserIdleDisplaySleep` and `kIOPMAssertionTypePreventUserIdleSystemSleep`, both with level `kIOPMAssertionLevelOn` and name "Screen Monitor: Keep Awake". It is idempotent, so a second hold doesn't create more assertions. `func release()` releases both (`IOPMAssertionRelease`) and is also idempotent. `deinit` calls release. `var isHeld: Bool`.
- `enum PowerSource { static func read() -> (onBattery: Bool, percent: Int?) }` uses `IOPSCopyPowerSourcesInfo`, `IOPSGetProvidingPowerSourceType` (on battery when it is `kIOPSBatteryPowerValue`) and `IOPSCopyPowerSourcesList` / `IOPSGetPowerSourceDescription`, with percent = current/max capacity × 100. On any failure it returns (false, nil), so a desktop counts as plugged in.
- `@MainActor final class KeepAwakeModel: ObservableObject` publishes `timerEnd: Date?`, `decision: KeepAwakeDecision`, `lastStop: KeepAwakeStop?`, `ps5RuleOn` (persisted) and `batteryThreshold` (persisted, clamped). It provides `start(_ preset: KeepAwakePreset)`, which sets timerEnd = now + duration, clears lastStop and evaluates; `stop()`, which clears timerEnd and lastStop, then evaluates; and `func evaluate()`, which builds the inputs from the clock, `PowerSource.read()`, `ps5Showing = monitor.lastInput == .ps5` and the settings, applies the decision (`hold` → `assertion.hold`, otherwise release; `clearTimer` → timerEnd = nil; `stopped` → lastStop, except that `.timerFinished` doesn't display anything), and publishes it. It ticks every 1 s while `timerEnd != nil || (ps5RuleOn && lastInput == .ps5)`, and is otherwise idle. It re-evaluates on `monitor.$lastInput` changes (Combine sink) and on settings changes. The timer callback hops with `[weak self]` and `MainActor.assumeIsolated`.
- Menu bar section (match the design): a `Keep Awake` header and, while holding, a reason label on the right ("Timer" / "PS5"). While a timer runs, a compact blue card shows the longText on line 1 (16 pt semibold, monospaced digits, never "0 min"), `Until h:mm a` on line 2 (11 pt secondary), and a `Stop` button on the right. No other sentence in the card (Anh: keep it short). While only the PS5 rule holds, the card reads "Keeping awake while the PS5 is on". Below it is a 3×2 grid of the preset buttons, with the running preset highlighted. If `lastStop` is `.lowBattery(n)`, a small orange line reads `Stopped: battery below n%`.
- MenuBarExtra label: while holding, `HStack(spacing: 3) { Image(systemName: "display"); Image(systemName: "clock.fill"); Text(shortText or "PS5").monospacedDigit() }`. Otherwise only the display icon, as today.
- Settings › Keep Awake: a Toggle `Keep awake while the LG shows the PS5` with the hint "Your Mac won’t sleep while you play; ends when you switch back.", and `Stop when battery is below` with a value label, a Slider over 5…50 step 5, and the footer "Only on battery power. Plugged in, Keep Awake runs until its timer ends."
- `applicationWillTerminate` calls `keepAwake.assertion.release()`.

- [ ] Step 1: Implement PowerAssertion, PowerSource and KeepAwakeModel. The decision logic stays in Task 12's tested policy; this task adds no new decision logic. If any appears, put it in LGKit with tests.
- [ ] Step 2: Wire up the menu bar section, the label badge and Settings to match the design.
- [ ] Step 3: Run `scripts/test.sh` (expect it to pass) and `swift build`. Don't run build-app.sh; the controller packages the app.
- [ ] Step 4: The controller verifies, read-only, after packaging: `pmset -g assertions | grep -i "Screen Monitor"` shows both assertions while a timer runs and none after Stop. Anh then checks the panel, the badge, the countdown and the PS5 rule.
- [ ] **Review amendments (binding; they override conflicting text above):**
  - **Combine timing:** `@Published` delivers in willSet, so `monitor.$lastInput.sink { [weak self] value in self?.evaluate(lastInput: value) }` must pass the NEW value in. `evaluate` takes an optional `lastInput` override and otherwise reads `monitor.lastInput`. Track `ps5Since`: set it when lastInput becomes `.ps5`, clear it on anything else.
  - **Wiring:** in `LGControlApp.init`, `let m = MonitorModel(); _model = StateObject(wrappedValue: m); _keepAwake = StateObject(wrappedValue: KeepAwakeModel(monitor: m))`. Inject `.environmentObject(keepAwake)` into EVERY scene that uses it: the MenuBarExtra content AND label, Settings, and the main window if it shows anything. `KeepAwakeModel` observes `NSApplication.willTerminateNotification` itself and releases. powerd also drops assertions when a process exits.
  - **lastStop:** only a non-nil `.lowBattery` sets it. `start()`, `stop()` and any decision with `hold == true` clear it. `.timerFinished` is never shown.
  - **activePreset:** publish `activePreset: KeepAwakePreset?`. `start` sets it, and it's cleared whenever `timerEnd` is cleared. The highlight uses it.
  - **Tick:** `Timer(timeInterval: 1, repeats: true)` added with `RunLoop.main.add(t, forMode: .common)`, `tolerance = 0.2`. It lives in the model, never in a view, and runs only while timerEnd != nil or the PS5 rule could hold. Also evaluate on `NSWorkspace.didWakeNotification`. Publish `badgeText: String?` separately, assigned only when the text changes, so the label doesn't redraw every second for nothing.
  - **PowerAssertion:** the constants are `String`s, so use `kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString` (the same for system sleep) and `IOPMAssertionLevel(kIOPMAssertionLevelOn)`. Store each `IOPMAssertionID` separately (0 = none) and zero it on release. A partial create failure retries on the next hold.
  - **PowerSource:**
    - Use `IOPSCopyPowerSourcesInfo()?.takeRetainedValue()` and `IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]`, but `IOPSGetProvidingPowerSourceType(blob).takeUnretainedValue()` and `IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue()` (Get rule).
    - Take the percent only from the source with `kIOPSTypeKey == kIOPSInternalBatteryType`.
    - On battery means the providing type is `kIOPSBatteryPowerValue`.
  - **MenuBarExtra label:** use `MenuBarExtra(content:label:)`. Try `HStack { Image("display"); Text(badge) }` first, with a single image plus text. Only if the controller's on-screen check shows it dropped is the fallback to render the label with `ImageRenderer` into a template `NSImage`. Keep monospaced digits where they render.
  - **Time format:** `Date.FormatStyle().hour().minute()`, which follows the system clock setting.
  - **README:** cover the presets, that both the screens and the Mac stay awake, the PS5 rule and its 8-hour cap, the battery rule, and the `pmset -g assertions` check.
  - **Manual check (controller):** from idle, switch to PS5, and `pmset -g assertions` must list both "Screen Monitor: Keep Awake" assertions. After switching to the Mac they must be gone.

- [ ] Step 5: Commit with the message `feat: keep the Mac and screens awake from the menu bar`.

**Review Focus:**
1. An assertion leaked after Stop, quitting, or a battery stop: every path must release.
2. A stale countdown, or the tick running forever while idle.
3. The battery rule firing while plugged in, or when the battery level is unknown.
4. The PS5 rule outliving a switch back to the Mac.
5. The badge text width causing the menu bar item to jitter (use monospaced digits).

### Task 14: Keep Awake design A and new presets

Anh picked card option A and new presets after Tasks 12 and 13 were planned. The spec section "Keep Awake design update" is binding. The Claude Design board "Keep Awake: menu bar panel and Settings" shows the final look.

**Files:** Modify `Sources/LGKit/KeepAwake.swift`, `Tests/LGKitTests/KeepAwake*Tests.swift`, `Sources/LGControl/MenuBarContent.swift` (the Keep Awake section) and README.md if it lists the presets.

- **Presets:** `KeepAwakePreset` becomes exactly 60, 120, 240, 360, 480 and 600 minutes, with the labels "1h", "2h", "4h", "6h", "8h" and "10h". Update its tests.
- **New pure function** `KeepAwakePolicy.clockText(_ remaining: TimeInterval) -> String`:
  - `s = Int(ceil(remaining))` (never negative), h = s / 3600, m = (s % 3600) / 60, sec = s % 60.
  - When h > 0: "h:mm:ss"; otherwise "m:ss".
  - Tests: 3582 → "59:42", 7182 → "1:59:42", 36000 → "10:00:00", 59.2 → "1:00", 0 → "0:00", −5 → "0:00", 600 → "10:00".
- **New pure function** `KeepAwakePolicy.ringProgress(remaining: TimeInterval, total: TimeInterval) -> Double`: remaining / total, clamped to 0…1, and 0 when total ≤ 0. Tests: (1800, 3600) → 0.5, (4000, 3600) → 1, (−1, 3600) → 0, (5, 0) → 0.
- **Card (menu bar):** while a timer runs, replace the current card with option A:
  - An HStack(spacing 12) holding:
    - a 44 × 44 ring: a background `Circle().stroke(lineWidth: 4)` in a light tint, plus `Circle().trim(from: 0, to: progress)` rotated −90°, stroked in the accent colour with a round line cap, and a small `clock` symbol in the centre;
    - a VStack(alignment: .leading, spacing: 1) with `Text(clockText)` at 22 pt semibold, `.monospacedDigit()`, `.lineLimit(1)`, and `Text("until " + time)` at 11 pt secondary, `.lineLimit(1)`;
    - a Spacer;
    - a 28 pt circular button with an `xmark` symbol (font size 10, bold), `.accessibilityLabel("Stop Keep Awake")`, calling `stop()`.
  - The total for the ring comes from `activePreset.duration`.
  - While only the PS5 rule holds, the same layout shows a full ring, "PS5" in place of the clock, and "while the PS5 is on" underneath. In that state the ✕ hides the reason until the next change (it can't stop the rule); or omit the ✕ if simpler, and say which you chose.
- **Presets row:** a single `HStack(spacing: 4)` of six equal-width buttons, 11 pt, with a filled accent background for `activePreset` and a quiet fill for the others. Drop the 3 × 2 grid.
- **Live countdown:** the clock text changes every second, so the 1 s tick must publish `decision` or the remaining time each tick. The `badgeText` optimisation stays only for the label.
- Use TDD for the two pure functions and the presets. Run scripts/test.sh once after the last edit, plus `swift build`. Commit with the message `feat: Keep Awake progress-ring card and new presets`.

### Task 15: Screen split snaps only at the screen edges

Anh's feedback: dropping a window in the middle of the LG must not snap it. Snap only when the pointer reaches the LG's left or right edge, within 6 pt, which is the Rectangle, Magnet and macOS behaviour. The full requirements and tests are in the brief `.superpowers/sdd/…/task-15-brief.md`:
- a pure function, `SnapZones.edgeZone(at:screenFrame:threshold:)`, with tests;
- WindowDragMonitor shows a single preview of the targeted half only while the pointer is at an edge, and snaps on drop only then;
- SnapOverlay shows one preview rect;
- the copy changes to "Drag a window to the left or right edge of the LG to snap it to that half."

**Task 15 status: dropped (Anh, 2026-10-24).** The screen split stays as is. Use macOS edge tiling if you need edge-only snapping.
