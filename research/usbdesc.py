import usb.core, usb.util, usb.backend.libusb1 as lb
be = lb.get_backend(find_library=lambda x: "/opt/homebrew/lib/libusb-1.0.dylib")
d = usb.core.find(idVendor=0x17ef, idProduct=0xa5b5, backend=be)
print(d)
for intf in (0, 1):
    try:
        r = d.ctrl_transfer(0x81, 0x06, 0x2200, intf, 1024)
        print(f"intf {intf} report descriptor ({len(r)}):", bytes(r).hex())
    except Exception as e:
        print(f"intf {intf} err:", e)
