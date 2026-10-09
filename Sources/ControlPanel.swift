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
    @ObservedObject var updates: UpdateChecker
    var onAbout: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let release = updates.availableRelease {
                UpdateBanner(release: release)
            }
            Divider()

            SliderRow(title: L("Intensity"), detail: Self.describeIntensity(model.settings.intensity),
                      symbol: "cloud.rain", value: $model.settings.intensity, range: 0...1)
            SliderRow(title: L("Wind"), detail: Self.describeWind(model.settings.wind),
                      symbol: "wind", value: $model.settings.wind, range: -1...1)
            SliderRow(title: L("Bounce"), detail: Self.describeBounce(model.settings.bounce),
                      symbol: "drop", value: $model.settings.bounce, range: 0...1)
            NumberRow(title: L("Stream width"), symbol: "line.3.horizontal.decrease",
                      unit: "pt", value: $model.settings.streamWidth,
                      range: RainSettings.streamWidthRange, step: 0.5)

            Divider()

            ToggleRow(title: L("Rain sound"), isOn: $model.settings.sound)
            SliderRow(title: L("Volume"), detail: "\(Int((model.settings.volume * 100).rounded())) %",
                      symbol: "speaker.wave.2", value: $model.settings.volume, range: 0...1)
                .disabled(!model.settings.sound)
                .opacity(model.settings.sound ? 1 : 0.45)

            Divider()

            ToggleRow(title: L("Lightning and thunder"), isOn: $model.settings.lightning)
            ToggleRow(title: L("Collide with windows"), isOn: $model.settings.collide)
            ToggleRow(title: L("Also bounce off the sides"),
                      caption: L("Noticeable when it's windy."),
                      isOn: $model.settings.sideCollide)
                .disabled(!model.settings.collide)
                .opacity(model.settings.collide ? 1 : 0.45)
            ToggleRow(title: L("Flood when you're away"),
                      caption: L("Touch the mouse or keyboard and the water drains."),
                      isOn: $model.settings.flood)
            SliderRow(title: L("Fills in"), detail: Self.describeMinutes(model.settings.floodMinutes),
                      symbol: "water.waves", value: $model.settings.floodMinutes,
                      range: RainSettings.floodMinutesRange)
                .disabled(!model.settings.flood)
                .opacity(model.settings.flood ? 1 : 0.45)
            ToggleRow(title: L("Fish in the flood"), isOn: $model.settings.fish)
                .disabled(!model.settings.flood)
                .opacity(model.settings.flood ? 1 : 0.45)
            ToggleRow(title: L("People with umbrellas"), caption: L("They walk on top of your windows."),
                      isOn: $model.settings.walkers)
            ToggleRow(title: L("Open at login"),
                      isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            ToggleRow(title: L("Check for updates"), caption: L("Once a day, on GitHub."),
                      isOn: $model.settings.checkUpdates)
            HStack {
                Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Check now")) { updates.check() }
                    .controlSize(.small)
                    .disabled(updates.state == .checking)
            }

            Divider()

            HStack {
                Button(L("About RainDesktop"), action: onAbout)
                    .buttonStyle(.borderless)
                Spacer()
                Button(L("Quit"), action: onQuit)
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var updateStatus: String {
        let current = updates.currentVersion
        switch updates.state {
        case .idle: return String(format: L("Version %@"), current)
        case .checking: return L("Checking…")
        case .upToDate: return String(format: L("You're up to date (%@)"), current)
        case .available(let release): return String(format: L("Version %@ available"), release.version)
        case .failed: return L("Couldn't check for updates")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("RainDesktop").font(.headline)
                Text(model.settings.raining ? L("Raining") : L("Not raining"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(L("Rain"), isOn: $model.settings.raining)
                .toggleStyle(.switch)
                .labelsHidden()
                .keyboardShortcut("r")
        }
    }

    static func describeIntensity(_ v: Double) -> String {
        switch v {
        case ..<0.15: return L("drizzle")
        case ..<0.35: return L("light")
        case ..<0.55: return L("moderate")
        case ..<0.75: return L("heavy")
        case ..<0.9: return L("storm")
        default: return L("downpour")
        }
    }

    static func describeWind(_ v: Double) -> String {
        let a = abs(v)
        if a < 0.05 { return L("calm") }
        let name = a < 0.45 ? L("breeze") : L("windy")
        return name + (v > 0 ? " →" : " ←")
    }

    static func describeMinutes(_ minutes: Double) -> String {
        let seconds = Int((minutes * 60 / 5).rounded()) * 5
        if seconds < 60 { return "\(seconds) s" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m) min \(s) s"
    }

    static func describeBounce(_ v: Double) -> String {
        v < 0.34 ? L("soft") : v < 0.67 ? L("medium") : L("strong")
    }
}

/// Aviso de versión nueva, arriba del panel.
private struct UpdateBanner: View {
    let release: UpdateChecker.Release

    /// Primera línea con texto de las notas de la versión (admite negritas y enlaces de Markdown).
    private var summary: AttributedString? {
        let line = release.notes.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
        guard let line else { return nil }
        return try? AttributedString(markdown: line)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: L("Version %@ available"), release.version))
                    .font(.callout.weight(.semibold))
                if let summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(L("Download")) { NSWorkspace.shared.open(release.url) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.14)))
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
