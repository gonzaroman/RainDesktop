import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settings = SettingsStore.load()
    private var rain: RainController!

    private var toggleItem: NSMenuItem!
    private var intensityLabel: NSTextField!
    private var soundItem: NSMenuItem!
    private var volumeLabel: NSTextField!
    private var volumeSlider: NSSlider!
    private var lightningItem: NSMenuItem!
    private var collideItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var windLabel: NSTextField!
    private var bounceLabel: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = buildMenu()
        rain = RainController(settings: settings)
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SettingsStore.save(settings)
    }

    // MARK: - Menú

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        toggleItem = addItem(to: menu, "", #selector(toggleRain), key: "r")
        menu.addItem(.separator())

        let (intensityItem, intensityText, _) = sliderItem(value: settings.intensity, range: 0...1,
                                                           action: #selector(intensityChanged(_:)))
        intensityLabel = intensityText
        menu.addItem(intensityItem)

        let (windItem, windText, _) = sliderItem(value: settings.wind, range: -1...1, action: #selector(windChanged(_:)))
        windLabel = windText
        menu.addItem(windItem)

        let (bounceItem, bounceText, _) = sliderItem(value: settings.bounce, range: 0...1, action: #selector(bounceChanged(_:)))
        bounceLabel = bounceText
        menu.addItem(bounceItem)

        menu.addItem(.separator())
        soundItem = addItem(to: menu, "Sonido de lluvia", #selector(toggleSound))
        let (volumeItem, volumeText, slider) = sliderItem(value: settings.volume, range: 0...1,
                                                          action: #selector(volumeChanged(_:)))
        volumeLabel = volumeText
        volumeSlider = slider
        menu.addItem(volumeItem)

        menu.addItem(.separator())
        lightningItem = addItem(to: menu, "Relámpagos y truenos", #selector(toggleLightning))
        collideItem = addItem(to: menu, "Chocar con las ventanas", #selector(toggleCollide))
        menu.addItem(.separator())
        loginItem = addItem(to: menu, "Abrir al iniciar sesión", #selector(toggleLaunchAtLogin))
        addItem(to: menu, "Acerca de RainDesktop", #selector(showAbout))
        menu.addItem(.separator())
        addItem(to: menu, "Salir de RainDesktop", #selector(quit), key: "q")
        return menu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    /// Elemento de menú con una etiqueta encima de un deslizador.
    private func sliderItem(value: Double, range: ClosedRange<Double>,
                            action: Selector) -> (NSMenuItem, NSTextField, NSSlider) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 46))
        let label = NSTextField(labelWithString: "")
        label.font = .menuFont(ofSize: 0)
        label.frame = NSRect(x: 22, y: 24, width: 204, height: 17)
        container.addSubview(label)

        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: self, action: action)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.frame = NSRect(x: 22, y: 4, width: 204, height: 20)
        container.addSubview(slider)

        let item = NSMenuItem()
        item.view = container
        return (item, label, slider)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshUI()
    }

    private func refreshUI() {
        toggleItem.title = settings.raining ? "Dejar de llover" : "Empezar a llover"
        let symbol = settings.raining ? "cloud.rain.fill" : "cloud.rain"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RainDesktop")
        intensityLabel.stringValue = "Intensidad: " + Self.describeIntensity(settings.intensity)
        soundItem.state = settings.sound ? .on : .off
        volumeLabel.stringValue = "Volumen: \(Int((settings.volume * 100).rounded())) %"
        volumeSlider.isEnabled = settings.sound
        volumeLabel.textColor = settings.sound ? .labelColor : .disabledControlTextColor
        windLabel.stringValue = "Viento: " + Self.describeWind(settings.wind)
        bounceLabel.stringValue = "Rebote: " + Self.describeBounce(settings.bounce)
        lightningItem.state = settings.lightning ? .on : .off
        collideItem.state = settings.collide ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private static func describeIntensity(_ v: Double) -> String {
        switch v {
        case ..<0.15: return "llovizna"
        case ..<0.35: return "ligera"
        case ..<0.55: return "moderada"
        case ..<0.75: return "fuerte"
        case ..<0.9: return "tormenta"
        default: return "diluvio"
        }
    }

    private static func describeWind(_ v: Double) -> String {
        let a = abs(v)
        if a < 0.08 { return "calma" }
        let name = a < 0.45 ? "brisa" : "ventoso"
        return name + (v > 0 ? " →" : " ←")
    }

    private static func describeBounce(_ v: Double) -> String {
        v < 0.34 ? "suave" : v < 0.67 ? "medio" : "fuerte"
    }

    // MARK: - Acciones

    private func update(_ change: (inout RainSettings) -> Void) {
        change(&settings)
        SettingsStore.save(settings)
        rain.settings = settings
        refreshUI()
    }

    @objc private func toggleRain() {
        update { $0.raining.toggle() }
    }

    @objc private func intensityChanged(_ sender: NSSlider) {
        update { $0.intensity = sender.doubleValue }
    }

    @objc private func toggleSound() {
        update { $0.sound.toggle() }
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        update { $0.volume = sender.doubleValue }
    }

    @objc private func windChanged(_ sender: NSSlider) {
        // Imán suave en el centro para poder volver a «calma».
        let value = abs(sender.doubleValue) < 0.05 ? 0 : sender.doubleValue
        update { $0.wind = value }
    }

    @objc private func bounceChanged(_ sender: NSSlider) {
        update { $0.bounce = sender.doubleValue }
    }

    @objc private func toggleLightning() {
        update { $0.lightning.toggle() }
    }

    @objc private func toggleCollide() {
        update { $0.collide.toggle() }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshUI()
    }

    @objc private func showAbout() {
        NSApp.activate()
        let credits = NSAttributedString(
            string: "Lluvia detrás de tus ventanas. Solo usa su contorno: sin permisos y sin red.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
