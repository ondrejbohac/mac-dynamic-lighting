import Foundation
import IOKit

// Private Apple Silicon API for raw I2C access to external displays (same one m1ddc and BetterDisplay use).
private typealias IOAVService = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?
@_silgen_name("IOAVServiceCopyEDID")
private func IOAVServiceCopyEDID(_ service: IOAVService, _ edid: UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn
@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: IOAVService, _ chip: UInt32, _ offset: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: IOAVService, _ chip: UInt32, _ offset: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

/// DDC/CI access to the Legion Pro 34WD-10. The monitor's built-in lighting effects live behind
/// Lenovo's indexed VCP pair: write the feature index to 0xF8, then the value to 0xF7.
final class LegionDDC {
    enum Feature: UInt16 {
        case effect = 0x1D
        case red = 0x11D
        case green = 0x21D
        case blue = 0x31D
        case colorMode = 0x41D // 0 default, 1 specified, 2 random
        case speed = 0x51D
        case brightness = 0x61D
    }

    private let service: IOAVService

    /// Finds the external display whose EDID names the Legion Pro 34WD-10.
    /// Falls back to the only external display when EDID cannot be read.
    init?() {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var externals: [(IOAVService, Data?)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            guard location == "External", let av = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            var edid: Unmanaged<CFData>?
            let data = IOAVServiceCopyEDID(av, &edid) == kIOReturnSuccess ? edid?.takeRetainedValue() as Data? : nil
            externals.append((av, data))
        }

        let marker = Data("Pro 34WD-10".utf8)
        if let match = externals.first(where: { $0.1?.range(of: marker) != nil }) {
            service = match.0
        } else if externals.count == 1, externals[0].1 == nil {
            service = externals[0].0
        } else {
            return nil
        }
    }

    /// Flashing stays dark unless the effect color has been initialised; this is the sequence
    /// found to bring it back (random colors, full-scale RGB, then re-selecting the effect).
    func prepareFlashing() {
        set(.colorMode, 2)
        for channel in [Feature.red, .green, .blue] { set(channel, 0xFF00) }
        set(.effect, 1)
    }

    func set(_ feature: Feature, _ value: Int) {
        setVCP(0xF8, Int(feature.rawValue))
        usleep(60_000)
        setVCP(0xF7, value)
        usleep(100_000)
    }

    private func setVCP(_ code: UInt8, _ value: Int) {
        var packet: [UInt8] = [0x84, 0x03, code, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        packet.append(packet.reduce(0x6E ^ 0x51) { $0 ^ $1 })
        // Sent twice: single DDC writes are occasionally dropped, and these writes are idempotent.
        for _ in 0..<2 {
            _ = IOAVServiceWriteI2C(service, 0x37, 0x51, &packet, UInt32(packet.count))
            usleep(10_000)
        }
    }
}
