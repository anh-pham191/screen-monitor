# LG Control

A small personal macOS app (macOS 14+) that controls an LG ULTRAFINE over DDC/CI:
brightness, contrast, volume, mute and input switching (Mac, PS5 and Windows), from a
window or the menu bar. It talks to the monitor through Apple's private `IOAVService` API,
so it works on Apple silicon over HDMI.

## Build and install

```sh
scripts/build-app.sh
```

This builds a release binary, wraps it in `LG Control.app`, signs it ad hoc and installs it to
`~/Applications/LG Control.app` (replacing any running copy). Command Line Tools are enough;
Xcode isn't needed.

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

- The ad-hoc signature changes on every build, so after reinstalling with `scripts/build-app.sh`,
  toggle Launch at login off and on again.
- It only works from the installed `.app`, not under `swift run`.
