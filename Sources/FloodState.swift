import CoreGraphics
import QuartzCore

/// Nivel de inundación compartido por todas las pantallas, de 0 (seco) a 1 (pantalla llena).
///
/// Sube mientras no se toca el ratón ni el teclado y se vacía en cuanto hay actividad. Para saberlo
/// solo pregunta cuántos segundos han pasado desde el último evento de entrada: no lee qué se pulsa,
/// así que no necesita el permiso de Monitorización de entrada.
final class FloodState {
    var enabled = false {
        didSet { if !enabled { level = 0 } }
    }
    /// Segundos que tarda en llenarse la pantalla.
    var fillDuration: CGFloat = 60
    private(set) var level: CGFloat = 0
    /// Se llama cuando cambia el nivel (para amortiguar el sonido).
    var onChange: ((CGFloat) -> Void)?

    /// Segundos sin actividad antes de que empiece a subir el agua.
    private static let startDelay: CFTimeInterval = 3
    /// Segundos que tarda en vaciarse por completo.
    private static let drainDuration: CGFloat = 1.1
    private static let anyInput = CGEventType(rawValue: ~0)!

    private var lastTimestamp: CFTimeInterval = 0
    private var idleCheckedAt: CFTimeInterval = 0
    private var idleSeconds: CFTimeInterval = 0

    /// Avanza hasta `now`. Varias pantallas pueden llamarlo en el mismo fotograma: solo cuenta la primera.
    func advance(to now: CFTimeInterval) {
        guard now > lastTimestamp else { return }
        let dt = lastTimestamp == 0 ? 0 : CGFloat(min(now - lastTimestamp, 0.1))
        lastTimestamp = now
        guard enabled else { return }

        // Consultar el tiempo sin actividad diez veces por segundo es suficiente.
        if now - idleCheckedAt > 0.1 {
            idleCheckedAt = now
            idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput)
        }

        let old = level
        if idleSeconds >= Self.startDelay {
            level = min(1, level + dt / max(fillDuration, 1))
        } else {
            level = max(0, level - dt / Self.drainDuration)
        }
        if level != old { onChange?(level) }
    }

    func reset() {
        level = 0
        lastTimestamp = 0
        onChange?(0)
    }
}
