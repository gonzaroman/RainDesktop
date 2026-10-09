import AppKit

/// Modo estudio, para hacer las capturas del README con `Tools/Studio`.
///
/// `--studio-pid <pid>`: la lluvia solo tiene en cuenta las ventanas de ese proceso (el escritorio
/// ficticio del estudio) y los ajustes no se guardan, así que los del usuario quedan intactos.
/// Los ajustes de cada escena se pasan como argumentos, p. ej. `-intensity 0.7 -flood 1`.
enum StudioMode {
    static let pid: pid_t? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--studio-pid"), i + 1 < args.count else { return nil }
        return pid_t(args[i + 1])
    }()

    static var isActive: Bool { pid != nil }

    /// Avisa al estudio de dónde está el icono de la barra de menús, para que dibuje el suyo encima.
    static let statusItemNotification = Notification.Name("com.gonzalo.raindesktop.studio.statusItem")

    static func announceStatusItem(_ button: NSView?) {
        guard isActive, let button, let window = button.window else { return }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        DistributedNotificationCenter.default().postNotificationName(
            statusItemNotification, object: "\(frame.midX)", userInfo: nil, deliverImmediately: true)
    }
}
