import Foundation

@main
enum Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args[0].hasPrefix("-") { // no command (or Cocoa launch flags): run the menu bar app
            DynamicLightingApp.main()
        } else {
            exit(CLI.run(args))
        }
    }
}

/// Command line interface, handy for scripts, Shortcuts or Raycast. Applies to all devices found.
enum CLI {
    static func run(_ args: [String]) -> Int32 {
        let devices = LampArrayDiscovery().discover()
        do {
            switch args[0] {
            case "list":
                if devices.isEmpty { print("No Dynamic Lighting device found") }
                for d in devices {
                    let lamps = (try? d.lampCount()).map { "\($0) lamps" } ?? "lamp count unavailable"
                    print(String(format: "%@  [%04x:%04x, %@]", d.name, d.vendorID, d.productID, lamps))
                }
            case "color" where args.count == 4:
                let c = args[1...3].compactMap { UInt8($0) }
                guard c.count == 3 else { return usage() }
                try requireDevices(devices).forEach { try $0.setColor(red: c[0], green: c[1], blue: c[2]) }
            case "off":
                try requireDevices(devices).forEach { try $0.setColor(red: 0, green: 0, blue: 0) }
            case "builtin":
                try requireDevices(devices).forEach { try $0.releaseControl() }
            case "legion-effect" where args.count >= 2:
                guard let effect = LegionEffect.allCases.first(where: { slug($0.title) == args[1].lowercased() }) else { return usage() }
                guard let monitor = devices.first(where: \.isLegionPro34WD10), let ddc = LegionDDC() else {
                    throw Message("Lenovo Legion Pro 34WD-10 not found")
                }
                try monitor.releaseControl()
                if effect == .flashing { ddc.prepareFlashing() }
                ddc.set(.effect, effect.rawValue)
                ddc.set(.speed, effect.speedValue(seconds: args.count > 2 ? Double(args[2]) ?? 10 : 10))
                if args.count > 3, let b = Int(args[3]) { ddc.set(.brightness, b) }
            default:
                return usage()
            }
            return 0
        } catch {
            fputs("error: \(error)\n", stderr)
            return 1
        }
    }

    private struct Message: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    private static func requireDevices(_ devices: [LampArrayDevice]) throws -> [LampArrayDevice] {
        guard !devices.isEmpty else { throw Message("No Dynamic Lighting device found") }
        return devices
    }

    private static func slug(_ s: String) -> String { s.lowercased().replacingOccurrences(of: " ", with: "") }

    private static func usage() -> Int32 {
        let effects = LegionEffect.allCases.map { slug($0.title) }.joined(separator: "|")
        fputs("""
        usage: DynamicLighting list
               DynamicLighting color <R> <G> <B>
               DynamicLighting off
               DynamicLighting builtin
               DynamicLighting legion-effect <\(effects)> [seconds] [brightness]

        """, stderr)
        return 2
    }
}
