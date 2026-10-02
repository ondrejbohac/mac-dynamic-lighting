# Research tools

Throwaway tools used while reverse engineering the Lenovo Legion Pro 34WD-10. They are kept for reference and are not needed by the app.

| File | Purpose |
| --- | --- |
| `ddc.swift` | Raw DDC/CI CLI for Apple Silicon: capabilities string, get/set any VCP code, scan all codes. Build with `swiftc -O ddc.swift -o ddc`. |
| `light.sh` | Legion effects via the `0xF8`/`0xF7` index pair, built on top of `ddc`. |
| `hidlisten.swift` | Passively prints input reports from the Realtek scaler HID (`0bda:1100`). |
| `usbdesc.py` | Dumps the USB descriptors and HID report descriptors of `17ef:a5b5` via libusb. |
| `lamparray.py` | First working LampArray client (libusb). |
| `dumps/` | Full VCP scans with the strip off and on. They are identical, which is how we learned the strip is not controlled by plain VCP codes. |

The Python tools need `brew install libusb` and `pip install pyusb`.
