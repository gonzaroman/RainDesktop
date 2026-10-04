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

    struct Splash {
        var x, y: CGFloat
        var window: UInt32?
        var age: CGFloat
    }

    static let gravity: CGFloat = 1800
    static let splashDuration: CGFloat = 0.28
    private static let maxDroplets = 400
    private static let maxBeads = 60
    private static let maxSplashes = 120
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
    var lightning = true { didSet { if !lightning { flash = 0 } } }

    private(set) var windows: [Obstacle] = []
    private(set) var drops: [Drop] = []
    private(set) var droplets: [Droplet] = []
    private(set) var beads: [Bead] = []
    private(set) var splashes: [Splash] = []
    private(set) var wetness: [UInt32: CGFloat] = [:]
    private(set) var flash: CGFloat = 0

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
    }

    // MARK: - Paso de simulación

    func step(dt: CGFloat) {
        guard size.width > 0, size.height > 0, dt > 0 else { return }
        stepDrops(dt)
        stepDroplets(dt)
        stepBeads(dt)

        for i in splashes.indices { splashes[i].age += dt }
        splashes.removeAll { $0.age >= Self.splashDuration }

        let dry = CGFloat(exp(-Double(dt) / 25))
        wetness = wetness.mapValues { $0 * dry }

        stepLightning(dt)
    }

    private var horizontalMargin: CGFloat {
        abs(wind) * Self.windSlope * size.height + 80
    }

    private func targetDropCount() -> Int {
        let area = size.width * size.height
        let scale = min(max(area / Self.referenceArea, 0.6), 2.5)
        return Int((90 + 650 * intensity) * scale)
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
        let speed = near ? CGFloat.random(in: 780...1150) : CGFloat.random(in: 420...620)
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
            length: near ? .random(in: 16...28) * speed / 950 : .random(in: 9...15),
            alpha: near ? .random(in: 0.28...0.5) : .random(in: 0.14...0.26),
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

            if collide && d.near, let hit = firstHit(from: CGPoint(x: d.x, y: d.y), to: next) {
                impact(at: hit.point, normal: hit.normal, window: hit.window, velocity: CGVector(dx: d.vx, dy: d.vy))
                drops[i] = makeDrop(anywhere: false)
                continue
            }

            d.x = next.x
            d.y = next.y
            if d.y < 0 {
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

    /// Primer borde superior que cruza el segmento p→q (el más alto, porque la gota cae).
    private func firstHit(from p: CGPoint, to q: CGPoint) -> (point: CGPoint, normal: CGVector, window: UInt32)? {
        var best: (point: CGPoint, normal: CGVector, window: UInt32)?
        for w in windows {
            let f = w.frame
            guard q.x >= f.minX, q.x <= f.maxX, q.y <= f.maxY, p.y >= f.minY,
                  let s = Surface.top(of: f, at: q.x), q.y < s.y else { continue }
            let before = Surface.top(of: f, at: p.x)?.y ?? s.y
            guard p.y >= before - 0.5 else { continue }
            if best == nil || s.y > best!.point.y {
                best = (CGPoint(x: q.x, y: s.y), s.normal, w.id)
            }
        }
        return best
    }

    private func impact(at p: CGPoint, normal n: CGVector, window id: UInt32, velocity v: CGVector) {
        wetness[id] = min(1, (wetness[id] ?? 0) + 0.01)
        if splashes.count < Self.maxSplashes {
            splashes.append(Splash(x: p.x, y: p.y, window: id, age: 0))
        }
        let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        let count = Int.random(in: 1...(2 + Int((bounce * 3).rounded())))
        for _ in 0..<count where droplets.count < Self.maxDroplets {
            let out = speed * .random(in: 0.12...0.28) * (0.4 + bounce * 1.2)
            let a = CGFloat.random(in: -1.0...1.0)
            let dir = CGVector(dx: n.dx * cos(a) - n.dy * sin(a), dy: n.dx * sin(a) + n.dy * cos(a))
            droplets.append(Droplet(
                x: p.x + dir.dx, y: p.y + max(0.5, dir.dy),
                vx: dir.dx * out + v.dx * 0.25, vy: dir.dy * out,
                window: id, age: 0, life: .random(in: 0.6...1.3),
                radius: .random(in: 0.7...1.3), bounces: 0
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
                    let chance = 0.18 + 0.25 * (wetness[id] ?? 0)
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
        let width = size.width
        droplets.removeAll { $0.age >= $0.life || $0.y < -4 || $0.x < -50 || $0.x > width + 50 }
        beads += settled
    }

    private func makeBead(window id: UInt32, frame f: CGRect, x: CGFloat) -> Bead {
        let x = min(max(x, f.minX + 0.5), f.maxX - 0.5)
        return Bead(
            x: x, y: Surface.top(of: f, at: x)?.y ?? f.maxY,
            v: .random(in: -18...18), window: id, edge: .top,
            age: 0, life: .random(in: 2.5...6),
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
                var target = wind * 45
                // Cerca de una esquina, el agua tiende a irse hacia ella.
                if b.x < f.minX + 3 * r { target -= 25 } else if b.x > f.maxX - 3 * r { target += 25 }
                b.v += (target - b.v) * min(1, dt * 1.5)
                b.x += b.v * dt
                if b.x <= f.minX || b.x >= f.maxX {
                    // Dobla la esquina y empieza a bajar por el lateral.
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
                // Baja a tirones, como un hilo de agua.
                b.v = min(b.v + 160 * dt, 150)
                let pulse = 0.55 + 0.45 * sin(b.age * 2.6 + b.phase)
                b.y -= b.v * pulse * dt
                if b.y <= f.minY {
                    drips.append(Droplet(x: b.x, y: f.minY - 1, vx: wind * 20, vy: -b.v, window: b.window,
                                         age: 0, life: 6, radius: b.radius * 0.8, bounces: 3))
                    b.age = .infinity
                }
            }
            beads[i] = b
        }
        beads.removeAll { $0.age >= $0.life }
        droplets += drips
    }

    private func stepLightning(_ dt: CGFloat) {
        if lightning {
            nextBolt -= dt
            if nextBolt <= 0 {
                flash = max(flash, .random(in: 0.10...0.18))
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
