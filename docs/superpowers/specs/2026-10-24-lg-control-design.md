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
- USB-C value not verified. Default `0x1B` (MCCS USB-C); must be changeable without code changes.

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
