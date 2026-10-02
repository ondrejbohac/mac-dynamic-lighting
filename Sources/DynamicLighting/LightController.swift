import AppKit
import Foundation
import ServiceManagement

enum LightMode: String, CaseIterable, Identifiable {
    case color, builtIn, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .color: "Color"
        case .builtIn: "Built-in"
        case .off: "Off"
        }
    }
}

/// Built-in effects of the Lenovo Legion Pro 34WD-10. Raw values are what the monitor expects in
/// VCP feature 0x1D. The list matches what Lenovo's own app offers for this model, plus the
/// OSD's default Starry Sky.
enum LegionEffect: Int, CaseIterable, Identifiable {
    case breathing = 1, flashing = 2, marquee = 3, rainbowWave = 4, starrySky = 6
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .breathing: "Breathing"
        case .flashing: "Flashing"
        case .marquee: "Marquee"
        case .rainbowWave: "Rainbow Wave"
        case .starrySky: "Starry Sky"
        }
    }

    /// Lenovo's app sends the cycle length in seconds, except for Marquee and Rainbow Wave
    /// which only know 3 steps. Flashing and Starry Sky accept 0-2, where 0 turns the strip dark.
    func speedValue(seconds: Double) -> Int {
        switch self {
        case .marquee, .rainbowWave: seconds < 7 ? 0 : seconds < 15 ? 1 : 2
        case .flashing, .starrySky: seconds < 10 ? 1 : 2
        case .breathing: Int(seconds)
        }
    }
}

struct LightSettings: Equatable {
    var mode: LightMode = .color
    var hue: Double = 0
    var saturation: Double = 0
    var brightness: Double = 1
    var legionEffect: LegionEffect = .breathing
    var legionSeconds: Double = 10
    var legionBrightness: Double = 100

    var rgb: (UInt8, UInt8, UInt8) {
        let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        return (UInt8((c.redComponent * 255).rounded()), UInt8((c.greenComponent * 255).rounded()), UInt8((c.blueComponent * 255).rounded()))
    }
}

struct DeviceInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let isLegion: Bool
}

@MainActor
final class LightController: ObservableObject {
    @Published var settings: LightSettings { didSet { if settings != oldValue { save(); worker.submit(settings) } } }
    @Published private(set) var devices: [DeviceInfo] = []
    @Published private(set) var lastError: String?
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet { updateLoginItem() }
    }

    var hasLegion: Bool { devices.contains(where: \.isLegion) }

    private let worker = LightWorker()
    private var keepAlive: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        settings = Self.load()
        worker.onResult = { [weak self] devices, error in
            Task { @MainActor in
                self?.devices = devices
                self?.lastError = error
            }
        }
        observeSystemEvents()
        reapply()
    }

    /// Rescans devices and re-sends the current state, e.g. after wake or reconnect.
    func reapply() {
        worker.submit(settings, force: true)
    }

    private func observeSystemEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reapplyAfterSettling() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapplyAfterSettling() }
        })
        // Devices drop back to their own effects when they lose power or USB; a cheap periodic
        // refresh also picks up reconnects and newly plugged-in devices.
        keepAlive = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reapply() }
        }
    }

    private func reapplyAfterSettling() {
        for delay in [2.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.reapply() }
            }
        }
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Login item: \(error.localizedDescription)"
        }
    }

    // MARK: Persistence

    private static let defaults = UserDefaults.standard

    private static func load() -> LightSettings {
        var s = LightSettings()
        guard defaults.object(forKey: "mode") != nil else { return s }
        s.mode = LightMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .color
        s.hue = defaults.double(forKey: "hue")
        s.saturation = defaults.double(forKey: "saturation")
        s.brightness = defaults.double(forKey: "brightness")
        s.legionEffect = LegionEffect(rawValue: defaults.integer(forKey: "legionEffect")) ?? .breathing
        s.legionSeconds = defaults.double(forKey: "legionSeconds")
        s.legionBrightness = defaults.double(forKey: "legionBrightness")
        return s
    }

    private func save() {
        let d = Self.defaults
        d.set(settings.mode.rawValue, forKey: "mode")
        d.set(settings.hue, forKey: "hue")
        d.set(settings.saturation, forKey: "saturation")
        d.set(settings.brightness, forKey: "brightness")
        d.set(settings.legionEffect.rawValue, forKey: "legionEffect")
        d.set(settings.legionSeconds, forKey: "legionSeconds")
        d.set(settings.legionBrightness, forKey: "legionBrightness")
    }
}

/// Talks to the hardware off the main thread. Slider drags produce many updates; only the latest
/// pending state is applied, and DDC writes (slow, ~200 ms each) are skipped when nothing changed.
final class LightWorker: @unchecked Sendable {
    var onResult: (([DeviceInfo], String?) -> Void)?

    private let queue = DispatchQueue(label: "DynamicLighting.worker")
    private let lock = NSLock()
    private var pending: (LightSettings, Bool)?
    private var running = false

    private let discovery = LampArrayDiscovery()
    private var devices: [LampArrayDevice] = []
    private var ddc: LegionDDC?
    private var appliedEffect: (effect: Int, speed: Int, brightness: Int)?
    private var lastMode: LightMode?

    func submit(_ settings: LightSettings, force: Bool = false) {
        lock.lock()
        pending = (settings, force || (pending?.1 ?? false))
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let (settings, force) = pending else {
                running = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            apply(settings, force: force)
        }
    }

    private func apply(_ s: LightSettings, force: Bool) {
        if force || devices.isEmpty { rescan() }

        // Re-sending "built-in" to devices every 30 s is pointless; only do it on actual changes.
        let builtInRefresh = force && s.mode == .builtIn && lastMode == .builtIn
        lastMode = s.mode

        var errors: [String] = []
        if !builtInRefresh {
            for device in devices {
                do {
                    switch s.mode {
                    case .color:
                        let (r, g, b) = s.rgb
                        try device.setColor(red: r, green: g, blue: b)
                    case .off:
                        try device.setColor(red: 0, green: 0, blue: 0)
                    case .builtIn:
                        try device.releaseControl()
                    }
                } catch {
                    errors.append("\(device.name): \(error)")
                }
            }
        }

        if s.mode == .builtIn, devices.contains(where: \.isLegionPro34WD10) {
            do { try applyLegionEffect(s, force: force && !builtInRefresh) } catch { errors.append("\(error)") }
        } else {
            appliedEffect = nil
        }

        if !errors.isEmpty { rescan() } // a device probably went away; refresh the list for the UI
        let infos = devices.map { DeviceInfo(id: $0.id, name: $0.name, isLegion: $0.isLegionPro34WD10) }
        onResult?(infos, errors.first)
    }

    private func rescan() {
        let found = discovery.discover()
        // Keep existing objects (and their cached lamp counts) for devices that are still present.
        devices = found.map { new in devices.first(where: { $0.id == new.id }) ?? new }
    }

    private struct NoDisplay: Error, CustomStringConvertible {
        var description: String { "Legion monitor not reachable over DDC" }
    }

    private func applyLegionEffect(_ s: LightSettings, force: Bool) throws {
        if ddc == nil || force { ddc = LegionDDC() }
        guard let ddc else { throw NoDisplay() }
        let target = (effect: s.legionEffect.rawValue,
                      speed: s.legionEffect.speedValue(seconds: s.legionSeconds),
                      brightness: Int(s.legionBrightness))
        let prev = force ? nil : appliedEffect
        if prev?.effect != target.effect {
            if s.legionEffect == .flashing { ddc.prepareFlashing() }
            ddc.set(.effect, target.effect)
        }
        if prev?.effect != target.effect || prev?.speed != target.speed { ddc.set(.speed, target.speed) }
        if prev?.brightness != target.brightness { ddc.set(.brightness, target.brightness) }
        appliedEffect = target
    }
}
