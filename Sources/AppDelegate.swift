import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var rainController = RainController()

    var isRaining = false
    var intensity: CGFloat = 0.6
    var wind: CGFloat = 0.25
    var lightningEnabled = true
    var collideEnabled = true
    var reboundLife: CGFloat = 0.6

    var toggleItem: NSMenuItem!
    var intensityItems: [NSMenuItem] = []
    var windItems: [NSMenuItem] = []
    var lightningItem: NSMenuItem!
    var collideItem: NSMenuItem!
    var reboundLabel: NSTextField!
    var reboundSlider: NSSlider!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cloud.rain", accessibilityDescription: "Lluvia")
            button.action = #selector(toggleRain)
            button.target = self
        }

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Empezar a llover", action: #selector(toggleRain), keyEquivalent: "r")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        let intensityMenu = NSMenu()
        let levels: [(String, CGFloat)] = [("Ligera", 0.3), ("Normal", 0.6), ("Fuerte", 1.0)]
        for (name, value) in levels {
            let item = NSMenuItem(title: name, action: #selector(setIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = (value == intensity) ? .on : .off
            intensityMenu.addItem(item)
            intensityItems.append(item)
        }
        let intensityParent = NSMenuItem(title: "Intensidad", action: nil, keyEquivalent: "")
        intensityParent.submenu = intensityMenu
        menu.addItem(intensityParent)

        let windMenu = NSMenu()
        let winds: [(String, CGFloat)] = [("Calma", 0.0), ("Brisa", 0.25), ("Ventoso", 0.7)]
        for (name, value) in winds {
            let item = NSMenuItem(title: name, action: #selector(setWind(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = (value == wind) ? .on : .off
            windMenu.addItem(item)
            windItems.append(item)
        }
        let windParent = NSMenuItem(title: "Viento", action: nil, keyEquivalent: "")
        windParent.submenu = windMenu
        menu.addItem(windParent)

        lightningItem = NSMenuItem(title: "Relámpagos", action: #selector(toggleLightning), keyEquivalent: "")
        lightningItem.target = self
        lightningItem.state = .on
        menu.addItem(lightningItem)

        collideItem = NSMenuItem(title: "Chocar con ventanas", action: #selector(toggleCollide), keyEquivalent: "")
        collideItem.target = self
        collideItem.state = .on
        menu.addItem(collideItem)

        // Slider vida tras choque: 0.1s - 1.5s
        let reboundItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 48))
        reboundLabel = NSTextField(labelWithString: String(format: "Vida rebote: %.2fs", reboundLife))
        reboundLabel.frame = NSRect(x: 14, y: 26, width: 200, height: 16)
        reboundLabel.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(reboundLabel)
        reboundSlider = NSSlider(value: Double(reboundLife), minValue: 0.1, maxValue: 1.5, target: self, action: #selector(reboundChanged(_:)))
        reboundSlider.frame = NSRect(x: 14, y: 4, width: 192, height: 20)
        reboundSlider.controlSize = .small
        container.addSubview(reboundSlider)
        reboundItem.view = container
        menu.addItem(reboundItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Salir de RainDesktop 1.1", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func toggleRain() {
        isRaining.toggle()
        if isRaining {
            rainController.start(intensity: intensity, wind: wind, lightning: lightningEnabled)
            rainController.setCollide(collideEnabled)
            rainController.setRebound(reboundLife)
            toggleItem.title = "Dejar de llover"
            statusItem.button?.image = NSImage(systemSymbolName: "cloud.rain.fill", accessibilityDescription: "Lloviendo")
        } else {
            rainController.stop()
            toggleItem.title = "Empezar a llover"
            statusItem.button?.image = NSImage(systemSymbolName: "cloud.rain", accessibilityDescription: "Lluvia")
        }
    }

    @objc func setIntensity(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? CGFloat {
            intensity = value
            for item in intensityItems {
                item.state = (item == sender) ? .on : .off
            }
            rainController.update(intensity: intensity, wind: wind, lightning: lightningEnabled)
        }
    }

    @objc func setWind(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? CGFloat {
            wind = value
            for item in windItems {
                item.state = (item == sender) ? .on : .off
            }
            rainController.update(intensity: intensity, wind: wind, lightning: lightningEnabled)
        }
    }

    @objc func toggleLightning() {
        lightningEnabled.toggle()
        lightningItem.state = lightningEnabled ? .on : .off
        rainController.update(intensity: intensity, wind: wind, lightning: lightningEnabled)
    }

    @objc func toggleCollide() {
        collideEnabled.toggle()
        collideItem.state = collideEnabled ? .on : .off
        rainController.setCollide(collideEnabled)
    }

    @objc func reboundChanged(_ sender: NSSlider) {
        reboundLife = CGFloat(sender.doubleValue)
        reboundLabel.stringValue = String(format: "Vida rebote: %.2fs", reboundLife)
        rainController.setRebound(reboundLife)
    }

    @objc func quitApp() {
        rainController.stop()
        NSApp.terminate(nil)
    }
}
