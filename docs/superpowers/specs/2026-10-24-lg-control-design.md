# LG Control — Design

## Intent

Anh wants to control the LG UltraFine external monitor from macOS instead of reaching for its physical buttons. The main daily job is switching the monitor between this Mac (HDMI 1) and a PS5 (HDMI 2), plus adjusting brightness, contrast and volume, and seeing the monitor's details.

This is a personal tool for one Mac. It will never ship on the App Store (it uses a private macOS API).

## Hardware facts (verified 2026-10-24 on this machine)

- Mac: MacBook Pro, Apple M5 Pro, macOS 27.0, Command Line Tools only (no Xcode).
- Monitor: LG ULTRAFINE, 3840×2160, EDID manufacturer `GSM`, product code 23739, serial string `DEMO12345678`, manufactured week 1 of 2026, 60×34 cm. Connected via the Mac's built-in HDMI port. It is the main display; the MacBook's built-in screen is also on.
- Inputs: HDMI 1 = this Mac, HDMI 2 = PS5, USB-C = Windows machine.
- DDC/CI works through `IOAVService` (`DCPAVServiceProxy`, `Location = External`), I2C chip address `0x37`, data address `0x51`.
- Reads verified: brightness `0x10` (26/100), contrast `0x12` (70/100), volume `0x62` (12/100), mute `0x8D` (2 = not muted), input `0x60` (returns 0 — **LG does not report the current input usefully**).
- Input switching verified with the standard VCP `0x60`: HDMI 2 = `0x12`, HDMI 1 = `0x11`. **Switching back to HDMI 1 from the Mac works while the LG is showing HDMI 2.**
- USB-C value not switch-tested. The LG advertises inputs `11 12 0F 00` (read 2026-10-24), so the default is `0x0F`; it must be changeable without code changes.

## Goals

1. Regular windowed macOS app (Dock icon, one main window) with:
   - Brightness, contrast and volume sliders, plus a mute toggle.
   - Three input buttons: **Mac (HDMI 1)**, **PS5 (HDMI 2)**, **Windows (USB-C)**.
   - A **Details** screen: model name, manufacturer, product code, serial number, manufacture week/year, physical size, connection type, resolution and refresh rate, raw current DDC values, and the monitor's DDC capabilities string (best-effort).
2. A **menu bar icon** as a backup, holding the three input buttons, a brightness slider, "Open LG Control" and "Quit".
3. Before switching *away* from the Mac's input, the app **moves its windows to the MacBook's built-in screen** so the controls stay visible.
4. **Launch at login**, toggled in the app.
5. Settings: the raw value sent for each input (hex), so USB-C can be fixed without a rebuild.

## Non-goals

- Global keyboard shortcuts (not chosen).
- Multiple external monitors, other monitor brands, Intel Macs.
- Picture modes, colour presets, power control.
- App Store distribution, notarisation, auto-update.

## Anti-goals

- The app must never crash or hang the UI when the monitor is missing, asleep, on another input, or slow to answer: it shows a "not connected" state and offers Retry.
- Dragging a slider must not flood the monitor with commands (the LG needs ~50 ms between commands): latest value wins.
- Switching to the PS5 must not strand the controls on an invisible screen.

## Decisions (Claude's calls, for Anh to check)

- Swift + SwiftUI, Swift Package Manager (no Xcode project); a script packages the build into `~/Applications/LG Control.app`, ad-hoc signed.
- Swift Testing for unit tests, run through `scripts/test.sh` (wraps the Command Line Tools framework flags).
- Swift language mode 5 to avoid strict-concurrency friction with IOKit and private-API calls.
- Because the LG doesn't report its input, the app shows the **last input it switched to** (persisted), not a live reading.

## Scope extension (2026-10-24): replace MonitorControl and the LG Mac apps

Anh's ultimate goal: LG Control replaces MonitorControl and any LG monitor app on this Mac. Anh uses, and v1 must include:

6. **Keyboard brightness and volume keys** (MonitorControl). The brightness keys adjust the display **under the mouse pointer**: on the LG, the app takes the key and changes the LG; on the MacBook screen, the key passes through to macOS untouched. The volume and mute keys go to the LG only when the LG is the current sound output (verified: the LG is the default output device today); otherwise they pass through. Each key press shows an on-screen indicator on the LG.
7. **Follow MacBook brightness** (MonitorControl sync). When on, the LG's brightness follows the built-in screen's brightness (keys, auto-brightness, Control Centre) plus an offset. Changing the LG by hand while sync is on updates the offset rather than fighting it. Verified: the built-in brightness is readable through `DisplayServicesGetBrightness` (0.465 on 2026-10-24).
8. **Screen split by dragging** (LG Screen Split). While any app's window is dragged on the LG, two zones (left half, right half) appear. Dropping the window in a zone snaps it to that half of the LG.

Non-goals stay as listed, plus: picture modes, firmware updates, layouts other than halves, keyboard snapping, and the screen split on the MacBook screen.

### Decisions (Claude's calls)

- The key capture and the screen split need macOS **Accessibility** permission. The app explains why and links to System Settings when permission is missing. Everything else works without it.
- macOS ties Accessibility permission to the app's code signature, and an ad-hoc signature changes on every build. So a one-time script creates a local self-signed code-signing certificate, and the build signs with it. Permission (and Launch at login) then survives rebuilds.
- The on-screen indicator is the app's own small HUD, styled like the macOS one (icon plus a 16-segment bar). The private OSD framework is not used.
- Key steps: 16 steps over the full range, as macOS uses. ⌥⇧ plus a key gives quarter-steps (64), as on macOS.
- Sync polls the built-in brightness every 0.5 s and ignores changes under 1 %.
- macOS's own "drag windows to screen edges to tile" can double-snap with the screen split. The README suggests turning it off; the app doesn't change system settings.

## Bug fix (2026-10-24 afternoon): LG's own input command

Anh found that PS5 (HDMI 2) did not stick: the standard VCP 0x60 switch makes this LG go black and bounce back to the Mac, even with the app quit (so the morning "switched and came back" test was this bounce, not a working switch). LG's own command — VCP 0xF4 written to I2C data address 0x50, HDMI 1 = 0x90, HDMI 2 = 0x91 — holds the PS5 and switches back on command (verified with Anh). The app now uses LG's command by default (USB-C 0xD1, not yet verified), with Standard (VCP 0x60) selectable in Settings.
