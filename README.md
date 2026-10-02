# Mac Dynamic Lighting

Control RGB lighting on macOS for devices that support **Windows Dynamic Lighting** (the HID LampArray standard). A small native menu bar app, no drivers, no background daemons.

Windows 11 has a built-in "Dynamic Lighting" panel that can set the color of compatible monitors, keyboards, mice and LED strips. Those devices all speak the same standard USB HID protocol, *LampArray*, but macOS has nothing that uses it, so the lighting is stuck on whatever the device does by default. This app fills that gap.

## Features

- Finds Dynamic Lighting (HID LampArray) devices automatically.
- Solid color with presets plus hue, saturation and brightness.
- **Off**, and **Built-in** to hand the lighting back to the device's own effects.
- Re-applies your color after sleep, display reconnects and device replugs.
- Launch at login.
- Command line interface for scripts, Shortcuts or Raycast.
- **Lenovo Legion Pro 34WD-10:** additionally controls the monitor's built-in effects (Breathing, Flashing, Marquee, Rainbow Wave, Starry Sky), with speed and brightness, over DDC/CI.

## Compatibility

| Device | Status |
| --- | --- |
| Lenovo Legion Pro 34WD-10 | Tested: colors and built-in effects |
| Other devices supported by Windows Dynamic Lighting | Should work for colors. Untested, reports welcome |
| RGB devices without Dynamic Lighting support | Not supported: they use proprietary protocols |

If your device shows up in Windows under *Settings → Personalization → Dynamic Lighting*, it is a LampArray device. Please open an issue with the output of `DynamicLighting list`, whether it works or not.

Requires macOS 13 or later on Apple Silicon.

## Install

1. Download the latest `DynamicLighting-x.y.z.dmg` from [Releases](../../releases).
2. Drag **Dynamic Lighting** to Applications.
3. The app is not notarized, so macOS blocks it on first launch. Either right-click the app and choose **Open**, or allow it under *System Settings → Privacy & Security*, or run:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/Dynamic Lighting.app"
   ```

The app lives in the menu bar (LED strip icon); there is no Dock icon.

Keyboards and mice that macOS already drives may trigger an *Input Monitoring* permission prompt the first time the app talks to them.

## Command line

The app binary doubles as a CLI. Commands apply to all devices found:

```sh
DL="/Applications/Dynamic Lighting.app/Contents/MacOS/DynamicLighting"
"$DL" list                          # show detected devices
"$DL" color 255 255 255             # solid color (R G B)
"$DL" off
"$DL" builtin                       # back to the device's own effects
"$DL" legion-effect rainbowwave 10  # Legion Pro 34WD-10 only: effect, cycle seconds, [brightness]
```

## Build from source

```sh
./scripts/build-app.sh   # → build/Dynamic Lighting.app
./scripts/make-dmg.sh    # → build/DynamicLighting-<version>.dmg
```

Pushing a `v*` tag builds the DMG with GitHub Actions and attaches it to a release.

## How it works

See [PROTOCOL.md](PROTOCOL.md) for the details, including the reverse-engineered Lenovo DDC codes. In short:

- **Colors:** the LampArray feature reports (`LampArrayControl` to disable autonomous mode, `LampRangeUpdate` to paint all lamps). Report IDs are read from each device's HID report descriptor.
  - USB interfaces that macOS leaves without a driver are driven with plain control transfers on the default pipe.
  - Interfaces that already have the HID driver attached go through `IOHIDDevice`.
- **Legion effects:** Lenovo's indexed VCP pair `0xF8`/`0xF7` over DDC/CI, using the Apple Silicon `IOAVService` I2C API.

The `research/` folder contains the throwaway tools and dumps used to figure all this out.

## Disclaimer

Not affiliated with Lenovo or Microsoft. Use at your own risk. The app only sends standard LampArray reports and the same DDC commands as Lenovo's own software, and never touches firmware update channels.

## License

[MIT](LICENSE)
