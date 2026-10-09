import CoreGraphics
import simd

/// Junta las piezas de un personaje y las pinta con borde negro: primero todas las piezas en negro y
/// un poco más gruesas, luego el relleno claro encima, para que el borde solo asome por fuera.
///
/// Las piezas se dan en coordenadas del personaje: pies en el origen, mirando hacia +x y con +y hacia
/// arriba. `place` las coloca en la pantalla, las da la vuelta si mira a la izquierda y las gira
/// alrededor de `pivot` (volteretas).
struct FigureBrush {
    enum Style {
        /// Con borde negro.
        case outlined
        /// Solo en negro, encima del relleno (corbata, gafas, ojos).
        case ink
        /// Solo en claro y sin borde (fogonazos).
        case glow
    }

    private struct Part {
        var kind: RainRenderer.Kind
        var a, b: CGPoint
        var width: CGFloat
        var flags: UInt32
        var style: Style
    }

    /// Grosor del borde negro, en puntos.
    static let outline: CGFloat = 1.0
    /// Tamaño de todos los personajes respecto al diseño original.
    static let figureScale: CGFloat = 1.2

    private var parts: [Part] = []
    private var base = CGPoint.zero
    private var facing: CGFloat = 1
    private var scale: CGFloat = 1
    private var angle: CGFloat = 0
    private var pivot = CGPoint.zero

    /// Coloca las piezas siguientes: pies en `at`, mirando a `facing` (1 o -1), girado `angle`
    /// radianes (positivo, hacia atrás) alrededor de `pivot`, en coordenadas del personaje.
    mutating func place(at: CGPoint, facing: CGFloat = 1, scale: CGFloat = 1, angle: CGFloat = 0,
                        pivot: CGPoint = .zero) {
        base = at
        self.facing = facing
        self.scale = scale
        self.angle = angle
        self.pivot = pivot
    }

    /// Punto del personaje en coordenadas de la pantalla.
    func world(_ p: CGPoint) -> CGPoint {
        let q = CGPoint(x: p.x * facing * scale, y: p.y * scale)
        let o = CGPoint(x: pivot.x * facing * scale, y: pivot.y * scale)
        let c = cos(angle * facing), s = sin(angle * facing)
        let dx = q.x - o.x, dy = q.y - o.y
        return CGPoint(x: base.x + o.x + dx * c - dy * s, y: base.y + o.y + dx * s + dy * c)
    }

    mutating func segment(_ a: CGPoint, _ b: CGPoint, width: CGFloat, style: Style = .outlined) {
        parts.append(Part(kind: .segment, a: world(a), b: world(b), width: width * scale, flags: 0, style: style))
    }

    /// Círculo o elipse; no gira con el personaje, así que mejor para piezas redondas.
    mutating func ellipse(_ c: CGPoint, _ r: CGPoint, style: Style = .outlined) {
        parts.append(Part(kind: .ellipse, a: world(c), b: CGPoint(x: r.x * scale, y: r.y * scale),
                          width: 0, flags: 0, style: style))
    }

    /// Las mismas piezas, pero en coordenadas de la pantalla (no giran con el personaje).
    mutating func worldSegment(_ a: CGPoint, _ b: CGPoint, width: CGFloat, style: Style = .outlined) {
        parts.append(Part(kind: .segment, a: a, b: b, width: width, flags: 0, style: style))
    }

    mutating func worldEllipse(_ c: CGPoint, _ r: CGPoint, style: Style = .outlined) {
        parts.append(Part(kind: .ellipse, a: c, b: r, width: 0, flags: 0, style: style))
    }

    /// Media elipse, en coordenadas de la pantalla: la de arriba (paraguas) o, con `flipped`, la de abajo
    /// (casco de una lancha).
    mutating func worldDome(_ c: CGPoint, _ r: CGPoint, flipped: Bool = false) {
        parts.append(Part(kind: .dome, a: c, b: r, width: 0,
                          flags: flipped ? RainRenderer.Flag.flipped : 0, style: .outlined))
    }

    /// Pinta lo acumulado y vacía el pincel. Con `inverted`, el relleno es negro y el borde claro
    /// (y los detalles en negro pasan a claros).
    mutating func flush(into instances: inout [RainRenderer.Instance], alpha: CGFloat, depth: UInt32,
                        inverted: Bool = false) {
        defer { parts.removeAll(keepingCapacity: true) }
        guard alpha > 0.004 else { return }
        // El borde claro sobre negro se lee peor: algo más grueso.
        let o = inverted ? Self.outline * 1.6 : Self.outline
        func emit(_ kind: RainRenderer.Kind, _ a: CGPoint, _ b: CGPoint, _ width: CGFloat, _ alpha: CGFloat,
                  _ flags: UInt32) {
            instances.append(RainRenderer.Instance(
                a: SIMD2(Float(a.x), Float(a.y)), b: SIMD2(Float(b.x), Float(b.y)),
                width: Float(width), alpha: Float(min(alpha, 1)), kind: kind.rawValue | flags, depth: depth))
        }
        // Borde: cada pieza en negro (o en claro, invertido), un poco más grande.
        for p in parts where p.style == .outlined {
            let ink = inverted ? p.flags : p.flags | RainRenderer.Flag.ink
            switch p.kind {
            case .ellipse:
                emit(.ellipse, p.a, CGPoint(x: p.b.x + o, y: p.b.y + o), 0, alpha * 0.9, ink)
            case .dome:
                // También la base plana lleva borde: se baja (o se sube) el centro.
                let down: CGFloat = p.flags & RainRenderer.Flag.flipped != 0 ? 1 : -1
                emit(.dome, CGPoint(x: p.a.x, y: p.a.y + down * o), CGPoint(x: p.b.x + o, y: p.b.y + 2 * o),
                     0, alpha * 0.9, ink)
            default:
                emit(p.kind, p.a, p.b, p.width + 2 * o, alpha * 0.9, ink)
            }
        }
        // Relleno claro y detalles en negro (al revés si está invertido), en el orden en que se dieron.
        for p in parts {
            let dark = p.style == .glow ? false : (p.style == .ink) != inverted
            let flags = dark ? p.flags | RainRenderer.Flag.ink : p.flags
            emit(p.kind, p.a, p.b, p.width, p.style == .ink ? alpha * 0.95 : alpha, flags)
        }
    }
}
