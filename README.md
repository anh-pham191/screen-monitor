# Screen Monitor

A small personal macOS app (macOS 14+) that controls a monitor over DDC/CI: brightness,
contrast, volume, mute and input switching (HDMI 1, HDMI 2 and USB-C), from a window or the
menu bar. It talks to the monitor through Apple's private `IOAVService` API, so it works on
Apple silicon over HDMI. Screens without DDC (DisplayLink and the like) get software
brightness instead, see below.

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

## Menu bar app

Screen Monitor has no Dock icon by default and opens only its menu bar icon, including at login.
Choose Open Screen Monitor from the menu bar icon to show the window, and Quit to exit. Settings ›
General › Show in Dock brings the Dock icon back.

## Brightness and volume keys

The app can take over the normal Mac keys:

- **Brightness keys (F1/F2):** change the screen under the pointer: the hardware screen directly,
  other external screens by dimming them (see below). With the pointer on the MacBook they change
  the MacBook as usual.
- **Volume and mute keys (F10–F12):** change the hardware screen while it's the sound output (the
  output named after the screen). Otherwise they change the Mac's output as usual. A volume key
  while muted unmutes first.
- **⌥⇧ with any of these keys:** quarter steps, as on a normal Mac.
- **Any other modifier** (⌥ alone, ⌘, ⌃, ⇧ alone): the key goes to macOS untouched, so shortcuts
  such as ⌥ + brightness (Displays settings) and ⌥ + volume (Sound settings) keep working.

An indicator like the macOS one appears on the screen for each press. Turn the feature off in
Settings › Keyboard › Control brightness and volume keys.

### Accessibility permission

The keys (and the screen split) need Accessibility permission. On first launch macOS asks for
it; or open Settings › Keyboard and press **Open System Settings**, then switch on **Screen Monitor** under Privacy &
Security › Accessibility. The app notices within a second; no restart needed. Without the
permission everything else works and the keys stay with macOS.

Quit MonitorControl (or any other app that grabs the media keys) first: two key taps fight over
the same presses.

## Screen split

Drag any window onto the hardware screen and two halves appear on it. Drop the window with the pointer over
one and it fills that half. On the MacBook screen nothing changes. Turn it off in Settings ›
Windows › Screen split (drag a window onto the hardware screen).

It needs the same Accessibility permission as the keys. It only counts a real drag: the window
has to move more than 4 pt without changing size, so resizing from the left or top edge never
shows the halves. Screen Monitor's own windows are left alone.

**macOS tiling:** macOS 15 and later tile windows too, when you drag one to a screen edge or hold
⌥ while dragging. Both can show at once near the screen's edges. If they get in each other's way,
turn off System Settings › Desktop & Dock › Windows › **Drag windows to screen edges to tile**
(and **Hold ⌥ key while dragging windows to tile**), or turn off the screen split here.

## Screens without hardware control (DisplayLink etc.)

Some external screens, such as those on a DisplayLink dock, have no DDC route, so their real
brightness can't be changed from the Mac. Screen Monitor dims them in software instead: a
click-through black overlay whose opacity sets the level. Each one gets its own slider in the
menu bar panel, headed by its name. This works whether or not a hardware screen is connected.

- **Darken only.** The overlay can't make a screen brighter than it is. Set the screen to 100%
  with its own buttons first, then dim from here.
- **Brightness keys follow the pointer.** With the pointer on such a screen they step its level,
  with the same ⌥⇧ fine steps.
- **Level 0 is not black.** It leaves about 10% light so a screen can't be dimmed out of reach.
- **Remembered per screen.** Each screen keeps its level across launches; two identical screens
  keep separate levels.
- **Screenshots.** The overlays aren't meant to show up in screenshots or screen sharing; that
  is best effort, and some capture tools may still include them.

## Follow MacBook brightness

Settings › Brightness › **Follow MacBook brightness** makes the hardware screen track the
MacBook's built-in display, including auto-brightness. Twice a second the app reads the MacBook
level and, when it has moved by at least 1%, sets the screen to that level plus an offset.

- **Turning it on** keeps the screen where it is: the current difference becomes the offset.
- **Changing the screen yourself** (slider, menu bar or brightness keys) sets a new offset, so the
  screen keeps the new difference from then on.
- **Offset** shows the difference in the screen's brightness units. **Reset** sets it to 0 and
  moves the screen to the MacBook level straight away.

The main window shows `Following MacBook` under Brightness while it's on. The MacBook level comes
from the private DisplayServices framework (read only; nothing is written to the MacBook).

## Keep Awake

The Keep Awake section of the menu bar panel stops both the screens and the Mac going to sleep
while you're not touching them. Pick a preset (`1h`, `2h`, `4h`, `6h`, `8h` or
`10h`) and a card shows a ring that empties as time runs out, a running clock and when it ends,
with a small ✕ to stop. Picking another
preset starts again from now. While it runs, the menu bar icon shows the time left, such as
`1h 15m`.

- **Away rule:** Settings › Keep Awake › **Keep awake while the screen shows another input** (on
  by default) keeps the Mac awake while the screen is on a port other than the Mac's, and the
  badge reads that port, such as `HDMI 2`. It ends when you switch back to the Mac from Screen
  Monitor. The screen answers on every input, so a switch made with the monitor's own buttons
  can't be seen; the rule therefore gives up after 8 hours.
- **Battery rule:** **Stop when battery is below** (5–50%, default 20%) ends Keep Awake when the
  MacBook is on battery and drops below that level, and the panel shows
  `Stopped: battery below 20%`. Plugged in, Keep Awake runs until its timer ends.

To check the hold, run:

```sh
pmset -g assertions | grep -i "Screen Monitor"
```

While Keep Awake holds it lists two `Screen Monitor: Keep Awake` assertions (display and system
idle sleep); after Stop, or when the app quits, it lists none.

## Tests

```sh
scripts/test.sh                       # whole suite
scripts/test.sh --filter MonitorReadout  # one area
```

Run tests only through this script: with Command Line Tools, plain `swift test` can't find the
`Testing` module.

## lgctl

A command-line tool for poking the hardware screen directly:

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

## Ports and input values

The three buttons are ports: HDMI 1, HDMI 2 and USB-C. Settings › Inputs › **This Mac is on**
names the port the Mac is plugged into (default HDMI 1). Leaving it moves windows off the
hardware screen, and switching back restores the sound output; Keep Awake treats any other port
as "away". The menu bar marks the Mac's port with a small `This Mac`.

Settings › Inputs › Switch command picks how a switch is sent. It defaults to LG's own command
for LG monitors and to the standard one for everything else, but only until you save a choice;
changing it resets the three values to that command's defaults.

- **LG monitors (VCP 0xF4 at 0x50):** LG's own command holds the new input, where the standard
  one makes some LG screens go black and bounce straight back to HDMI 1. Data address `0x50`.
- **Standard (VCP 0x60 at 0x51):** what other monitors use.

| Port | LG command | Standard |
|---|---|---|
| HDMI 1 | `0x90` (verified) | `0x11` |
| HDMI 2 | `0x91` (verified) | `0x12` |
| USB-C | `0xD1` (default) | `0x0F` (default) |

The USB-C values aren't verified. Under LG's command USB-C is conventionally `0xD1`
(DisplayPort `0xD0`). Under standard, an LG advertises `11 12 0F 00` for input source, so `0x0F`
is the best guess. If the USB-C button doesn't switch, change the value in Settings. Details ›
Inputs advertised by monitor lists the standard `0x60` values.

Settings saved before ports existed load with their stored values: the old Mac, PS5 and Windows
values become HDMI 1, HDMI 2 and USB-C.

## Launch at login

Settings › Launch at login registers the app with `SMAppService`. Two caveats:

- Ad-hoc builds only (no signing certificate, see above): the signature changes on every build,
  so after reinstalling with `scripts/build-app.sh`, toggle Launch at login off and on again.
- It only works from the installed `.app`, not under `swift run`.
