import AppKit
import ServiceManagement
import SwiftUI

/// Estado del panel. Cada cambio de ajustes se guarda y se aplica al momento.
final class ControlPanelModel: ObservableObject {
    @Published var settings: RainSettings {
        didSet {
            guard settings != oldValue else { return }
            onChange(settings)
        }
    }
    @Published private(set) var launchAtLogin = false

    private let onChange: (RainSettings) -> Void

    init(settings: RainSettings, onChange: @escaping (RainSettings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshLaunchAtLogin()
    }
}

/// Panel que se abre desde el icono de la barra de menús.
struct ControlPanel: View {
    @ObservedObject var model: ControlPanelModel
    var onAbout: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            SliderRow(title: "Intensidad", detail: Self.describeIntensity(model.settings.intensity),
                      symbol: "cloud.rain", value: $model.settings.intensity, range: 0...1)
            SliderRow(title: "Viento", detail: Self.describeWind(model.settings.wind),
                      symbol: "wind", value: $model.settings.wind, range: -1...1)
            SliderRow(title: "Rebote", detail: Self.describeBounce(model.settings.bounce),
                      symbol: "drop", value: $model.settings.bounce, range: 0...1)
            NumberRow(title: "Grosor de los hilos", symbol: "line.3.horizontal.decrease",
                      unit: "pt", value: $model.settings.streamWidth,
                      range: RainSettings.streamWidthRange, step: 0.5)

            Divider()

            ToggleRow(title: "Sonido de lluvia", isOn: $model.settings.sound)
            SliderRow(title: "Volumen", detail: "\(Int((model.settings.volume * 100).rounded())) %",
                      symbol: "speaker.wave.2", value: $model.settings.volume, range: 0...1)
                .disabled(!model.settings.sound)
                .opacity(model.settings.sound ? 1 : 0.45)

            Divider()

            ToggleRow(title: "Relámpagos y truenos", isOn: $model.settings.lightning)
            ToggleRow(title: "Chocar con las ventanas", isOn: $model.settings.collide)
            ToggleRow(title: "Rebotar también en los laterales",
                      caption: "Se nota cuando hay viento.",
                      isOn: $model.settings.sideCollide)
                .disabled(!model.settings.collide)
                .opacity(model.settings.collide ? 1 : 0.45)
            ToggleRow(title: "Abrir al iniciar sesión",
                      isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))

            Divider()

            HStack {
                Button("Acerca de RainDesktop", action: onAbout)
                    .buttonStyle(.borderless)
                Spacer()
                Button("Salir", action: onQuit)
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("RainDesktop").font(.headline)
                Text(model.settings.raining ? "Lloviendo" : "Sin lluvia")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Lluvia", isOn: $model.settings.raining)
                .toggleStyle(.switch)
                .labelsHidden()
                .keyboardShortcut("r")
        }
    }

    static func describeIntensity(_ v: Double) -> String {
        switch v {
        case ..<0.15: return "llovizna"
        case ..<0.35: return "ligera"
        case ..<0.55: return "moderada"
        case ..<0.75: return "fuerte"
        case ..<0.9: return "tormenta"
        default: return "diluvio"
        }
    }

    static func describeWind(_ v: Double) -> String {
        let a = abs(v)
        if a < 0.05 { return "calma" }
        let name = a < 0.45 ? "brisa" : "ventoso"
        return name + (v > 0 ? " →" : " ←")
    }

    static func describeBounce(_ v: Double) -> String {
        v < 0.34 ? "suave" : v < 0.67 ? "medio" : "fuerte"
    }
}

private struct SliderRow: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

/// Campo numérico con flechas: se puede escribir un valor o subirlo y bajarlo de `step` en `step`.
private struct NumberRow: View {
    let title: String
    let symbol: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 2
        return f
    }()

    private var clamped: Binding<Double> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.callout)
            Spacer()
            TextField("", value: clamped, formatter: Self.formatter)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .controlSize(.small)
            Text(unit).font(.callout).foregroundStyle(.secondary)
            Stepper("", value: clamped, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}
