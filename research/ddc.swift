import Foundation
import IOKit

typealias IOAVService = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?
@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ s: IOAVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ s: IOAVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

func findExternal() -> IOAVService? {
    var it = io_iterator_t()
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return nil }
    while case let s = IOIteratorNext(it), s != 0 {
        if let loc = IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
           loc == "External", let av = IOAVServiceCreateWithService(kCFAllocatorDefault, s)?.takeRetainedValue() { return av }
    }
    return nil
}

let av = findExternal()!

func send(_ payload: [UInt8]) {
    var p: [UInt8] = [UInt8(0x80 | payload.count)] + payload
    var chk: UInt8 = 0x6E ^ 0x51
    for b in p { chk ^= b }
    p.append(chk)
    for _ in 0..<2 { _ = IOAVServiceWriteI2C(av, 0x37, 0x51, &p, UInt32(p.count)); usleep(10000) }
}
func read(_ n: Int) -> [UInt8]? {
    var b = [UInt8](repeating: 0, count: n)
    usleep(50000)
    return IOAVServiceReadI2C(av, 0x37, 0x51, &b, UInt32(n)) == 0 ? b : nil
}
func getVCP(_ code: UInt8) -> (Int, Int)? {
    for _ in 0..<3 {
        send([0x01, code])
        if let r = read(11), r[2] == 0x02, r[4] == code {
            if r[3] != 0 { return nil }
            return (Int(r[6]) << 8 | Int(r[7]), Int(r[8]) << 8 | Int(r[9]))
        }
    }
    return nil
}
func setVCP(_ code: UInt8, _ v: Int) { send([0x03, code, UInt8(v >> 8), UInt8(v & 0xff)]) }
func caps() -> String {
    var out = [UInt8](); var off = 0
    while off < 4096 {
        var chunk: [UInt8]? = nil
        for _ in 0..<4 {
            send([0xF3, UInt8(off >> 8), UInt8(off & 0xff)])
            if let r = read(38), r[2] == 0xE3, (Int(r[3]) << 8 | Int(r[4])) == off { chunk = r; break }
        }
        guard let r = chunk else { break }
        let len = Int(r[1] & 0x7f) - 3
        if len <= 0 { break }
        out += r[5..<(5 + len)]; off += len
        if out.contains(0) { break }
    }
    return String(decoding: out.filter { $0 != 0 }, as: UTF8.self)
}

let a = CommandLine.arguments
switch a.count > 1 ? a[1] : "" {
case "caps": print(caps())
case "get": let c = UInt8(a[2], radix: 16)!; if let v = getVCP(c) { print(String(format: "%02X cur=%d max=%d", c, v.1, v.0)) } else { print("unsupported") }
case "set": setVCP(UInt8(a[2], radix: 16)!, Int(a[3])!); print("ok")
case "scan":
    let from = a.count > 2 ? Int(a[2], radix: 16)! : 0, to = a.count > 3 ? Int(a[3], radix: 16)! : 0xFF
    for c in from...to { if let v = getVCP(UInt8(c)) { print(String(format: "%02X cur=%d max=%d", c, v.1, v.0)); fflush(stdout) } }
default: print("usage: ddc caps | get XX | set XX val | scan [from to]")
}
