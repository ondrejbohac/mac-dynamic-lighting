import CUSB
import Foundation
import IOKit
import IOKit.hid

/// A device implementing the HID LampArray standard (usage page 0x59, "Lighting and Illumination"),
/// the protocol behind Windows Dynamic Lighting.
final class LampArrayDevice {
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    private let transport: FeatureTransport
    private let reports: LampArrayReports
    private var cachedLampCount: Int?

    fileprivate init(id: String, name: String, vendorID: Int, productID: Int, transport: FeatureTransport, reports: LampArrayReports) {
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.transport = transport
        self.reports = reports
    }

    /// Lenovo Legion Pro 34WD-10, whose built-in effects are additionally reachable over DDC/CI.
    var isLegionPro34WD10: Bool { vendorID == 0x17EF && productID == 0xA5B5 }

    func lampCount() throws -> Int {
        if let cachedLampCount { return cachedLampCount }
        // LampArrayAttributesReport: LampCount (u16) is the first field.
        let r = try transport.getFeature(reports.attributes, length: 64)
        guard r.count >= 3 else { throw LampArrayError.badReport }
        let count = Int(r[1]) | Int(r[2]) << 8
        cachedLampCount = count
        return count
    }

    /// Takes over the lamps from the device and paints all of them with one color.
    func setColor(red: UInt8, green: UInt8, blue: UInt8) throws {
        let last = UInt16(max(try lampCount() - 1, 0))
        try transport.setFeature(reports.control, [0]) // AutonomousMode off
        try transport.setFeature(reports.rangeUpdate, [
            1, // LampUpdateFlags: update complete
            0, 0, // LampIdStart
            UInt8(last & 0xFF), UInt8(last >> 8), // LampIdEnd
            red, green, blue, 0xFF, // RGB + intensity
        ])
    }

    /// Hands the lamps back to the device's own (autonomous) effects.
    func releaseControl() throws {
        try transport.setFeature(reports.control, [1])
    }
}

enum LampArrayError: Error, CustomStringConvertible {
    case io(Int32)
    case badReport

    var description: String {
        switch self {
        case .io(let code): String(format: "I/O error 0x%08x", UInt32(bitPattern: code))
        case .badReport: "Unexpected LampArray report"
        }
    }
}

// MARK: - Discovery

/// Finds LampArray devices. Two kinds exist on macOS:
/// - USB HID interfaces macOS attaches no driver to (e.g. the Legion monitor's "StripA" interface).
///   They are driven with plain control transfers on the device's default pipe.
/// - Interfaces macOS does attach its HID driver to (keyboards, mice, Bluetooth devices).
///   They are driven through IOHIDDevice.
final class LampArrayDiscovery {
    private let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var descriptorCache: [String: [UInt8]] = [:]

    init() {
        IOHIDManagerSetDeviceMatching(hidManager, [
            kIOHIDDeviceUsagePageKey: 0x59,
            kIOHIDDeviceUsageKey: 0x01,
        ] as CFDictionary)
    }

    func discover() -> [LampArrayDevice] {
        usbDevices() + hidDevices()
    }

    private func usbDevices() -> [LampArrayDevice] {
        var found: [LampArrayDevice] = []
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        while case let intf = IOIteratorNext(iterator), intf != 0 {
            defer { IOObjectRelease(intf) }
            guard property(intf, "bInterfaceClass") as? Int == 3, // HID
                  !hasChildren(intf) else { continue } // has a HID driver: handled by hidDevices()

            var parent = io_registry_entry_t()
            guard IORegistryEntryGetParentEntry(intf, kIOServicePlane, &parent) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(parent) }

            guard let number = property(intf, "bInterfaceNumber") as? Int,
                  let location = property(parent, "locationID") as? Int else { continue }
            let vendor = property(parent, "idVendor") as? Int ?? 0
            let product = property(parent, "idProduct") as? Int ?? 0
            let name = property(parent, "USB Product Name") as? String ?? String(format: "USB %04x:%04x", vendor, product)

            let transport = USBTransport(locationID: UInt32(truncatingIfNeeded: location), interface: UInt16(number))
            let key = "usb:\(location):\(number)"
            guard let descriptor = descriptorCache[key] ?? transport.reportDescriptor() else { continue }
            descriptorCache[key] = descriptor
            guard let reports = LampArrayReports(descriptor: descriptor) else { continue }
            found.append(LampArrayDevice(id: key, name: name, vendorID: vendor, productID: product, transport: transport, reports: reports))
        }
        return found
    }

    private func hidDevices() -> [LampArrayDevice] {
        guard let set = IOHIDManagerCopyDevices(hidManager) as? Set<IOHIDDevice> else { return [] }
        return set.compactMap { device in
            guard let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data,
                  let reports = LampArrayReports(descriptor: [UInt8](descriptor)) else { return nil }
            let service = IOHIDDeviceGetService(device)
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &registryID)
            let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "HID device"
            return LampArrayDevice(id: "hid:\(registryID)", name: name, vendorID: vendor, productID: product,
                                   transport: HIDTransport(device: device), reports: reports)
        }
    }

    private func hasChildren(_ entry: io_registry_entry_t) -> Bool {
        var children = io_iterator_t()
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(children) }
        let child = IOIteratorNext(children)
        if child != 0 { IOObjectRelease(child) }
        return child != 0
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

// MARK: - Report descriptor

/// Report IDs of the LampArray feature reports this app uses, read from the HID report descriptor.
struct LampArrayReports {
    let attributes: UInt8 // LampArrayAttributesReport (usage 0x02)
    let rangeUpdate: UInt8 // LampRangeUpdateReport (usage 0x60)
    let control: UInt8 // LampArrayControlReport (usage 0x70)

    private static let page: UInt32 = 0x59

    init?(descriptor: [UInt8]) {
        var usagePage: UInt32 = 0
        var reportID: UInt8 = 0
        var globals: [(UInt32, UInt8)] = []
        var localUsages: [(page: UInt32, usage: UInt32)] = []
        var collections: [(page: UInt32, usage: UInt32)?] = []
        var isLampArray = false
        var ids: [UInt32: UInt8] = [:]

        var i = 0
        while i < descriptor.count {
            let prefix = descriptor[i]
            if prefix == 0xFE { // long item
                guard i + 1 < descriptor.count else { break }
                i += 3 + Int(descriptor[i + 1])
                continue
            }
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            guard i + size < descriptor.count else { break }
            var value: UInt32 = 0
            for b in 0..<size { value |= UInt32(descriptor[i + 1 + b]) << (8 * b) }
            i += 1 + size

            switch prefix & 0xFC {
            case 0x04: usagePage = value
            case 0x84: reportID = UInt8(truncatingIfNeeded: value)
            case 0xA4: globals.append((usagePage, reportID)) // push
            case 0xB4: if let g = globals.popLast() { (usagePage, reportID) = g } // pop
            case 0x08: localUsages.append(size == 4 ? (value >> 16, value & 0xFFFF) : (usagePage, value))
            case 0xA0: // collection
                let usage = localUsages.first
                if collections.isEmpty, usage?.page == Self.page, usage?.usage == 0x01 { isLampArray = true }
                collections.append(usage)
                localUsages = []
            case 0xC0: _ = collections.popLast()
            case 0xB0: // feature
                for case let c? in collections where c.page == Self.page && [0x02, 0x60, 0x70].contains(c.usage) && ids[c.usage] == nil {
                    ids[c.usage] = reportID
                }
                localUsages = []
            case 0x80, 0x90: localUsages = [] // input, output
            default: break
            }
        }

        guard isLampArray, let a = ids[0x02], let r = ids[0x60], let c = ids[0x70] else { return nil }
        attributes = a
        rangeUpdate = r
        control = c
    }
}

// MARK: - Transports

private protocol FeatureTransport {
    func getFeature(_ id: UInt8, length: Int) throws -> [UInt8]
    func setFeature(_ id: UInt8, _ payload: [UInt8]) throws
}

private struct USBTransport: FeatureTransport {
    let locationID: UInt32
    let interface: UInt16

    func reportDescriptor() -> [UInt8]? {
        // GET_DESCRIPTOR (HID report descriptor) addressed to the interface.
        try? transfer(requestType: 0x81, request: 0x06, value: 0x2200, length: 4096)
    }

    func getFeature(_ id: UInt8, length: Int) throws -> [UInt8] {
        let data = try transfer(requestType: 0xA1, request: 0x01, value: 0x0300 | UInt16(id), length: length) // GET_REPORT
        return id == 0 ? [0] + data : data
    }

    func setFeature(_ id: UInt8, _ payload: [UInt8]) throws {
        var data = id == 0 ? payload : [id] + payload
        let kr = data.withUnsafeMutableBytes {
            usb_control_transfer(locationID, 0x21, 0x09, 0x0300 | UInt16(id), interface, $0.baseAddress, UInt16($0.count), 1000, nil) // SET_REPORT
        }
        guard kr == 0 else { throw LampArrayError.io(kr) }
    }

    private func transfer(requestType: UInt8, request: UInt8, value: UInt16, length: Int) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: length)
        var done: UInt32 = 0
        let kr = buf.withUnsafeMutableBytes {
            usb_control_transfer(locationID, requestType, request, value, interface, $0.baseAddress, UInt16(length), 1000, &done)
        }
        guard kr == 0 else { throw LampArrayError.io(kr) }
        return Array(buf.prefix(Int(done)))
    }
}

private final class HIDTransport: FeatureTransport {
    private let device: IOHIDDevice
    private var isOpen = false

    init(device: IOHIDDevice) { self.device = device }
    deinit { if isOpen { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) } }

    private func open() throws {
        guard !isOpen else { return }
        let kr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard kr == kIOReturnSuccess else { throw LampArrayError.io(kr) }
        isOpen = true
    }

    func getFeature(_ id: UInt8, length: Int) throws -> [UInt8] {
        try open()
        var buf = [UInt8](repeating: 0, count: length)
        var len = CFIndex(length)
        let kr = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &buf, &len)
        guard kr == kIOReturnSuccess else { throw LampArrayError.io(kr) }
        // Numbered reports already start with their ID; normalise unnumbered ones to the same layout.
        let data = Array(buf.prefix(len))
        return id == 0 ? [0] + data : data
    }

    func setFeature(_ id: UInt8, _ payload: [UInt8]) throws {
        try open()
        let data = id == 0 ? payload : [id] + payload
        let kr = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(id), data, data.count)
        guard kr == kIOReturnSuccess else { throw LampArrayError.io(kr) }
    }
}
