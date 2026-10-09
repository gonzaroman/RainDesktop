import CoreGraphics
import Foundation

/// Ventana que la lluvia tiene delante, en coordenadas locales de la vista.
struct Obstacle: Equatable {
    let id: UInt32
    var frame: CGRect
}

/// Perfil superior de una ventana: plano en el centro y con las esquinas redondeadas de macOS.
enum Surface {
    static let cornerRadius: CGFloat = 10

    static func radius(of frame: CGRect) -> CGFloat {
        min(cornerRadius, frame.width / 2, frame.height / 2)
    }

    /// Altura del borde superior en `x` y su normal hacia fuera, o `nil` si `x` cae fuera de la ventana.
    static func top(of frame: CGRect, at x: CGFloat) -> (y: CGFloat, normal: CGVector)? {
        guard x >= frame.minX, x <= frame.maxX else { return nil }
        let r = radius(of: frame)
        let cx: CGFloat
        if x < frame.minX + r {
            cx = frame.minX + r
        } else if x > frame.maxX - r {
            cx = frame.maxX - r
        } else {
            return (frame.maxY, CGVector(dx: 0, dy: 1))
        }
        let dx = x - cx
        let dy = max(0, r * r - dx * dx).squareRoot()
        return (frame.maxY - r + dy, CGVector(dx: dx / r, dy: dy / r))
    }
}

/// Física de la lluvia, sin nada de dibujo. Unidades: puntos y segundos.
///
/// - Las gotas caen detrás de todas las ventanas. Las cercanas chocan con el borde superior.
/// - Al chocar se rompen en gotitas que rebotan sobre esa ventana.
/// - Las gotitas sin energía se asientan como perlas que resbalan, bajan por el lateral y gotean.
/// Todo lo que está sobre una ventana se mueve con ella y se suelta si la ventana desaparece.
final class RainSimulation {
    struct Drop {
        var x, y, vx, vy, length, alpha: CGFloat
        var near: Bool
    }

    struct Droplet {
        var x, y, vx, vy: CGFloat
        var window: UInt32?
        var age, life, radius: CGFloat
        var bounces: Int
        /// Agua que gotea desde una ventana: cae hasta el fondo de la pantalla y salpica allí.
        var drip = false
    }

    enum Edge { case top, left, right }

    struct Bead {
        var x, y: CGFloat
        /// En el borde superior, velocidad horizontal; en un lateral, velocidad de bajada.
        var v: CGFloat
        var window: UInt32
        var edge: Edge
        var age, life, radius, phase: CGFloat
    }

    /// Burbuja que sube por el agua de la inundación.
    struct Bubble {
        var x, y, radius, vy, phase, age: CGFloat
    }

    /// Hilo de agua que baja por un lateral, alimentado por el agua que llega desde arriba.
    struct Stream {
        /// Caudal, de 0 a 1, según el agua que llega por segundo a este lado.
        var strength: CGFloat = 0
        /// Agua que ha llegado en este paso (impactos laterales y desagüe de arriba).
        var inflow: CGFloat = 0
        /// Cuánto ha bajado el hilo desde la esquina, en puntos.
        var length: CGFloat = 0
        /// Gota que se va formando abajo, de 0 a 1; al llegar a 1 se suelta.
        var charge: CGFloat = 0
    }

    struct Streams {
        /// Agua acumulada encima de la ventana, en «impactos».
        var pool: CGFloat = 0
        var left = Stream()
        var right = Stream()
    }

    struct Splash {
        var x, y: CGFloat
        var window: UInt32?
        var age: CGFloat
        /// Salpicadura contra un lateral: el anillo se dibuja en vertical.
        var vertical = false
        /// Salpicadura en la superficie del agua de la inundación (se ve por delante de todo).
        var onWater = false
    }

    static let gravity: CGFloat = 1800
    static let splashDuration: CGFloat = 0.28
    private static let maxDroplets = 900
    private static let maxBeads = 260
    private static let maxSplashes = 250
    private static let maxDrops = 4500
    private static let maxBubbles = 220
    /// Área de referencia (MacBook Pro 14") para escalar el número de gotas a cada pantalla.
    private static let referenceArea: CGFloat = 1512 * 982
    /// Inclinación máxima de la lluvia: vx = wind * windSlope * velocidad de caída.
    private static let windSlope: CGFloat = 0.42

    var size: CGSize = .zero {
        didSet {
            guard size != oldValue else { return }
            drops.removeAll()
            syncDropCount()
        }
    }
    var intensity: CGFloat = 0.6 { didSet { syncDropCount() } }
    /// De -1 (hacia la izquierda) a 1 (hacia la derecha).
    var wind: CGFloat = 0.25
    /// De 0 (suave) a 1 (fuerte).
    var bounce: CGFloat = 0.5
    var collide = true
    /// Las gotas que el viento empuja contra un lateral también rebotan.
    var sideCollide = false
    var lightning = true { didSet { if !lightning { flash = 0 } } }
    /// Altura del agua de la inundación, en puntos. La lluvia y el goteo acaban en su superficie.
    var waterLevel: CGFloat = 0

    private(set) var windows: [Obstacle] = []
    private(set) var drops: [Drop] = []
    private(set) var droplets: [Droplet] = []
    private(set) var beads: [Bead] = []
    private(set) var splashes: [Splash] = []
    private(set) var wetness: [UInt32: CGFloat] = [:]
    private(set) var streams: [UInt32: Streams] = [:]
    private(set) var bubbles: [Bubble] = []
    private var bubbleBurst = 0
    /// Tiempo de simulación, para animar el ondulado de los hilos.
    private(set) var time: CGFloat = 0
    private(set) var flash: CGFloat = 0
    /// `true` durante el paso en que cae un rayo (para el trueno).
    private(set) var didStrike = false

    private var frames: [UInt32: CGRect] = [:]
    private var nextBolt = CGFloat.random(in: 6...16)
    private var secondPulseIn: CGFloat = -1

    func frame(of id: UInt32) -> CGRect? { frames[id] }

    // MARK: - Ventanas

    /// Recibe las ventanas de delante a atrás. El agua posada sobre una ventana se desplaza con ella;
    /// si la ventana ya no está, el agua se suelta y cae.
    func setWindows(_ new: [Obstacle]) {
        let old = frames
        var current: [UInt32: CGRect] = [:]
        for w in new { current[w.id] = w.frame }
        windows = new
        frames = current

        for i in droplets.indices {
            guard let id = droplets[i].window else { continue }
            if let f = current[id] {
                if let o = old[id] {
                    droplets[i].x += f.minX - o.minX
                    droplets[i].y += f.maxY - o.maxY
                }
            } else {
                droplets[i].window = nil
            }
        }

        var released: [Droplet] = []
        beads.removeAll { b in
            guard current[b.window] == nil else { return false }
            released.append(Droplet(x: b.x, y: b.y, vx: 0, vy: -b.v, window: nil,
                                    age: 0, life: 6, radius: b.radius * 0.8, bounces: 3))
            return true
        }
        droplets += released

        for i in beads.indices {
            let id = beads[i].window
            guard let f = current[id] else { continue }
            let o = old[id] ?? f
            switch beads[i].edge {
            case .top:
                beads[i].x = min(max(beads[i].x + f.minX - o.minX, f.minX + 0.5), f.maxX - 0.5)
                beads[i].y = Surface.top(of: f, at: beads[i].x)?.y ?? f.maxY
            case .left:
                beads[i].x = f.minX - 0.8
                beads[i].y += f.maxY - o.maxY
            case .right:
                beads[i].x = f.maxX + 0.8
                beads[i].y += f.maxY - o.maxY
            }
        }

        for i in splashes.indices {
            guard let id = splashes[i].window else { continue }
            if let f = current[id], let o = old[id] {
                splashes[i].x += f.minX - o.minX
                splashes[i].y += f.maxY - o.maxY
            } else if current[id] == nil {
                splashes[i].window = nil
            }
        }

        wetness = wetness.filter { current[$0.key] != nil }
        streams = streams.filter { current[$0.key] != nil }
    }

    // MARK: - Paso de simulación

    func step(dt: CGFloat) {
        guard size.width > 0, size.height > 0, dt > 0 else { return }
        time += dt
        stepDrops(dt)
        stepDroplets(dt)
        stepBeads(dt)
        stepStreams(dt)
        stepBubbles(dt)

        for i in splashes.indices { splashes[i].age += dt }
        splashes.removeAll { $0.age >= Self.splashDuration }

        let dry = CGFloat(exp(-Double(dt) / 25))
        wetness = wetness.mapValues { $0 * dry }

        stepLightning(dt)
    }

    private var horizontalMargin: CGFloat {
        abs(wind) * Self.windSlope * size.height + 80
    }

    /// Escala exponencial, en una pantalla de 14": llovizna ≈ 250 gotas, ligera ≈ 440, moderada ≈ 700,
    /// fuerte ≈ 1.100, tormenta ≈ 1.600 y diluvio ≈ 2.400.
    private func targetDropCount() -> Int {
        let area = size.width * size.height
        let scale = min(max(area / Self.referenceArea, 0.6), 2.5)
        return min(Int(250 * pow(9.6, intensity) * scale), Self.maxDrops)
    }

    private func syncDropCount() {
        guard size.width > 0, size.height > 0 else { return }
        let target = targetDropCount()
        if drops.count < target {
            drops.reserveCapacity(target)
            for _ in drops.count..<target { drops.append(makeDrop(anywhere: true)) }
        } else if drops.count > target {
            drops.removeLast(drops.count - target)
        }
    }

    private func makeDrop(anywhere: Bool) -> Drop {
        let near = CGFloat.random(in: 0...1) < 0.65
        // Con más intensidad, gotas más rápidas, largas y visibles.
        let heavy = 0.85 + 0.35 * intensity
        let speed = (near ? CGFloat.random(in: 780...1150) : CGFloat.random(in: 420...620)) * heavy
        let vx = wind * Self.windSlope * speed
        // Las gotas nacen a barlovento para que, con viento, la pantalla quede cubierta por igual.
        let drift = vx / speed * size.height
        let minX = min(0, -drift) - 40
        let maxX = size.width + max(0, -drift) + 40
        return Drop(
            x: .random(in: minX...maxX),
            y: anywhere ? .random(in: 0...(size.height + 40)) : size.height + .random(in: 4...60),
            vx: vx,
            vy: -speed,
            length: (near ? .random(in: 16...28) * speed / 950 : .random(in: 9...15)) * heavy,
            alpha: (near ? .random(in: 0.28...0.5) : .random(in: 0.14...0.26)) * (0.9 + 0.2 * intensity),
            near: near
        )
    }

    private func stepDrops(_ dt: CGFloat) {
        let margin = horizontalMargin
        let blend = min(1, dt * 2)
        for i in drops.indices {
            var d = drops[i]
            let targetVX = wind * Self.windSlope * -d.vy
            d.vx += (targetVX - d.vx) * blend
            let next = CGPoint(x: d.x + d.vx * dt, y: d.y + d.vy * dt)

            if collide && d.near, let hit = firstHit(from: CGPoint(x: d.x, y: d.y), to: next),
               hit.point.y >= waterLevel {
                impact(at: hit.point, normal: hit.normal, window: hit.window, edge: hit.edge,
                       velocity: CGVector(dx: d.vx, dy: d.vy))
                drops[i] = makeDrop(anywhere: false)
                continue
            }

            d.x = next.x
            d.y = next.y
            if waterLevel > 1 && d.y < waterLevel {
                // Cae en el agua: anillo en la superficie.
                if d.near && splashes.count < Self.maxSplashes && Int.random(in: 0..<3) == 0 {
                    splashes.append(Splash(x: d.x, y: waterLevel, window: nil, age: 0, onWater: true))
                }
                d = makeDrop(anywhere: false)
            } else if d.y < 0 {
                if d.near && splashes.count < Self.maxSplashes && Int.random(in: 0..<4) == 0 {
                    splashes.append(Splash(x: d.x, y: 1, window: nil, age: 0))
                }
                d = makeDrop(anywhere: false)
            } else if d.x < -margin || d.x > size.width + margin {
                d = makeDrop(anywhere: false)
            }
            drops[i] = d
        }
    }

    private typealias Hit = (point: CGPoint, normal: CGVector, window: UInt32, edge: Edge)

    /// Primer borde que cruza el segmento p→q: el superior y, si está activado, los laterales.
    private func firstHit(from p: CGPoint, to q: CGPoint) -> Hit? {
        var best: Hit?
        var bestT = CGFloat.infinity
        func consider(_ t: CGFloat, _ hit: Hit) {
            if t < bestT { bestT = t; best = hit }
        }
        for w in windows {
            let f = w.frame
            guard max(p.y, q.y) >= f.minY, min(p.y, q.y) <= f.maxY + 1 else { continue }

            // Borde superior (con las esquinas redondeadas).
            if q.x >= f.minX, q.x <= f.maxX, let s = Surface.top(of: f, at: q.x), q.y < s.y {
                let before = Surface.top(of: f, at: p.x)?.y ?? s.y
                if p.y >= before - 0.5 {
                    let t = p.y > q.y ? (p.y - s.y) / (p.y - q.y) : 0
                    consider(t, (CGPoint(x: q.x, y: s.y), s.normal, w.id, .top))
                }
            }

            // Laterales: solo la parte recta, por debajo de la esquina redondeada.
            guard sideCollide, p.x != q.x else { continue }
            let r = Surface.radius(of: f)
            let edges: [(x: CGFloat, crosses: Bool, normal: CGVector, edge: Edge)] = [
                (f.minX, p.x <= f.minX && q.x > f.minX, CGVector(dx: -1, dy: 0), .left),
                (f.maxX, p.x >= f.maxX && q.x < f.maxX, CGVector(dx: 1, dy: 0), .right),
            ]
            for e in edges where e.crosses {
                let t = (e.x - p.x) / (q.x - p.x)
                let y = p.y + (q.y - p.y) * t
                if y >= f.minY && y <= f.maxY - r {
                    consider(t, (CGPoint(x: e.x, y: y), e.normal, w.id, e.edge))
                }
            }
        }
        return best
    }

    private func impact(at p: CGPoint, normal n: CGVector, window id: UInt32, edge: Edge, velocity v: CGVector) {
        let side = edge != .top
        wetness[id] = min(1, (wetness[id] ?? 0) + (side ? 0.004 : 0.01))
        if splashes.count < Self.maxSplashes {
            splashes.append(Splash(x: p.x, y: p.y, window: id, age: 0, vertical: side))
        }
        // El rebote depende sobre todo de la velocidad contra la superficie: de lado, el viento.
        let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        let normalSpeed = abs(v.dx * n.dx + v.dy * n.dy)
        let impactSpeed = normalSpeed * 0.85 + speed * 0.15
        let count = Int.random(in: 1...(2 + Int((bounce * 3).rounded())))
        for _ in 0..<count where droplets.count < Self.maxDroplets {
            let out = impactSpeed * .random(in: 0.12...0.28) * (0.4 + bounce * 1.2)
            let a = CGFloat.random(in: -1.0...1.0)
            let dir = CGVector(dx: n.dx * cos(a) - n.dy * sin(a), dy: n.dx * sin(a) + n.dy * cos(a))
            droplets.append(Droplet(
                x: p.x + dir.dx * 1.5, y: p.y + (side ? dir.dy * 1.5 : max(0.5, dir.dy)),
                vx: dir.dx * out + v.dx * (side ? 0 : 0.25), vy: dir.dy * out + (side ? v.dy * 0.2 : 0),
                window: id, age: 0, life: .random(in: 0.6...1.3),
                radius: .random(in: 0.7...1.3), bounces: 0
            ))
        }
        // Parte del agua se queda en la superficie: arriba corre hacia los bordes; de lado, baja.
        if !side, beads.count < Self.maxBeads, CGFloat.random(in: 0...1) < 0.22, let f = frames[id] {
            beads.append(makeBead(window: id, frame: f, x: p.x))
        }
        if side {
            feed(id, edge, 1)
        } else {
            streams[id, default: Streams()].pool += 1
        }
        if side, beads.count < Self.maxBeads, CGFloat.random(in: 0...1) < 0.12, let f = frames[id] {
            beads.append(Bead(
                x: edge == .left ? f.minX - 0.8 : f.maxX + 0.8, y: p.y, v: 10, window: id, edge: edge,
                age: 0, life: .infinity, radius: .random(in: 1.1...1.6), phase: .random(in: 0...(2 * .pi))
            ))
        }
    }

    private func stepDroplets(_ dt: CGFloat) {
        var settled: [Bead] = []
        for i in droplets.indices {
            var d = droplets[i]
            d.age += dt
            d.vy -= Self.gravity * dt
            let px = d.x, py = d.y
            d.x += d.vx * dt
            d.y += d.vy * dt

            if d.vy < 0, let id = d.window, let f = frames[id],
               let s = Surface.top(of: f, at: d.x), d.y < s.y,
               py >= (Surface.top(of: f, at: px)?.y ?? s.y) - 0.5 {
                let vn = d.vx * s.normal.dx + d.vy * s.normal.dy
                if vn > -60 || d.bounces >= 3 {
                    // Sin energía: se queda como perla o se la bebe el borde mojado.
                    let chance = 0.35 + 0.4 * (wetness[id] ?? 0)
                    if beads.count + settled.count < Self.maxBeads && CGFloat.random(in: 0...1) < chance {
                        settled.append(makeBead(window: id, frame: f, x: d.x))
                    }
                    d.age = d.life
                } else {
                    let restitution = 0.2 + bounce * 0.3
                    d.vx -= (1 + restitution) * vn * s.normal.dx
                    d.vy -= (1 + restitution) * vn * s.normal.dy
                    d.vx *= 0.8
                    d.y = s.y + 0.3
                    d.bounces += 1
                }
            }
            droplets[i] = d
        }
        let ground = max(2, waterLevel)
        for d in droplets where d.drip && d.y < ground && splashes.count < Self.maxSplashes {
            splashes.append(Splash(x: d.x, y: ground, window: waterLevel > 1 ? nil : d.window, age: 0,
                                   onWater: waterLevel > 1))
        }
        let width = size.width
        droplets.removeAll { $0.age >= $0.life || $0.y < ($0.drip ? ground : -4) || $0.x < -50 || $0.x > width + 50 }
        beads += settled
    }

    private func makeBead(window id: UInt32, frame f: CGRect, x: CGFloat) -> Bead {
        let x = min(max(x, f.minX + 0.5), f.maxX - 0.5)
        return Bead(
            x: x, y: Surface.top(of: f, at: x)?.y ?? f.maxY,
            v: .random(in: -10...10), window: id, edge: .top,
            age: 0, life: .random(in: 25...40),
            radius: .random(in: 1.2...1.9), phase: .random(in: 0...(2 * .pi))
        )
    }

    private func stepBeads(_ dt: CGFloat) {
        var drips: [Droplet] = []
        for i in beads.indices {
            var b = beads[i]
            guard let f = frames[b.window] else { continue }
            b.age += dt
            switch b.edge {
            case .top:
                let r = Surface.radius(of: f)
                // Como en una superficie plana, el agua corre hacia el borde más cercano, más deprisa
                // cuanto más mojada está; el viento la empuja.
                let wet = wetness[b.window] ?? 0
                let toEdge: CGFloat = b.x < f.midX ? -1 : 1
                let edgeDistance = min(b.x - f.minX, f.maxX - b.x)
                let nearCorner: CGFloat = edgeDistance < 3 * r ? 30 : 0
                let target = toEdge * (18 + 90 * wet + nearCorner) + wind * 45
                b.v += (target - b.v) * min(1, dt * 1.2)
                b.x += b.v * dt
                if b.x <= f.minX || b.x >= f.maxX {
                    // Dobla la esquina, alimenta el hilo de ese lado y empieza a bajar por él.
                    b.edge = b.x <= f.minX ? .left : .right
                    b.x = b.edge == .left ? f.minX - 0.8 : f.maxX + 0.8
                    b.y = f.maxY - r
                    b.v = 20
                    b.age = 0
                    b.life = .infinity
                } else {
                    b.y = Surface.top(of: f, at: b.x)?.y ?? f.maxY
                }
            case .left, .right:
                // Baja a tirones; por un hilo ya mojado corre más.
                let stream = b.edge == .left ? streams[b.window]?.left : streams[b.window]?.right
                b.v = min(b.v + 160 * dt, 150 + 120 * (stream?.strength ?? 0))
                let pulse = 0.55 + 0.45 * sin(b.age * 2.6 + b.phase)
                b.y -= b.v * pulse * dt
                if b.y <= f.minY {
                    drips.append(Droplet(x: b.x, y: f.minY - 1, vx: wind * 20, vy: -b.v, window: b.window,
                                         age: 0, life: 6, radius: b.radius * 0.9, bounces: 3, drip: true))
                    b.age = .infinity
                }
            }
            beads[i] = b
        }
        beads.removeAll { $0.age >= $0.life }
        droplets += drips
    }

    private func feed(_ id: UInt32, _ edge: Edge, _ amount: CGFloat) {
        switch edge {
        case .left: streams[id, default: Streams()].left.inflow += amount
        case .right: streams[id, default: Streams()].right.inflow += amount
        case .top: break
        }
    }

    private func stepStreams(_ dt: CGFloat) {
        // El agua de arriba desagua en ~1,5 s hacia los dos lados; el viento la empuja a sotavento.
        let drain = 1 - CGFloat(exp(-Double(dt) / 1.5))
        let leftShare = min(max(0.5 - wind * 0.45, 0.08), 0.92)
        let follow = min(1, dt / 1.2)
        var drips: [Droplet] = []
        for (id, var s) in streams {
            guard let f = frames[id] else { continue }
            let outflow = s.pool * drain
            s.pool -= outflow
            s.left.inflow += outflow * leftShare
            s.right.inflow += outflow * (1 - leftShare)
            let full = f.height - Surface.radius(of: f)
            for edge in [Edge.left, .right] {
                var st = edge == .left ? s.left : s.right
                // ~8 impactos/s por lado dan un hilo fino; ~200/s, un chorro.
                let target = 1 - CGFloat(exp(-Double(st.inflow / dt) / 60))
                st.inflow = 0
                st.strength += (target - st.strength) * follow
                if st.strength > 0.04 {
                    // El hilo avanza hacia abajo mientras le llega agua…
                    st.length = min(full, st.length + (50 + 140 * st.strength) * dt)
                } else {
                    // …y se seca desde abajo cuando deja de llegar.
                    st.length = max(0, st.length - 35 * dt)
                }
                if st.length >= full - 0.5 && st.strength > 0.04 {
                    // Abajo se forma una gota que crece hasta soltarse.
                    // Con poco caudal gotea; con mucho, el chorro se rompe en gotas seguidas.
                    st.charge += dt * (0.8 + 13 * st.strength)
                    if st.charge >= 1 {
                        st.charge = 0
                        let x = (edge == .left ? f.minX - 0.8 : f.maxX + 0.8) + .random(in: -0.6...0.6)
                        drips.append(Droplet(x: x, y: f.minY - 4 - 6 * st.strength, vx: wind * 15,
                                             vy: -60 - 120 * st.strength, window: id, age: 0, life: 6,
                                             radius: .random(in: 1.4...2.0) + st.strength * 0.5,
                                             bounces: 3, drip: true))
                    }
                } else {
                    st.charge = max(0, st.charge - dt)
                }
                if edge == .left { s.left = st } else { s.right = st }
            }
            streams[id] = s
        }
        streams = streams.filter { $0.value.pool > 0.01 || $0.value.left.length > 0 || $0.value.right.length > 0
            || $0.value.left.strength > 0.01 || $0.value.right.strength > 0.01 }
        droplets += drips
    }

    private func stepBubbles(_ dt: CGFloat) {
        guard waterLevel > 20 else {
            bubbles.removeAll()
            return
        }
        // Más burbujas cuanto más ancha es la pantalla y más hondo está el agua.
        let rate = 9 * size.width / 1512 * min(1, waterLevel / 250)
        if CGFloat.random(in: 0...1) < rate * dt {
            // A veces sale una racha de varias desde el mismo sitio.
            let x = CGFloat.random(in: 0...size.width)
            let count = Int.random(in: 0..<5) == 0 ? Int.random(in: 3...6) : 1
            for i in 0..<count where bubbles.count < Self.maxBubbles {
                let radius = CGFloat.random(in: 1.2...4.5)
                bubbles.append(Bubble(x: x + .random(in: -6...6), y: -radius - CGFloat(i) * 9,
                                      radius: radius, vy: .random(in: 25...45),
                                      phase: .random(in: 0...(2 * .pi)), age: 0))
            }
        }
        let surface = waterLevel - 2
        var popped: [Splash] = []
        for i in bubbles.indices {
            var b = bubbles[i]
            b.age += dt
            // Suben cada vez más deprisa (las grandes más) y se balancean de lado a lado.
            b.vy = min(b.vy + 40 * dt, 50 + b.radius * 22)
            b.y += b.vy * dt
            b.x += sin(b.age * 3.2 + b.phase) * (8 + b.radius * 2) * dt
            if b.y + b.radius >= surface {
                if splashes.count + popped.count < Self.maxSplashes {
                    popped.append(Splash(x: b.x, y: waterLevel, window: nil, age: Self.splashDuration * 0.35,
                                         onWater: true))
                }
                b.age = -1
            }
            bubbles[i] = b
        }
        bubbles.removeAll { $0.age < 0 }
        splashes += popped
    }

    private func stepLightning(_ dt: CGFloat) {
        didStrike = false
        if lightning {
            nextBolt -= dt
            if nextBolt <= 0 {
                flash = max(flash, .random(in: 0.10...0.18))
                didStrike = true
                secondPulseIn = 0.09
                nextBolt = .random(in: 8...22)
            }
            if secondPulseIn > 0 {
                secondPulseIn -= dt
                if secondPulseIn <= 0 {
                    flash = max(flash, .random(in: 0.06...0.11))
                }
            }
        }
        flash *= CGFloat(exp(-Double(dt) * 7))
        if flash < 0.003 { flash = 0 }
    }
}
