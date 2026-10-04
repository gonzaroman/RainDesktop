import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var rain: RainController!
    private var model: ControlPanelModel!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let settings = SettingsStore.load()
        rain = RainController(settings: settings)
        model = ControlPanelModel(settings: settings) { [weak self] new in
            SettingsStore.save(new)
            self?.rain.settings = new
            self?.updateStatusIcon()
        }

        popover.behavior = .transient
        popover.animates = true
        let panel = NSHostingController(rootView: ControlPanel(
            model: model,
            onAbout: { [weak self] in self?.showAbout() },
            onQuit: { NSApp.terminate(nil) }
        ))
        // El panel toma el tamaño de su contenido; si no, se coloca con 320×320 y luego crece hacia arriba.
        panel.sizingOptions = [.preferredContentSize]
        popover.contentViewController = panel

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "RainDesktop — clic derecho para empezar o parar la lluvia"
        }
        updateStatusIcon()

        // Para desarrollo: `open RainDesktop.app --args --show-panel` abre el panel al arrancar.
        if CommandLine.arguments.contains("--show-panel"), let button = statusItem.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.statusItemClicked(button) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SettingsStore.save(model.settings)
    }

    private func updateStatusIcon() {
        let symbol = model.settings.raining ? "cloud.rain.fill" : "cloud.rain"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RainDesktop")
    }

    /// Clic: abre o cierra el panel. Clic derecho (o ⌃clic): empieza o para la lluvia directamente.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            model.settings.raining.toggle()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refreshLaunchAtLogin()
            NSApp.activate()
            // El panel se abre por debajo del icono (el botón puede tener coordenadas invertidas).
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: sender.isFlipped ? .maxY : .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showAbout() {
        popover.performClose(nil)
        NSApp.activate()
        let credits = NSAttributedString(
            string: "Lluvia detrás de tus ventanas. Solo usa su contorno: sin permisos y sin red.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
