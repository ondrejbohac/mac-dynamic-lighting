import sys, struct, usb.core, usb.backend.libusb1 as lb
be = lb.get_backend(find_library=lambda x: "/opt/homebrew/lib/libusb-1.0.dylib")
d = usb.core.find(idVendor=0x17ef, idProduct=0xa5b5, backend=be)
IF = 1
def get(rid, n): return bytes(d.ctrl_transfer(0xA1, 0x01, 0x0300 | rid, IF, n))
def put(rid, data): d.ctrl_transfer(0x21, 0x09, 0x0300 | rid, IF, bytes([rid]) + data)

def attrs():
    r = get(7, 64)
    cnt, bx, by, bz, kind, interval = struct.unpack_from("<HIIIII", r, 1)
    return dict(lamps=cnt, box_um=(bx, by, bz), kind=kind, min_update_us=interval)

def color(r, g, b, i=255):
    n = attrs()["lamps"]
    put(0x0C, bytes([0]))                                    # AutonomousMode off
    put(0x0B, struct.pack("<BHHBBBB", 1, 0, n - 1, r, g, b, i))  # LampRangeUpdate, complete

cmd = sys.argv[1] if len(sys.argv) > 1 else "info"
if cmd == "info":
    print(attrs())
elif cmd == "lamp":
    put(8, struct.pack("<H", int(sys.argv[2]))); print(get(9, 64).hex())
elif cmd == "color":
    color(*[int(x) for x in sys.argv[2:]])
elif cmd == "auto":
    put(0x0C, bytes([1]))
