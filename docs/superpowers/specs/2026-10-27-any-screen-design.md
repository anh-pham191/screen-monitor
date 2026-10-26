# Any screen: ports, generic naming and software brightness

Date: 2026-10-27. Status: approved in chat by Anh.

## Why

The MacBook now also drives two Philips 253V7L screens through a DisplayLink dock. The app was
built around one LG and one set of devices (Mac on HDMI 1, PS5 on HDMI 2, Windows on USB-C).
Devices on the ports change, and other screens are in use, so the app should talk about ports
and screens, not about an LG and a PS5.

Verified on this Mac (read-only): DisplayLink screens show up in CoreGraphics with their own
vendor/model/serial (Philips: vendor 0x410C, model 0xC171) but have no DDC route: there is no
`DCPAVServiceProxy` for them and their IORegistry `Metadata` holds no EDID. So their brightness
can only be changed in software.

## Goals

1. **Ports, not devices.** Input buttons read "HDMI 1", "HDMI 2", "USB-C". A Settings choice,
   "This Mac is on", names the Mac's port (default HDMI 1). Everything that today means
   "leaving / returning to the Mac" (move windows off the screen, restore sound, start at the
   Mac's port, Keep Awake while away) keys off that port instead of `.mac`/`.ps5`.
2. **No "LG" in anything a person sees**: app UI, HUD, Settings, Keep Awake text, power
   assertion reason, `lgctl` messages, README. The hardware screen appears under its EDID name.
   When there is none: "No screen with hardware control" (menu/window), and
   `lgctl`: "No screen with hardware control found".
3. **The right screen is the hardware screen.** Today "the LG" is "the first non-built-in
   screen", which with DisplayLink screens attached can be a Philips. The hardware screen is the
   external screen whose CoreGraphics vendor and model match the EDID read from the DDC path.
   Brightness keys, HUD, window moving and the screen split use that screen.
4. **Software brightness for every other external screen** (any number; DisplayLink today):
   a click-through black overlay whose opacity sets the brightness. Per-screen level 0–100,
   default 100 (no overlay), remembered across launches per screen.
   - Brightness keys over such a screen step its level (same 16 / 64 fine steps and modifier
     rules as the hardware screen) and show the HUD on that screen.
   - The menu bar panel lists each one by name with a brightness slider.
   - Works whether or not a hardware screen is connected.
5. **Input command.** LG's command (VCP 0xF4 @ 0x50) stays available and is the default when
   the hardware screen's maker is LG (EDID manufacturer "GSM"); any other maker defaults to the
   standard command. This only picks the default when no input settings were ever saved; a saved
   choice always wins. Settings labels: "LG monitors (VCP 0xF4)" and "Standard (VCP 0x60)".

## Non-goals

- More than one hardware (DDC) screen. One hardware screen + any number of software screens.
- Contrast, volume or input switching for software screens (needs DDC).
- Following MacBook brightness for software screens.
- Renaming code (`LGKit`, `lgctl`, `LGControl`, type names) or the bundle ID
  `com.anhpham.lgcontrol` (kept so Accessibility, login item and settings survive).
- Gamma-table dimming (not honoured by DisplayLink).

## Behaviour details

- **Dimming curve:** overlay opacity = 0.9 × (1 − level/100). Level 0 leaves 10% light, so a
  screen can never go fully black by accident. Level 100 removes the overlay window entirely.
- **Overlay window:** borderless, black, ignores mouse events, no shadow, covers the screen's
  full frame including the menu bar, joins all Spaces and full-screen Spaces, never key or main.
  It sits above normal windows and the menu bar; the HUD sits above the overlay.
- **Screen identity** for remembering levels: `"<vendor hex>-<model hex>-<serial>"` from
  CoreGraphics; two identical Philips differ by serial. If a serial is 0, the key adds the
  screen's position in the CoreGraphics list so they still differ.
- **Rebuild** overlays on screen-parameter changes and after wake.
- **Leaving the Mac's port:** windows on the hardware screen move to the MacBook screen; if the
  lid is closed, to the first other screen that isn't the hardware screen; if none, they stay.
- **Keep Awake "away" rule:** the setting reads "Keep awake while the screen shows another
  input"; the menu bar badge and the ring card show the port it's on (e.g. "HDMI 2"); the power
  assertion reason is "The screen is showing another input". The stored setting key stays
  `keepAwakePS5` so Anh's choice carries over.
- **Saved input values migrate:** a saved config with keys `mac`/`ps5`/`windows` decodes into
  `hdmi1`/`hdmi2`/`usbC`.

## Left to the builder

Exact SwiftUI layout of the new menu section (keep it in the existing panel style: screen name
as the section label, a slider row like the existing brightness row), file split inside the app
target.
