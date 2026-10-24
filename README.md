# Screen Monitor

A small personal macOS app (macOS 14+) that controls an LG ULTRAFINE over DDC/CI:
brightness, contrast, volume, mute and input switching (Mac, PS5 and Windows), from a
window or the menu bar. It talks to the monitor through Apple's private `IOAVService` API,
so it works on Apple silicon over HDMI.

## Build and install

```sh
scripts/build-app.sh
```

This builds a release binary, wraps it in `Screen Monitor.app`, signs it and installs it to
`~/Applications/Screen Monitor.app` (replacing any running copy). Command Line Tools are enough;
Xcode isn't needed.

> Upgrading from LG Control: delete ~/Applications/LG Control.app; the bundle ID is unchanged, so permissions and settings carry over (toggle Launch at login off and on once).

### One-time signing certificate

macOS ties the Accessibility permission (and Launch at login) to the app's code signature. An
ad-hoc signature changes on every build, so the permission would reset each time. Run this once:

```sh
scripts/make-signing-cert.sh
```

It creates a self-signed code-signing certificate, `LG Control Local Signing`, in the login
keychain and asks for your password (once or twice). From then on `scripts/build-app.sh` signs
with it, and the permission survives rebuilds. Without it the build still works, signs ad hoc
and prints a warning.

## Brightness and volume keys

The app can take over the normal Mac keys for the LG:

- **Brightness keys (F1/F2):** change the LG while the pointer is on the LG. With the pointer on
  the MacBook they change the MacBook as usual.
- **Volume and mute keys (F10–F12):** change the LG while it's the sound output (the output named
  after the LG, `LG ULTRAFINE`). Otherwise they change the Mac's output as usual. A volume key
  while muted unmutes first.
- **⌥⇧ with any of these keys:** quarter steps, as on a normal Mac.
- **Any other modifier** (⌥ alone, ⌘, ⌃, ⇧ alone): the key goes to macOS untouched, so shortcuts
  such as ⌥ + brightness (Displays settings) and ⌥ + volume (Sound settings) keep working.

An indicator like the macOS one appears on the LG for each press. Turn the feature off in
Settings › Keyboard › Control brightness and volume keys.

### Accessibility permission

The keys (and the screen split) need Accessibility permission. On first launch macOS asks for
it; or open Settings › Keyboard and press **Open System Settings**, then switch on **Screen Monitor** under Privacy &
Security › Accessibility. The app notices within a second; no restart needed. Without the
permission everything else works and the keys stay with macOS.

Quit MonitorControl (or any other app that grabs the media keys) first: two key taps fight over
the same presses.

## Screen split

Drag any window onto the LG and two halves appear on it. Drop the window with the pointer over
one and it fills that half. On the MacBook screen nothing changes. Turn it off in Settings ›
Windows › Screen split (drag a window onto the LG).

It needs the same Accessibility permission as the keys. It only counts a real drag: the window
has to move more than 4 pt without changing size, so resizing from the left or top edge never
shows the halves. Screen Monitor's own windows are left alone.

**macOS tiling:** macOS 15 and later tile windows too, when you drag one to a screen edge or hold
⌥ while dragging. Both can show at once near the LG's edges. If they get in each other's way,
turn off System Settings › Desktop & Dock › Windows › **Drag windows to screen edges to tile**
(and **Hold ⌥ key while dragging windows to tile**), or turn off the screen split here.

## Follow MacBook brightness

Settings › Brightness › **Follow MacBook brightness** makes the LG track the MacBook's built-in
display, including auto-brightness. Twice a second the app reads the MacBook level and, when it
has moved by at least 1%, sets the LG to that level plus an offset.

- **Turning it on** keeps the LG where it is: the current difference becomes the offset.
- **Changing the LG yourself** (slider, menu bar or brightness keys) sets a new offset, so the
  LG keeps the new difference from then on.
- **Offset** shows the difference in the LG's brightness units. **Reset** sets it to 0 and moves
  the LG to the MacBook level straight away.

The main window shows `Following MacBook` under Brightness while it's on. The MacBook level comes
from the private DisplayServices framework (read only; nothing is written to the MacBook).

## Tests

```sh
scripts/test.sh                       # whole suite
scripts/test.sh --filter MonitorReadout  # one area
```

Run tests only through this script: with Command Line Tools, plain `swift test` can't find the
`Testing` module.

## lgctl

A command-line tool for poking the monitor directly:

```sh
swift run lgctl read 10          # read VCP 0x10 (brightness)
swift run lgctl read 60 --raw    # also print the raw reply bytes
swift run lgctl set 10 1a        # write VCP 0x10 = 0x1A
swift run lgctl set f4 91 --addr 50  # LG's own input command: switch to HDMI 2
swift run lgctl caps             # capabilities string, model, MCCS version, inputs
swift run lgctl info             # EDID name, serial, connection, resolution, refresh
```

Codes and values are hex. `--addr` sets the I2C data address for `set` (default `51`, the
standard DDC/CI address); LG's own input command needs `50`.

## Input values

The standard input switch (VCP `0x60` at data address `0x51`) makes this LG go black and bounce
straight back to HDMI 1. LG's own command holds the new input: VCP `0xF4` written to data address
`0x50`. Settings › Inputs › Switch command picks between them (LG is the default); changing it
resets the three values to that command's defaults.

| Input | LG command (VCP 0xF4 at 0x50) | Standard (VCP 0x60 at 0x51) |
|---|---|---|
| Mac (HDMI 1) | `0x90` (verified) | `0x11` |
| PS5 (HDMI 2) | `0x91` (verified) | `0x12` |
| Windows (USB-C) | `0xD1` (default) | `0x0F` (default) |

The USB-C values aren't verified. Under LG's command USB-C is conventionally `0xD1`
(DisplayPort `0xD0`). Under standard, the LG advertises `11 12 0F 00` for input source, so `0x0F`
is the best guess. If the Windows button doesn't switch, change the value in Settings. Details ›
Inputs advertised by monitor lists the standard `0x60` values.

Settings saved before the switch command existed load as Standard with their stored values.

## Launch at login

Settings › Launch at login registers the app with `SMAppService`. Two caveats:

- Ad-hoc builds only (no signing certificate, see above): the signature changes on every build,
  so after reinstalling with `scripts/build-app.sh`, toggle Launch at login off and on again.
- It only works from the installed `.app`, not under `swift run`.
