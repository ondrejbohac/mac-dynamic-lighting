# Protocol notes

## HID LampArray (any Dynamic Lighting device)

LampArray is defined in the USB HID Usage Tables, usage page `0x59` (*Lighting and Illumination*). A device exposes a top-level `LampArray` collection (usage `0x01`) with these feature reports:

| Usage | Report | Direction | Used for |
| --- | --- | --- | --- |
| `0x02` | LampArrayAttributesReport | get | `LampCount` (u16) is the first field |
| `0x20` / `0x22` | LampAttributesRequest / Response | set / get | per-lamp position, purpose, capabilities (not used yet) |
| `0x50` | LampMultiUpdateReport | set | up to N lamps with individual colors (not used yet) |
| `0x60` | LampRangeUpdateReport | set | `flags u8, lampIdStart u16, lampIdEnd u16, R, G, B, I` |
| `0x70` | LampArrayControlReport | set | `AutonomousMode u8` (1 = device runs its own effects) |

Report IDs are device specific, so the app reads them from the report descriptor. Painting everything one color takes two requests:

```
SET_REPORT feature <control>  [id, 0x00]                                  autonomous mode off
SET_REPORT feature <range>    [id, 0x01, 0x00,0x00, last_lo,last_hi, R,G,B, 0xFF]
```

Flag `0x01` is *LampUpdateComplete*, so the device shows the update immediately.

### macOS specifics

- If macOS attaches its HID driver to the interface, the device appears as an `IOHIDDevice` with `DeviceUsagePage 0x59` and is driven with `IOHIDDeviceSetReport` / `IOHIDDeviceGetReport`.
- Some interfaces get no driver at all, like the Legion monitor's `StripA` below. They never show up as HID devices. Their report descriptor can still be fetched with a standard `GET_DESCRIPTOR (0x22)` control request addressed to the interface. Feature reports are plain `SET_REPORT` / `GET_REPORT` class requests on the device's default pipe. This works without opening the device or claiming the interface.

## Lenovo Legion Pro 34WD-10

USB devices behind the monitor's hub:

| VID:PID | Interface | What it is |
| --- | --- | --- |
| `17ef:a5b5` | 0 | Vendor HID (usage page `0xFF00`), report IDs 1/9 (64 B in/out), feature 0x72 (168 B). Not used. |
| `17ef:a5b5` | 1 `StripA` | **LampArray**, 8 lamps, kind *Peripheral*, bounding box 789.6 × 354.7 × 150 mm, min. update interval 20 ms. Report IDs: attributes 7, lamp request/response 8/9, multi update 10, range update 11, control 12. |
| `0bda:1100` | 0 | Realtek scaler HID (usage page `0xFFDA`), used by Realtek's firmware update tool. **Do not send anything here.** |

`StripA` report descriptor:

```
05590901a10185070902a1020903150027ffff000075109501b10309040905090609070908150027ffffff7f75209505b103c0
85080920a1020921150027ffff000075109501b102c085090922a1020921150027ffff000075109501b10209230924092509
270926150027ffffff7f75209505b10209280929092a092b092c092d150026ff0075089506b102c0850a0950a10209030955
1500250875089502b1020921150027ffff000075109508b102095109520953095409510952095309540951095209530954
0951095209530954095109520953095409510952095309540951095209530954095109520953095409510952095309541500
26ff0075089520b102c0850b0960a10209551500250875089501b10209610962150027ffff000075109502b1020951095209
530954150026ff0075089504b102c0850c0970a10209711500250175089501b102c0c0
```

### Built-in effects over DDC/CI

The monitor's own effects are not part of LampArray. They live behind Lenovo's indexed VCP pair:

1. Write the feature index to VCP `0xF8`.
2. Wait about 50 ms.
3. Write the value to (or read it from) VCP `0xF7`.

| Index | Meaning | Values |
| --- | --- | --- |
| `0x1D` | effect | 0 off, 1 Breathing, 2 Flashing, 3 Marquee, 4 Rainbow Wave, 5 Fireworks, 6 Starry Sky, 7 Rhythm |
| `0x11D` / `0x21D` / `0x31D` | effect color R / G / B | see Flashing below |
| `0x41D` | color preference | 0 default, 1 specified, 2 random |
| `0x51D` | speed | see below |
| `0x61D` | brightness | 0–100 |
| `0x71D` | "overall light mode" (read only) | |

Lenovo's own app offers Breathing, Flashing, Marquee and Rainbow Wave for this model. Starry Sky is what the OSD uses when the light is switched on. Fireworks and Rhythm are listed in the capabilities string, but their behaviour was not verified.

**Speed:** Lenovo's app sends the cycle length in seconds (0.5–20).
- Breathing takes 1–20 as is.
- For Marquee and Rainbow Wave the app maps the seconds to three steps: < 7 s → 0, < 15 s → 1, otherwise 2.
- Flashing and Starry Sky clamp to 0–2. Speed 0 stops them with the strip dark.

**Flashing** stays dark unless the effect color is initialised. The sequence that brought it back:

| Step | Write |
| --- | --- |
| 1 | `0x41D` = 2 (random colors) |
| 2 | R, G and B (`0x11D`, `0x21D`, `0x31D`) = `0xFF00` |
| 3 | effect = 1 (Breathing) |
| 4 | effect = 2 (Flashing) |

Reads of the R/G/B indexes return unreliable values.

None of these codes show up in a plain VCP scan, because they only exist behind the `0xF8` index. Capabilities string, for reference:

```
(prot(monitor)type(LCD)model(Lenovo Legion Pro 34WD-10)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(01 05 06 08 0B 0F) 16 18 1A 52 60(11 12 0F 31 FF 11 12 0F 31) 72(05 78 FB 00 50 64 78 8C A0) 86(02 05) A5(00 01 02) AC AE B2 B6 C6(...) C8 C9(4C) CA CC(02 03 04 05 06 09 0A 0D) D6(01 05) DF E0(00 03 04 05 06) EA(00 01) EB(00 01 02) EC(00 01 FF 00 02 03) EF(00 01 07 08 09) F2(00 01) F4(00 01 02) F5(00 01 02 FF 00 01 04) F6(07) F7(01(07) 02 09(...) 0A(...) 0B(00 01) 0D(00 02) 15(00 01 02) 1A(00 01) 1D(00 01 02 03 05 06 07) 21(00 01)) F8(...) F9(00 01 02 03 04 05 06) FA(...) FB FC FD)mswhql(1)asset_eep(40)mccs_ver(2.2))
```

On Apple Silicon, raw DDC goes through the private `IOAVServiceWriteI2C` / `IOAVServiceReadI2C` on the external display's `DCPAVServiceProxy` (I2C address `0x37`, offset `0x51`). The monitor is identified by the model name in its EDID (`IOAVServiceCopyEDID`).
