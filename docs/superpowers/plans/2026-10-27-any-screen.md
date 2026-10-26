# Any Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ports instead of devices, no "LG" in anything a person sees, the hardware screen identified properly, and software brightness for every other external screen (DisplayLink).

**Architecture:** Pure logic (ports, migration, Keep Awake rename, screen identity/classification, dimming curve, key routing) lives in `LGKit` with Swift Testing tests. The app target (`LGControl`) wires it to AppKit: a screen catalog, overlay windows, the key tap, and SwiftUI.

**Tech Stack:** Swift 6.0 tools, language mode 5, macOS 14+, SwiftUI + AppKit, Swift Testing via `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-10-27-any-screen-design.md`

## Global Constraints

- `Package.swift` keeps `swiftLanguageModes: [.v5]` and `.macOS(.v14)`; no new dependencies.
- Tests: `scripts/test.sh` (wraps `swift test` with the Command Line Tools framework flags). Build: `swift build`.
- Never write to a monitor (no `lgctl set`, no running the app's switch). Reads are fine but not needed.
- Do not rename modules/targets/products (`LGKit`, `lgctl`, `LGControl`) or the bundle ID `com.anhpham.lgcontrol`. UserDefaults keys stay as they are unless a task says otherwise.
- User-visible copy: no "LG", "PS5", "Mac (…)", "Windows (…)" anywhere a person reads it, except the Settings command option "LG monitors (VCP 0xF4)" which names the monitor family whose command it is.
- Match surrounding code: comment density and tone, naming, `MainActor.assumeIsolated` patterns.
- Git: commit on branch `any-screen`; author email is already configured per repo — don't change it. Commit trailer: see A9.

## Review Focus

1. Two identical DisplayLink screens (same vendor/model) must keep separate brightness levels — identity includes serial, or position when the serial is 0. (Task 2 test `identicalScreensGetDistinctKeys`.)
2. A Philips screen must never be treated as the hardware screen just because it's the first external one, including when the LG is absent (lid open or closed). (Task 2 tests `classifier*`.)
3. Saved settings from the current release (`{"command":"lg","mac":144,"ps5":145,"windows":209}`) must keep their values under the new port names. (Task 1 test `legacyDeviceKeysMigrateToPorts`.)
4. Brightness keys over a software screen must work while the hardware screen is disconnected or absent. (Task 2 test `softwareRouteIgnoresHardwareConnection`.)
5. Level 0 must never make a screen fully black. (Task 2 test `dimmingNeverFullyBlack`.)


## Plan review rulings (binding; each task's implementer reads the ones tagged with its task)

- **A1 (Task 2) MediaKeyGate.** `KeyAction.handle(fine:)` becomes `.handle(route: KeyRoute, fine: Bool)`. The gate stores the owning route per key (`[MediaKey: KeyRoute]`), so repeats and the key-up follow the route chosen at the first key-down. New signature: `decide(_ event:, modifiers:, canHandle: (KeyRoute) -> Bool, route: () -> KeyRoute) -> KeyAction`. A fresh press: `let r = route()`; handle only if `modifiers.handle && r != .passThrough && canHandle(r)`. A repeat: use the stored route; `canHandle(stored)`; mute repeats still swallow. Port every `MediaKeyGateTests` case (`{ .lg }` → `{ .hardware }`, `canHandle: true` → `canHandle: { _ in true }`, `.handle(fine:)` → `.handle(route: .hardware, fine:)`). Add `softwarePressKeepsItsRouteForRepeatAndKeyUp` and `canHandleIsAskedForTheChosenRoute` tests. In `MediaKeyTap` (Task 2 call-site): `canHandle: { $0 == .software || model.canHandleMediaKey(key.key) }`; `.handle(.hardware, fine)` → `model.handleMediaKey`; `.handle(.software, _)` → pass through for now (Task 3 wires it).
- **A2 (Task 3) Hardware EDID is sticky.** `ScreenCatalog.hardwareEDID` is only ever set to a non-nil EDID and keeps the last one; DDC dropping (e.g. while on another input) must not reclassify the hardware screen as software. When the stored EDID changes, `MonitorModel` calls `softwareBrightness.rebuild()` so overlays and the menu list update after the first refresh.
- **A3 (Task 1) Call sites owned by Task 1:** `Tests/LGKitTests/MonitorReadoutTests.swift`, `RecoveryTests.swift`, `KeepAwakeTests.swift` (helper `inputs(ps5Showing:ps5Since:)`), `KeepAwakeStateTests.swift`, `AppLogicTests.swift`; app: `SettingsView.swift` (`ps5RuleOn` binding, input rows), `MenuBarContent.swift` (`case .ps5` → `.otherInput`), `ContentView.swift`, `KeepAwakeModel.swift`, all `.mac` uses in `MonitorModel.swift` including `AudioRestore` arguments (`leavingFromMac: lastInput == macPort`). `grep -rnE "\.ps5|\.mac\b|\.windows\b|ps5(Showing|RuleOn|Since|Cap)|shouldMoveToBuiltIn|nextPS5Since" Sources Tests` returns nothing afterwards (UserDefaults key string `keepAwakePS5` excepted).
- **A4 (Task 1/3) Window destination.** Task 1 passes `WindowMover.builtInAvailable()` as `destinationAvailable`; Task 3 replaces it with "a destination screen exists". Task 3 adds pure `WindowPlacement.destination(kinds: [ScreenKind]) -> Int?` over screens in `NSScreen.screens` order (index of the built-in, else first `.software`, else nil), and changes `WindowMover.moveAppWindowsToBuiltInScreen()` to `moveAppWindows(to: NSScreen)`; `WindowShuffler.moveWindowsOffHardwareScreen()` uses the same destination for its own and other apps' windows. `WindowShuffler.restoreWindows()` waits for `ScreenCatalog.hardwareScreen()` (both places that called `lgScreen()`).
- **A5 (Task 3) Ownership.** `LGControlApp` builds `SoftwareBrightness(defaults:hud:)` first, then `MonitorModel(defaults:softwareBrightness:)`. `MonitorModel` keeps owning the single `HUD` and the key tap; it passes its `hud` to `SoftwareBrightness` (one HUD instance) — so construct the HUD in `LGControlApp`, pass it to both, or let `MonitorModel` create `SoftwareBrightness`; pick one and keep a single `HUD`. `MonitorModel.init` sets `keyTap.softwareBrightness`. Both are environment objects for the views.
- **A6 (Task 4) Copy check.** Replace the plan's grep with `grep -rnE '"[^"]*(LG|PS5|Windows \(|Mac \()' Sources/LGControl Sources/lgctl`. Allowed hits only: the Settings option label "LG monitors (VCP 0xF4)" (in LGKit, so not listed), `defaultLGName = "LG ULTRAFINE"` (internal CoreAudio fallback), `NSLog` lines, UserDefaults keys, and the help text sentence naming LG's own command. Explicitly fix `MenuBarContent` and `ContentView` `?? "LG"` fallbacks.
- **A7 (Task 1) Auto command.** Apply only when nothing was ever saved, once per new EDID manufacturer seen: `let auto = InputConfig.defaults(for: .automatic(manufacturerID: m)); if auto != inputConfig { inputConfig = auto }` (didSet persists on any assignment, so guard first).
- **A8 (Task 2) Public API.** Everything in `Screens.swift` that the app uses is `public` (the app imports `LGKit` without `@testable`). `vendorNumber` is non-optional: returns 0 unless `manufacturerID` is exactly 3 letters A–Z; `ScreenClassifier` never matches when `vendorNumber == 0`.
- **A9 (all) Commit trailer:** end each commit message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01KPBU3oNp5fX8rNkcSGiquU`.
- Noted, accepted: with serial 0, two identical screens keyed by position can swap levels if macOS reorders them.

---

### Task 1: Ports, the Mac's port, and the Keep Awake rename (LGKit + compile fixes)

**Files:**
- Modify: `Sources/LGKit/InputConfig.swift`, `Sources/LGKit/WindowPlacement.swift`, `Sources/LGKit/KeepAwake.swift`, `Sources/LGKit/KeepAwakeState.swift`
- Modify (only enough to compile and keep today's behaviour with the new names): `Sources/LGControl/MonitorModel.swift`, `KeepAwakeModel.swift`, `MenuBarContent.swift`, `ContentView.swift`, `SettingsView.swift`
- Test: `Tests/LGKitTests/AppLogicTests.swift`, `KeepAwakeTests.swift`, `KeepAwakeStateTests.swift`

**Interfaces (produces):**
- `public enum Input: String, CaseIterable, Codable { case hdmi1, hdmi2, usbC }` with `label`: "HDMI 1", "HDMI 2", "USB-C".
- `InputConfig` stored properties `hdmi1`, `hdmi2`, `usbC` (same defaults as today's mac/ps5/windows: LG 0x90/0x91/0xD1, standard 0x11/0x12/0x0F); `value(for:)`, `set(_:for:)` unchanged in shape. Encodes with keys `command`, `hdmi1`, `hdmi2`, `usbC`. Decoding: new key wins; else legacy key (`mac`→hdmi1, `ps5`→hdmi2, `windows`→usbC); else the command's default. Missing `command` still means `.standard`.
- `InputCommand.label`: `.lg` → "LG monitors (VCP 0xF4)", `.standard` → "Standard (VCP 0x60)".
- `public static func InputCommand.automatic(manufacturerID: String?) -> InputCommand` — `"GSM"` → `.lg`, anything else or nil → `.standard`.
- `WindowPlacement.shouldMoveOff(target: Input, macPort: Input, destinationAvailable: Bool) -> Bool` = `target != macPort && destinationAvailable` (replaces both `shouldMoveToBuiltIn` overloads; update callers).
- Keep Awake rename: `KeepAwakeInputs.ps5Showing/ps5RuleOn/ps5Since` → `awayFromMac/awayRuleOn/awaySince`; `KeepAwakeReason.ps5` → `.otherInput`; `KeepAwakePolicy.ps5Cap` → `awayCap` (same 8 h); `KeepAwakeState.nextPS5Since` → `nextAwaySince`, `needsTick(... ps5RuleOn:ps5Showing:ps5Since:)` → `awayRuleOn:awayFromMac:awaySince:`. Behaviour unchanged.
- `KeepAwakeState.badgeText(for: KeepAwakeDecision, port: String?) -> String?` — `.otherInput` returns `port ?? "Input"`; `reasonLabel(.otherInput)` = "Other input".

App wiring in this task (no new UI yet):
- `MonitorModel`: `@Published var macPort: Input` persisted under UserDefaults key `"macPort"` (raw value; default `.hdmi1`). `lastInput` starts at `macPort`. Every `== .mac` / `!= .mac` becomes a comparison with `macPort`. When no `inputConfig` was ever saved (`defaults.data(forKey:) == nil`) and a refresh yields an EDID manufacturer, set `inputConfig = .defaults(for: .automatic(manufacturerID:))` once — but don't persist it unless it differs from the current value.
- `KeepAwakeModel`: `awayFromMac = input != nil && input != monitor.macPort`; badge passes `monitor.lastInput?.label`. Assertion reason for `.otherInput`: "The screen is showing another input". UserDefaults key stays `"keepAwakePS5"`.
- Existing views compile with the new names; label text fixes in views are Task 4.

- [ ] **Step 1: Update/write the failing tests**

```swift
@Test func portLabels() {
    #expect(Input.allCases == [.hdmi1, .hdmi2, .usbC])
    #expect(Input.allCases.map(\.label) == ["HDMI 1", "HDMI 2", "USB-C"])
}
@Test func legacyDeviceKeysMigrateToPorts() throws {
    let c = try JSONDecoder().decode(InputConfig.self,
        from: Data(#"{"command":"lg","mac":144,"ps5":145,"windows":209}"#.utf8))
    #expect(c.command == .lg && c.hdmi1 == 0x90 && c.hdmi2 == 0x91 && c.usbC == 0xD1)
}
@Test func newKeysWinOverLegacyKeys() throws {
    let c = try JSONDecoder().decode(InputConfig.self,
        from: Data(#"{"command":"standard","hdmi1":1,"mac":2}"#.utf8))
    #expect(c.hdmi1 == 1)
}
@Test func encodesPortKeys() throws {
    let json = String(decoding: try JSONEncoder().encode(InputConfig()), as: UTF8.self)
    #expect(json.contains("\"hdmi1\"") && !json.contains("\"mac\""))
}
@Test func automaticCommandByMaker() {
    #expect(InputCommand.automatic(manufacturerID: "GSM") == .lg)
    #expect(InputCommand.automatic(manufacturerID: "PHL") == .standard)
    #expect(InputCommand.automatic(manufacturerID: nil) == .standard)
    #expect(InputCommand.allCases.map(\.label) == ["LG monitors (VCP 0xF4)", "Standard (VCP 0x60)"])
}
@Test func moveOffOnlyWhenLeavingTheMacsPort() {
    #expect(WindowPlacement.shouldMoveOff(target: .hdmi2, macPort: .hdmi1, destinationAvailable: true))
    #expect(!WindowPlacement.shouldMoveOff(target: .hdmi1, macPort: .hdmi1, destinationAvailable: true))
    #expect(WindowPlacement.shouldMoveOff(target: .hdmi1, macPort: .usbC, destinationAvailable: true))
    #expect(!WindowPlacement.shouldMoveOff(target: .hdmi2, macPort: .hdmi1, destinationAvailable: false))
}
@Test func awayBadgeShowsThePort() {
    let d = KeepAwakeDecision(hold: true, reason: .otherInput, clearTimer: false, stopped: nil)
    #expect(KeepAwakeState.badgeText(for: d, port: "HDMI 2") == "HDMI 2")
    #expect(KeepAwakeState.badgeText(for: d, port: nil) == "Input")
    #expect(KeepAwakeState.reasonLabel(.otherInput) == "Other input")
}
```
Rename existing tests' uses of `.mac/.ps5/.windows`, `ps5*`, `.ps5` to the new names; update the old label assertions (`defaultInputValues`, `inputCommandWireValues`) to the new labels. Replace the existing `WindowPlacement` tests with `moveOffOnlyWhenLeavingTheMacsPort`.

- [ ] **Step 2: Run `scripts/test.sh` — expect compile failures/FAILs for the new names**
- [ ] **Step 3: Implement the LGKit changes, then the app compile fixes and wiring above**
- [ ] **Step 4: Run `scripts/test.sh` and `swift build` — expect all PASS and a clean build**
- [ ] **Step 5: Commit** `refactor: name inputs by port and add the Mac's port setting`

---

### Task 2: Screen identity, classification, dimming curve, key routing (LGKit)

**Files:**
- Create: `Sources/LGKit/Screens.swift`, `Tests/LGKitTests/ScreensTests.swift`
- Modify: `Sources/LGKit/EDID.swift` (add `vendorNumber`), `Sources/LGKit/MediaKeys.swift` (`KeyRoute`, `KeyRouter.route`), `Sources/LGControl/MediaKeyTap.swift` (call-site only, keep behaviour: pass `.hardware` when the pointer is on today's `lgScreen()`, else `nil`), `Tests/LGKitTests/MediaKeysTests.swift`

**Interfaces (produces):**
- `EDIDInfo.vendorNumber: UInt32` — the 3-letter manufacturer ID packed the way CoreGraphics reports it: `((c1-64)<<10) | ((c2-64)<<5) | (c3-64)`; nil-safe: returns 0 if `manufacturerID` isn't 3 letters A–Z.
- `public struct ScreenInfo: Equatable, Sendable { displayID: UInt32; isBuiltIn: Bool; vendor: UInt32; model: UInt32; serial: UInt32 }` (public memberwise init).
- `public enum ScreenKind: Equatable, Sendable { case builtIn, hardware, software }`
- `public enum ScreenClassifier { static func classify(_ screens: [ScreenInfo], hardwareEDID: EDIDInfo?) -> [UInt32: ScreenKind] }` — built-in → `.builtIn`; the FIRST non-built-in screen with `vendor == edid.vendorNumber && model == UInt32(edid.productCode)` → `.hardware`; every other non-built-in → `.software`. No EDID → no hardware screen.
- `public enum ScreenKey { static func key(for screen: ScreenInfo, among screens: [ScreenInfo]) -> String }` — lowercase hex `"\(vendor)-\(model)-\(serial)"` (vendor/model hex, serial decimal); when `serial == 0`, append `"#\(index)"` where index = position of this screen among the non-built-in screens in `screens` order.
- `public enum SoftwareDimming { static let maximumOpacity = 0.9; static func opacity(level: Int) -> Double; static func clamp(_ level: Int) -> Int }` — opacity = `0.9 * (1 - clamp(level)/100)`; clamp to 0...100.
- `public struct SoftwareLevels: Codable, Equatable, Sendable { public init(); func level(for key: String) -> Int /* default 100 */; mutating func set(_ level: Int, for key: String) /* clamped */ }`.
- `KeyRoute` becomes `{ case hardware, software, passThrough }`. `KeyRouter.route(_ key: MediaKey, pointerScreen: ScreenKind?, hardwareIsSoundOutput: Bool, hardwareConnected: Bool) -> KeyRoute`:
  - brightness: pointer `.software` → `.software` (whatever the hardware state); pointer `.hardware` and connected → `.hardware`; otherwise `.passThrough`.
  - volume/mute: `hardwareConnected && hardwareIsSoundOutput` → `.hardware`; else `.passThrough`.

- [ ] **Step 1: Write the failing tests** (`ScreensTests.swift`, plus updated `MediaKeysTests`). Test files share one module: if a top-level name below clashes with an existing one, rename it in the new file.

```swift
// `lgEDID` (hex string) and `bytes(_:)` already exist in EDIDTests.swift (same test module).
let lgInfo = EDIDInfo.parse(bytes(lgEDID))!
let macScreen = ScreenInfo(displayID: 1, isBuiltIn: true, vendor: 0x610, model: 0xa04f, serial: 0)
let lgScreen = ScreenInfo(displayID: 2, isBuiltIn: false, vendor: 0x1E6D, model: 0x5CBB, serial: 1)
let phl1 = ScreenInfo(displayID: 9, isBuiltIn: false, vendor: 0x410C, model: 0xC171, serial: 11)
let phl2 = ScreenInfo(displayID: 10, isBuiltIn: false, vendor: 0x410C, model: 0xC171, serial: 12)

@Test func vendorNumberPacksManufacturerID() {
    #expect(lgInfo.vendorNumber == 0x1E6D)   // "GSM"
}
@Test func classifierFindsHardwareByEDIDNotOrder() {
    let k = ScreenClassifier.classify([macScreen, phl1, lgScreen, phl2], hardwareEDID: lgInfo)
    #expect(k == [1: .builtIn, 9: .software, 2: .hardware, 10: .software])
}
@Test func classifierWithoutEDIDHasNoHardwareScreen() {
    let k = ScreenClassifier.classify([phl1, phl2], hardwareEDID: nil)
    #expect(k == [9: .software, 10: .software])
}
@Test func classifierWhenHardwareScreenAbsent() {
    #expect(ScreenClassifier.classify([phl1], hardwareEDID: lgInfo) == [9: .software])
}
@Test func identicalScreensGetDistinctKeys() {
    #expect(ScreenKey.key(for: phl1, among: [phl1, phl2]) == "410c-c171-11")
    let a = ScreenInfo(displayID: 9, isBuiltIn: false, vendor: 0x410C, model: 0xC171, serial: 0)
    let b = ScreenInfo(displayID: 10, isBuiltIn: false, vendor: 0x410C, model: 0xC171, serial: 0)
    #expect(ScreenKey.key(for: a, among: [macScreen, a, b]) == "410c-c171-0#0")
    #expect(ScreenKey.key(for: b, among: [macScreen, a, b]) == "410c-c171-0#1")
}
@Test func dimmingCurve() {
    #expect(SoftwareDimming.opacity(level: 100) == 0)
    #expect(abs(SoftwareDimming.opacity(level: 50) - 0.45) < 1e-9)
    #expect(SoftwareDimming.opacity(level: 150) == 0)
}
@Test func dimmingNeverFullyBlack() {
    #expect(abs(SoftwareDimming.opacity(level: 0) - 0.9) < 1e-9)
    #expect(SoftwareDimming.opacity(level: -20) < 1)
}
@Test func softwareLevelsDefaultAndClamp() throws {
    var s = SoftwareLevels()
    #expect(s.level(for: "x") == 100)
    s.set(-5, for: "x"); #expect(s.level(for: "x") == 0)
    s.set(40, for: "y")
    #expect(try JSONDecoder().decode(SoftwareLevels.self, from: JSONEncoder().encode(s)) == s)
}
@Test func softwareRouteIgnoresHardwareConnection() {
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: .software, hardwareIsSoundOutput: false, hardwareConnected: false) == .software)
    #expect(KeyRouter.route(.brightnessDown, pointerScreen: .hardware, hardwareIsSoundOutput: false, hardwareConnected: true) == .hardware)
    #expect(KeyRouter.route(.brightnessDown, pointerScreen: .hardware, hardwareIsSoundOutput: false, hardwareConnected: false) == .passThrough)
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: .builtIn, hardwareIsSoundOutput: true, hardwareConnected: true) == .passThrough)
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: nil, hardwareIsSoundOutput: true, hardwareConnected: true) == .passThrough)
    #expect(KeyRouter.route(.volumeUp, pointerScreen: .software, hardwareIsSoundOutput: true, hardwareConnected: true) == .hardware)
    #expect(KeyRouter.route(.mute, pointerScreen: .hardware, hardwareIsSoundOutput: false, hardwareConnected: true) == .passThrough)
}
```
Port the existing `KeyRouter.route` tests in `MediaKeysTests.swift` to the new signature (`.lg` → `.hardware`, `pointerOnLG: true` → `pointerScreen: .hardware`, false → `nil`).

- [ ] **Step 2: Run `scripts/test.sh` — expect failures (types missing)**
- [ ] **Step 3: Implement in `Screens.swift`, `EDID.swift`, `MediaKeys.swift`; minimal call-site update in `MediaKeyTap.swift` (`.hardware` case handled like the old `.lg`; `.software` treated as `.passThrough` until Task 3)**
- [ ] **Step 4: Run `scripts/test.sh` and `swift build` — all PASS, clean build**
- [ ] **Step 5: Commit** `feat: identify screens and add software dimming logic`

---

### Task 3: Screen catalog, overlays, keys and window moving (app)

Depends on Tasks 1 and 2.

**Files:**
- Create: `Sources/LGControl/ScreenCatalog.swift`, `Sources/LGControl/SoftwareBrightness.swift`
- Modify: `MediaKeyTap.swift`, `MonitorModel.swift`, `WindowShuffler.swift`, `WindowDragMonitor.swift`, `WindowMover.swift`, `HUD.swift`, `LGControlApp.swift`

**Interfaces (produces):**
- `@MainActor enum ScreenCatalog`:
  - `static func infos() -> [(ScreenInfo, NSScreen)]` from `NSScreen.screens` (display ID from `NSScreenNumber`; `CGDisplayIsBuiltin`, `CGDisplayVendorNumber`, `CGDisplayModelNumber`, `CGDisplaySerialNumber`).
  - `static var hardwareEDID: EDIDInfo?` — set by `MonitorModel` whenever a refresh publishes details (`details?.edid`).
  - `static func kind(of screen: NSScreen) -> ScreenKind?`, `static func hardwareScreen() -> NSScreen?`, `static func softwareScreens() -> [(key: String, name: String, screen: NSScreen)]` (name = `NSScreen.localizedName`), `static func screenUnderPointer() -> NSScreen?`.
  - Replaces `MediaKeyTap.lgScreen()` everywhere (delete it): WindowShuffler, WindowDragMonitor, `MonitorModel.showHUD`.
- `@MainActor final class SoftwareBrightness: ObservableObject`:
  - `@Published private(set) var screens: [SoftwareScreen]` where `struct SoftwareScreen: Identifiable { id: String /* key */; name: String; level: Int }`.
  - `func setLevel(_ level: Int, for key: String)` — clamps, persists `SoftwareLevels` JSON under UserDefaults key `"softwareBrightness"`, updates the overlay.
  - `func handleMediaKey(_ event: MediaKeyEvent, fine: Bool, on screen: NSScreen)` — steps with `Stepper.step(current:maximum: 100, up:, fine:)`, sets the level, shows the HUD (`.brightness`, level/100) on that screen.
  - Rebuilds `screens` and overlays on `NSApplication.didChangeScreenParametersNotification` and `NSWorkspace.didWakeNotification` (and in `init`).
  - Owns one overlay `NSPanel` per software screen with level < 100, per the spec: borderless, `backgroundColor = .black`, `alphaValue = opacity`, `ignoresMouseEvents = true`, `hasShadow = false`, `isOpaque = false`, frame = `screen.frame`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, `level = .screenSaver`, can't become key/main, `orderFrontRegardless()`. Level 100 → panel closed and dropped.
- `HUD` panel level raised to `NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)` so it shows over an overlay.
- `MediaKeyTap`: route with `pointerScreen: ScreenCatalog.screenUnderPointer().flatMap(ScreenCatalog.kind)`; `.software` → `softwareBrightness.handleMediaKey(...)` (the tap gets a `weak var softwareBrightness`). `canHandle` for brightness over a software screen is always true. Keep the existing `MediaKeyGate` flow.
- `WindowShuffler.moveAllWindowsToBuiltIn` → `moveWindowsOffHardwareScreen()`: destination = built-in screen, else first screen that is neither built-in nor hardware (i.e. a software screen), else do nothing. Its own-windows step (`WindowMover`) uses the same destination. `MonitorModel.switchTo` uses `WindowPlacement.shouldMoveOff(target:macPort:destinationAvailable:)`.
- `LGControlApp` creates one `SoftwareBrightness` (pass `UserDefaults.standard`), injects it as an environment object and into the key tap via `MonitorModel`.

- [ ] **Step 1: Write failing tests** — none possible for AppKit glue beyond Task 2's; instead add to `ScreensTests.swift` any pure helper you extract (e.g. destination choice: `WindowPlacement.destination(kinds: [ScreenKind]) -> Int?` returning the index of the built-in, else the first `.software`, else nil) with tests `destinationPrefersBuiltIn`, `destinationFallsBackToSoftwareScreen`, `destinationNoneWhenOnlyHardware`.
- [ ] **Step 2: Run `scripts/test.sh` — new tests fail**
- [ ] **Step 3: Implement the files above**
- [ ] **Step 4: Run `scripts/test.sh` and `swift build` — all PASS, clean build. `grep -rn "lgScreen" Sources` returns nothing.**
- [ ] **Step 5: Commit** `feat: software brightness for screens without hardware control`

---

### Task 4: Menu bar, Settings, copy and README (app + lgctl)

Depends on Task 3.

**Files:**
- Modify: `Sources/LGControl/MenuBarContent.swift`, `ContentView.swift`, `SettingsView.swift`, `DetailsView.swift`, `KeepAwakeModel.swift`, `LGControlApp.swift`, `MonitorModel.swift` (copy only), `Sources/lgctl/main.swift`, `README.md`

**Requirements:**
- Menu bar panel: header = hardware screen's EDID name, else "No screen with hardware control" (secondary). Port rows read the port label; the Mac's port row also shows a small secondary "This Mac". Then, per software screen, a section headed by its name with a brightness slider (0–100) bound to `SoftwareBrightness.setLevel`. Software section shows even with no hardware screen. Keep Awake "away" card: title = `monitor.lastInput?.label ?? "Other input"`, subtitle "while the screen shows it".
- Main window (`ContentView`): same name/empty-state copy; "Showing \(input.label)" logic compares against `macPort`; the always-work hint: "Input buttons always work, so you can switch the screen back to this Mac."; disconnected body: "Brightness, contrast and volume come back as soon as the screen answers — Screen Monitor keeps checking."
- Settings:
  - Inputs section gains a `Picker("This Mac is on", selection: $model.macPort)` over `Input.allCases`.
  - Command help text: "LG monitors switch inputs reliably only with LG’s own command. Other monitors use the standard command."
  - Keyboard: "Brightness keys change the screen under the pointer: the hardware screen directly, other screens by dimming. Volume and mute change the hardware screen while it’s the sound output."
  - Split: "Screen split (drag a window onto the hardware screen)"; "While you drag a window on that screen, two halves appear. Drop it on one to fill that half."
  - Sync: "The screen keeps the difference it has when you turn this on. Changing it yourself sets a new difference."
  - Keep Awake: "Keep awake while the screen shows another input".
- `MonitorModel.describe`: "The screen didn’t answer the capabilities request." `defaultLGName` stays only as the CoreAudio fallback name (internal).
- `lgctl`: every "LG not connected" → "No screen with hardware control found".
- README: describe ports + "This Mac is on", software brightness for DisplayLink/other screens (darken-only, set the screen to 100% with its own buttons first), the LG command as an LG-specific option; no "PS5/Windows" device mapping.
- Check: `grep -rn '"[^"]*\bLG\b' Sources/LGControl Sources/lgctl` lists only the Settings option label and code comments/internal names (no other user-visible string).

- [ ] **Step 1: Implement**
- [ ] **Step 2: Run `scripts/test.sh` and `swift build` — all PASS, clean build; run the grep check**
- [ ] **Step 3: Commit** `feat: generic screen copy, ports and software screen sliders in the UI`
