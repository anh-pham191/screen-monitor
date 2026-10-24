# LG Control

A small personal macOS app (macOS 14+) that controls an LG ULTRAFINE over DDC/CI:
brightness, contrast, volume, mute and input switching (Mac, PS5 and Windows), from a
window or the menu bar. It talks to the monitor through Apple's private `IOAVService` API,
so it works on Apple silicon over HDMI.

## Build and install

```sh
scripts/build-app.sh
```

This builds a release binary, wraps it in `LG Control.app`, signs it and installs it to
`~/Applications/LG Control.app` (replacing any running copy). Command Line Tools are enough;
Xcode isn't needed.

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

The keys need Accessibility permission. On first launch macOS asks for it; or open Settings ›
Keyboard and press **Open System Settings**, then switch on **LG Control** under Privacy &
Security › Accessibility. The app notices within a second; no restart needed. Without the
permission everything else works and the keys stay with macOS.

Quit MonitorControl (or any other app that grabs the media keys) first: two key taps fight over
the same presses.

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
swift run lgctl caps             # capabilities string, model, MCCS version, inputs
swift run lgctl info             # EDID name, serial, connection, resolution, refresh
```

Codes and values are hex.

## Input values

| Input | VCP 0x60 value |
|---|---|
| Mac (HDMI 1) | `0x11` (verified) |
| PS5 (HDMI 2) | `0x12` (verified) |
| Windows (USB-C) | `0x0F` (default) |

The USB-C value isn't verified. The LG advertises `11 12 0F 00` for input source, so `0x0F` is
the best guess. If the Windows button doesn't switch, change the value in Settings: try `0x1B`,
`0x10`, or another value listed under Details › Inputs advertised by monitor.

## Launch at login

Settings › Launch at login registers the app with `SMAppService`. Two caveats:

- Ad-hoc builds only (no signing certificate, see above): the signature changes on every build,
  so after reinstalling with `scripts/build-app.sh`, toggle Launch at login off and on again.
- It only works from the installed `.app`, not under `swift run`.
