import AppKit

/// Crea una `RainWindow` por pantalla, reparte las ventanas a cada una y arranca o para la lluvia
/// según los ajustes.
final class RainController {
    var settings: RainSettings {
        didSet { apply() }
    }

    private var windows: [RainWindow] = []
    private let tracker = WindowTracker()
    private let sound = RainSound()
    private let flood = FloodState()
    private var tracked: [TrackedWindow] = []
    private var running = false
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(settings: RainSettings) {
        self.settings = settings
        flood.onChange = { [weak self] level in self?.sound.muffle = Double(level) }
        tracker.onUpdate = { [weak self] list in
            self?.tracked = list
            self?.distribute()
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.rebuildWindows()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.tracker.refresh()
        }
        observe(NotificationCenter.default, Notification.Name.NSProcessInfoPowerStateDidChange) { [weak self] in
            self?.restartAnimation()
        }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in
            self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self?.apply()
        }
        apply()
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        observers.append((center, token))
    }

    private func apply() {
        if settings.raining && !running {
            start()
        } else if !settings.raining && running {
            stop()
        }
        configureViews()
        configureSound()
    }

    private func configureSound() {
        sound.intensity = settings.intensity
        sound.volume = settings.volume
        if running && settings.sound {
            sound.play()
        } else {
            sound.stop()
        }
    }

    private func configureViews() {
        // Con «Reducir movimiento» activado no hay relámpagos.
        let lightning = settings.lightning && !reduceMotion
        flood.enabled = settings.flood
        flood.fillDuration = CGFloat(settings.floodMinutes * 60)
        for w in windows {
            w.rainView.configure(with: settings, lightning: lightning)
        }
    }

    private func start() {
        running = true
        if windows.isEmpty { createWindows() }
        configureViews()
        show()
        tracker.start()
    }

    private func stop() {
        running = false
        flood.reset()
        tracker.stop()
        tracked = []
        for w in windows {
            w.rainView.stopAnimating()
            w.rainView.setObstacles([])
            w.orderOut(nil)
        }
    }

    private func show() {
        for w in windows {
            w.orderFrontRegardless()
            w.rainView.startAnimating()
        }
    }

    /// Vuelve a crear el display link de cada vista (p. ej. al cambiar el modo de bajo consumo).
    private func restartAnimation() {
        guard running else { return }
        for w in windows {
            w.rainView.stopAnimating()
            w.rainView.startAnimating()
        }
    }

    private func createWindows() {
        windows = NSScreen.screens.map { screen in
            let window = RainWindow(screen: screen)
            window.rainView.flood = flood
            window.rainView.onLightning = { [weak self] in self?.sound.thunder() }
            return window
        }
    }

    /// Al conectar o desconectar pantallas se cierran todas las ventanas de lluvia y se crean de nuevo.
    private func rebuildWindows() {
        for w in windows {
            w.rainView.stopAnimating()
            w.orderOut(nil)
            w.close()
        }
        windows = []
        guard running else { return }
        createWindows()
        configureViews()
        show()
        distribute()
    }

    private func distribute() {
        for w in windows {
            let screen = w.screenFrame
            let local = tracked.compactMap { t -> Obstacle? in
                guard t.frame.intersects(screen) else { return nil }
                return Obstacle(id: t.id, frame: t.frame.offsetBy(dx: -screen.minX, dy: -screen.minY))
            }
            w.rainView.setObstacles(local)
        }
    }
}
