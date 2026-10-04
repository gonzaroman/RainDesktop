import AppKit
import CoreGraphics

/// Una ventana de otra app tal como la ve la lluvia: solo su identificador y su contorno.
struct TrackedWindow: Equatable {
    let id: CGWindowID
    /// Coordenadas Cocoa globales (origen abajo-izquierda de la pantalla principal).
    let frame: CGRect
}

/// Sigue la geometría de las ventanas visibles con `CGWindowListCopyWindowInfo`.
///
/// Solo lee número, contorno, capa, alfa y PID de cada ventana: nunca títulos ni nombres de apps,
/// así que no necesita permiso de Grabación de pantalla ni de Accesibilidad. La lista llega ordenada
/// de delante hacia atrás, y ese orden es el que usa la lluvia para saber qué tapa a qué.
final class WindowTracker {
    /// Se llama en el hilo principal cada vez que cambia la lista (ordenada de delante a atrás).
    var onUpdate: (([TrackedWindow]) -> Void)?

    private static let idleInterval: TimeInterval = 0.1
    private static let activeInterval: TimeInterval = 1.0 / 60.0
    /// Tras detectar un cambio se consulta rápido un rato, para que el agua siga a una ventana arrastrada.
    private static let activeDuration: TimeInterval = 0.5
    private static let maxWindows = 32

    private var timer: Timer?
    private var interval: TimeInterval = 0
    private var fastUntil: TimeInterval = 0
    private var windows: [TrackedWindow] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func start() {
        stop()
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        interval = 0
        windows = []
    }

    /// Fuerza una consulta inmediata (p. ej. al cambiar de Space).
    func refresh() {
        guard timer != nil else { return }
        poll()
    }

    private func poll() {
        let current = Self.snapshot(excludingPID: ownPID)
        let now = ProcessInfo.processInfo.systemUptime
        if current != windows {
            windows = current
            fastUntil = now + Self.activeDuration
            onUpdate?(current)
        }
        schedule(now < fastUntil ? Self.activeInterval : Self.idleInterval)
    }

    private func schedule(_ newInterval: TimeInterval) {
        guard timer == nil || newInterval != interval else { return }
        timer?.invalidate()
        interval = newInterval
        let t = Timer(timeInterval: newInterval, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = newInterval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private static func snapshot(excludingPID pid: pid_t) -> [TrackedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        // Quartz tiene el origen arriba-izquierda de la pantalla principal (la de la barra de menús);
        // Cocoa, abajo-izquierda de esa misma pantalla.
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height

        var result: [TrackedWindow] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.1,
                  let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner != pid,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let q = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  q.width >= 60, q.height >= 40 else { continue }

            let frame = CGRect(x: q.minX, y: primaryHeight - q.maxY, width: q.width, height: q.height)
            result.append(TrackedWindow(id: number, frame: frame))
            if result.count >= maxWindows { break }
        }
        return result
    }
}
