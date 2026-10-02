import SwiftUI

struct DynamicLightingApp: App {
    @StateObject private var controller = LightController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller)
        } label: {
            Image(systemName: "light.strip.2")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct Preset: Identifiable {
    let name: String
    let hue: Double
    let saturation: Double
    var id: String { name }
    var color: Color { Color(hue: hue, saturation: saturation, brightness: 1) }

    static let all = [
        Preset(name: "White", hue: 0, saturation: 0),
        Preset(name: "Warm", hue: 0.08, saturation: 0.35),
        Preset(name: "Red", hue: 0, saturation: 1),
        Preset(name: "Orange", hue: 0.07, saturation: 1),
        Preset(name: "Green", hue: 0.33, saturation: 1),
        Preset(name: "Cyan", hue: 0.5, saturation: 1),
        Preset(name: "Blue", hue: 0.64, saturation: 1),
        Preset(name: "Purple", hue: 0.78, saturation: 1),
    ]
}

struct MenuView: View {
    @ObservedObject var controller: LightController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("", selection: $controller.settings.mode) {
                ForEach(LightMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch controller.settings.mode {
            case .color: colorSection
            case .builtIn: builtInSection
            case .off: EmptyView()
            }

            Divider()

            Toggle("Launch at login", isOn: $controller.launchAtLogin)
                .toggleStyle(.checkbox)

            HStack {
                Button("Rescan") { controller.reapply() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(controller.devices.isEmpty ? Color.secondary.opacity(0.5) : Color.green)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dynamic Lighting").font(.headline)
                if controller.devices.isEmpty {
                    Text("No Dynamic Lighting device found").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(controller.devices) { Text($0.name).font(.caption).foregroundStyle(.secondary) }
                }
                if let error = controller.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Preset.all) { preset in
                    Button {
                        controller.settings.hue = preset.hue
                        controller.settings.saturation = preset.saturation
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected(preset) ? 0.9 : 0.15), lineWidth: isSelected(preset) ? 2 : 1))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }

            GradientSlider(title: "Hue", value: $controller.settings.hue,
                           colors: stride(from: 0.0, through: 1.0, by: 1 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) })
            GradientSlider(title: "Saturation", value: $controller.settings.saturation,
                           colors: [.white, Color(hue: controller.settings.hue, saturation: 1, brightness: 1)])
            GradientSlider(title: "Brightness", value: $controller.settings.brightness,
                           colors: [.black, Color(hue: controller.settings.hue, saturation: controller.settings.saturation, brightness: 1)])
        }
    }

    @ViewBuilder
    private var builtInSection: some View {
        if controller.hasLegion {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Legion effect", selection: $controller.settings.legionEffect) {
                    ForEach(LegionEffect.allCases) { Text($0.title).tag($0) }
                }
                LabeledSlider(title: "Cycle", value: $controller.settings.legionSeconds, range: 1...20, step: 1, unit: "s")
                LabeledSlider(title: "Brightness", value: $controller.settings.legionBrightness, range: 0...100, step: 5, unit: "%")
            }
        }
        Text("Lighting runs on the device's own built-in effects.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func isSelected(_ p: Preset) -> Bool {
        abs(controller.settings.hue - p.hue) < 0.005 && abs(controller.settings.saturation - p.saturation) < 0.005
    }
}

private struct GradientSlider: View {
    let title: String
    @Binding var value: Double
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
                    Circle()
                        .fill(Color.white)
                        .shadow(radius: 1.5)
                        .frame(width: 16, height: 16)
                        .offset(x: CGFloat(value) * (geo.size.width - 16))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    value = min(max(Double((g.location.x - 8) / (geo.size.width - 16)), 0), 1)
                })
            }
            .frame(height: 16)
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value)) \(unit)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
