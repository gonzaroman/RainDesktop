import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var rain: RainController!
    private var model: ControlPanelModel!
    private let popover = NSPopover()
    private let updates = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let settings = SettingsStore.load()
        rain = RainController(settings: settings)
        model = ControlPanelModel(settings: settings) { [weak self] new in
            SettingsStore.save(new)
            self?.rain.settings = new
            self?.updates.automatic = new.checkUpdates
            self?.updateStatusIcon()
        }
        updates.automatic = settings.checkUpdates
        updates.onChange = { [weak self] _ in self?.updateStatusIcon() }

        popover.behavior = .transient
        popover.animates = true
        let panel = NSHostingController(rootView: ControlPanel(
            model: model,
            updates: updates,
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
            button.toolTip = L("RainDesktop — right-click to start or stop the rain")
        }
        updateStatusIcon()
        updates.start()

        if StudioMode.isActive {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                StudioMode.announceStatusItem(self?.statusItem.button)
            }
        }

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
        statusItem?.button?.image = Self.statusImage(symbol: symbol, badge: updates.availableRelease != nil)
    }

    /// Icono de la barra de menús; con `badge`, un puntito arriba a la derecha (hay versión nueva).
    /// Sigue siendo plantilla, así que cambia de color con la barra como el resto de iconos.
    private static func statusImage(symbol: String, badge: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "RainDesktop") else { return nil }
        guard badge else { return base }
        let size = NSSize(width: base.size.width + 3, height: base.size.height)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height))
            let d: CGFloat = 6
            let dot = NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)
            // Un hueco alrededor del punto para que se distinga de la nube.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L("RainDesktop — update available")
        return image
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
            // Que no se abra con el campo del grosor seleccionado.
            popover.contentViewController?.view.window?.makeFirstResponder(nil)
        }
    }

    private func showAbout() {
        popover.performClose(nil)
        NSApp.activate()
        let credits = NSAttributedString(
            string: L("Rain behind your windows. It only uses their outlines and needs no permissions."),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
