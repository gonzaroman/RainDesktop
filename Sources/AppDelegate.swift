import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settings = SettingsStore.load()
    private var rain: RainController!

    private var toggleItem: NSMenuItem!
    private var intensityItems: [NSMenuItem] = []
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

        let intensityMenu = NSMenu()
        for (name, value) in [("Ligera", 0.3), ("Normal", 0.6), ("Fuerte", 1.0)] {
            let item = addItem(to: intensityMenu, name, #selector(setIntensity(_:)))
            item.representedObject = value
            intensityItems.append(item)
        }
        let intensityParent = NSMenuItem(title: "Intensidad", action: nil, keyEquivalent: "")
        intensityParent.submenu = intensityMenu
        menu.addItem(intensityParent)

        let (windItem, windText) = sliderItem(value: settings.wind, range: -1...1, action: #selector(windChanged(_:)))
        windLabel = windText
        menu.addItem(windItem)

        let (bounceItem, bounceText) = sliderItem(value: settings.bounce, range: 0...1, action: #selector(bounceChanged(_:)))
        bounceLabel = bounceText
        menu.addItem(bounceItem)

        menu.addItem(.separator())
        lightningItem = addItem(to: menu, "Relámpagos", #selector(toggleLightning))
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
    private func sliderItem(value: Double, range: ClosedRange<Double>, action: Selector) -> (NSMenuItem, NSTextField) {
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
        return (item, label)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshUI()
    }

    private func refreshUI() {
        toggleItem.title = settings.raining ? "Dejar de llover" : "Empezar a llover"
        let symbol = settings.raining ? "cloud.rain.fill" : "cloud.rain"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RainDesktop")
        for item in intensityItems {
            let value = item.representedObject as? Double ?? -1
            item.state = abs(value - settings.intensity) < 0.01 ? .on : .off
        }
        windLabel.stringValue = "Viento: " + Self.describeWind(settings.wind)
        bounceLabel.stringValue = "Rebote: " + Self.describeBounce(settings.bounce)
        lightningItem.state = settings.lightning ? .on : .off
        collideItem.state = settings.collide ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
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

    @objc private func setIntensity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        update { $0.intensity = value }
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
