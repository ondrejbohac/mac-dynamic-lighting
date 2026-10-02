import Foundation
import IOKit.hid
let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 0x0bda, kIOHIDProductIDKey: 0x1100] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
print("open:", IOHIDManagerOpen(m, 0)); fflush(stdout)
let devs = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> ?? []
print("devices:", devs.count); fflush(stdout)
for d in devs {
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    IOHIDDeviceRegisterInputReportCallback(d, buf, 4096, { _, _, _, _, id, rep, len in
        let hex = (0..<len).map { String(format: "%02x", rep[$0]) }.joined(separator: " ")
        print(Date(), "id=\(id) len=\(len):", hex); fflush(stdout)
    }, nil)
}
CFRunLoopRunInMode(.defaultMode, Double(CommandLine.arguments.last!) ?? 60, false)
print("done")
