import AppKit

class RainController {
    private var windows: [RainWindow] = []
    private let provider = WindowListProvider()
    private var lastIntensity: CGFloat = 0.6
    private var lastWind: CGFloat = 0.25
    private var lastLightning = true
    private var lastRebound: CGFloat = 0.6
    var collideEnabled = true

    func start(intensity: CGFloat, wind: CGFloat, lightning: Bool) {
        lastIntensity = intensity
        lastWind = wind
        lastLightning = lightning
        if windows.isEmpty {
            createWindows()
        }
        applyToViews()
        for window in windows {
            window.orderFrontRegardless()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        provider.onUpdate = { [weak self] rects in
            self?.distribute(rects: rects)
        }
        provider.start()
    }

    func stop() {
        provider.stop()
        for window in windows {
            window.orderOut(nil)
        }
        // Seguridad: cerrar cualquier RainWindow fugada (p. ej. de un screensChanged antiguo)
        for w in NSApp.windows where w is RainWindow && !windows.contains(where: { $0 === w }) {
            w.orderOut(nil)
            w.close()
        }
        NotificationCenter.default.removeObserver(self)
    }

    func update(intensity: CGFloat, wind: CGFloat, lightning: Bool) {
        lastIntensity = intensity
        lastWind = wind
        lastLightning = lightning
        applyToViews()
    }

    func setCollide(_ enabled: Bool) {
        collideEnabled = enabled
        applyToViews()
    }

    func setRebound(_ life: CGFloat) {
        lastRebound = life
        applyToViews()
    }

    private func applyToViews() {
        for window in windows {
            if let view = window.contentView as? RainView {
                view.intensity = lastIntensity
                view.wind = lastWind
                view.lightningEnabled = lastLightning
                view.collideEnabled = collideEnabled
                view.reboundLife = lastRebound
            }
        }
    }

    private func distribute(rects: [CGRect]) {
        for window in windows {
            guard let screen = window.screen ?? NSScreen.main else { continue }
            let origin = screen.frame.origin
            var local: [CGRect] = []
            for r in rects {
                // Global Cocoa -> coords locales de esta pantalla
                let lr = CGRect(x: r.minX - origin.x, y: r.minY - origin.y, width: r.width, height: r.height)
                // Solo si intersecta con la vista
                if lr.maxX > 0 && lr.minX < screen.frame.width && lr.maxY > 0 && lr.minY < screen.frame.height {
                    local.append(lr)
                }
            }
            (window.contentView as? RainView)?.obstacles = local
        }
    }

    @objc private func screensChanged() {
        let wasVisible = windows.first?.isVisible ?? false
        // Cerrar las antiguas antes de soltarlas: si no, quedan fugadas en pantalla
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        // Y por si acaso, barrer cualquier otra RainWindow viva de NSApp
        for w in NSApp.windows where w is RainWindow {
            w.orderOut(nil)
            w.close()
        }
        createWindows()
        applyToViews()
        if wasVisible {
            for window in windows {
                window.orderFrontRegardless()
            }
        }
    }

    private func createWindows() {
        windows = NSScreen.screens.map { screen in
            RainWindow(screen: screen)
        }
        applyToViews()
    }
}
