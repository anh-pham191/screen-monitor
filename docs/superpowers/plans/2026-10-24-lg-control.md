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
- Input values: Mac/HDMI 1 = `0x11`, PS5/HDMI 2 = `0x12` (both verified), Windows/USB-C = `0x1B` (default, not verified, and changeable in Settings).
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
  - `public struct InputConfig: Codable, Equatable, Sendable { public var mac: UInt16 = 0x11; public var ps5: UInt16 = 0x12; public var windows: UInt16 = 0x1B; public init() {}; public func value(for: Input) -> UInt16; public mutating func set(_ value: UInt16, for: Input); public static func parseHex(_ text: String) -> UInt16?; public static func formatHex(_ value: UInt16) -> String }`
  - `public final class LatestValueWriter<Value: Sendable>: @unchecked Sendable` with `public init(queue: DispatchQueue, interval: TimeInterval, write: @escaping (Value) -> Void)` and `public func submit(_ value: Value)`
  - `public enum WindowPlacement { public static func shouldMoveToBuiltIn(target: Input, windowOnExternal: Bool, builtInAvailable: Bool) -> Bool }`

- [ ] **Step 1: Write the failing tests**:

```swift
@Test func defaultInputValues() {
    let c = InputConfig()
    #expect([c.value(for: .mac), c.value(for: .ps5), c.value(for: .windows)] == [0x11, 0x12, 0x1B])
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
    var c = InputConfig(); c.set(0x0F, for: .windows)
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
  - M8: The USB-C button switches to Windows. If it doesn't, try `0x0F`, `0x10` or a value from `Inputs advertised by monitor` in Settings.

- [ ] **Step 7: Commit** with the message `feat: add LG Control SwiftUI app, menu bar and packaging`.
