import CoreGraphics
import Foundation

/// Por dónde pueden andar los personajes: el borde superior de las ventanas que se ven.
enum Terrain {
    /// Ventana en cuyo borde superior se posa algo que baja de `p` a `q`, si no la tapa otra de delante.
    /// `windows` va de delante a atrás.
    static func landing(on windows: [Obstacle], from p: CGPoint, to q: CGPoint) -> (UInt32, CGRect)? {
        for (i, w) in windows.enumerated() {
            let f = w.frame
            guard let s = Surface.top(of: f, at: q.x), q.y < s.y,
                  p.y >= (Surface.top(of: f, at: p.x)?.y ?? s.y) - 0.5 else { continue }
            if isCovered(CGPoint(x: q.x, y: s.y + 1), in: windows, before: i) { continue }
            return (w.id, f)
        }
        return nil
    }

    /// Si alguna de las `before` primeras ventanas tapa el punto.
    static func isCovered(_ point: CGPoint, in windows: [Obstacle], before index: Int) -> Bool {
        windows[..<index].contains { $0.frame.contains(point) }
    }
}

/// Personajes que acompañan a la lluvia, sin nada de dibujo:
/// - monigotes con paraguas que bajan del cielo, caminan por el borde superior de las ventanas,
///   se caen por las esquinas y bajan flotando hasta otra ventana, el fondo o el agua;
/// - peces que nadan en la inundación.
final class Creatures {
    struct Walker {
        enum State {
            /// Sobre el borde superior de `window`; `offset` es la distancia a su borde izquierdo,
            /// para que el monigote se mueva con la ventana.
            case walking(window: UInt32, offset: CGFloat)
            /// Bajando con el paraguas abierto.
            case falling
            /// Ha caído al agua: se hunde y se desvanece.
            case sinking
        }

        var state: State
        /// Posición de los pies.
        var x, y, vx, vy: CGFloat
        /// 1 hacia la derecha, -1 hacia la izquierda.
        var direction: CGFloat
        var speed: CGFloat
        /// Fase del paso y del balanceo.
        var phase: CGFloat
        /// Tiempo en el estado actual.
        var age: CGFloat = 0
        var alpha: CGFloat = 0
        /// Última ventana sobre la que ha andado: al caer se dibuja en su capa, delante de ella.
        var layer: UInt32?
        var turnIn: CGFloat
    }

    struct Fish {
        var x, y, vx: CGFloat
        /// Mitad del largo del cuerpo.
        var size: CGFloat
        var speed: CGFloat
        /// 1 hacia la derecha, -1 hacia la izquierda.
        var heading: CGFloat
        /// Profundidad preferida, como fracción del agua.
        var depth: CGFloat
        var phase, age, alpha, turnIn: CGFloat
    }

    var walkersEnabled = true { didSet { if !walkersEnabled { walkers.removeAll() } } }
    var fishEnabled = true { didSet { if !fishEnabled { fish.removeAll() } } }

    private(set) var walkers: [Walker] = []
    private(set) var fish: [Fish] = []

    private static let maxWalkers = 3
    private static let maxFish = 6
    /// Velocidad de caída con el paraguas abierto.
    private static let terminalSpeed: CGFloat = 70
    /// Ancho mínimo de una ventana para aterrizar en ella al llegar del cielo.
    private static let minLandingWidth: CGFloat = 120

    private var nextWalker = CGFloat.random(in: 3...6)

    /// Avanza un paso. `ceiling` es la altura por debajo de la barra de menús.
    func step(dt: CGFloat, sim: RainSimulation, ceiling: CGFloat) {
        stepWalkers(dt, sim, ceiling)
        stepFish(dt, sim)
    }

    // MARK: - Monigotes

    private func stepWalkers(_ dt: CGFloat, _ sim: RainSimulation, _ ceiling: CGFloat) {
        guard walkersEnabled else { return }
        nextWalker -= dt
        if nextWalker <= 0 {
            nextWalker = .random(in: 15...35)
            if walkers.count < Self.maxWalkers { spawnWalker(sim, ceiling) }
        }

        let water = sim.waterLevel
        for i in walkers.indices {
            var w = walkers[i]
            w.age += dt
            w.alpha = min(1, w.alpha + dt * 2)
            let px = w.x, py = w.y

            switch w.state {
            case .walking(let id, var offset):
                guard let f = sim.frame(of: id) else {
                    // La ventana ya no está: cae.
                    w.state = .falling
                    w.vx = 0
                    w.vy = 0
                    w.age = 0
                    break
                }
                // De vez en cuando se da la vuelta; contra el viento anda más despacio.
                w.turnIn -= dt
                if w.turnIn <= 0 {
                    w.turnIn = .random(in: 6...14)
                    if Int.random(in: 0..<3) == 0 { w.direction = -w.direction }
                }
                w.phase += dt * w.speed * 0.32
                offset += w.direction * w.speed * (1 + 0.3 * sim.wind * w.direction) * dt
                w.x = f.minX + offset
                if w.x < f.minX || w.x > f.maxX {
                    // Se sale por la esquina y empieza a bajar con el paraguas.
                    w.state = .falling
                    w.vx = w.direction * w.speed
                    w.vy = 0
                    w.y = f.maxY
                    w.age = 0
                } else {
                    w.state = .walking(window: id, offset: offset)
                    w.y = Surface.top(of: f, at: w.x)?.y ?? f.maxY
                }

            case .falling:
                let target = sim.wind * 40 + sin(w.age * 1.7 + w.phase) * 12
                w.vx += (target - w.vx) * min(1, dt * 2)
                w.vy += (-Self.terminalSpeed - w.vy) * min(1, dt * 2.5)
                w.x += w.vx * dt
                w.y += w.vy * dt
                if let (id, f) = Terrain.landing(on: sim.windows, from: CGPoint(x: px, y: py),
                                                 to: CGPoint(x: w.x, y: w.y)) {
                    w.state = .walking(window: id, offset: w.x - f.minX)
                    w.y = Surface.top(of: f, at: w.x)?.y ?? f.maxY
                    w.layer = id
                    w.vx = 0
                    w.vy = 0
                    // Sigue en la dirección en que iba el viento, o hacia el lado con más sitio.
                    w.direction = abs(sim.wind) > 0.15 ? (sim.wind > 0 ? 1 : -1) : (w.x < f.midX ? 1 : -1)
                    w.age = 0
                }

            case .sinking:
                w.y -= 20 * dt
                w.alpha = max(0, 1 - w.age / 1.2)
            }

            // El agua lo alcanza: chapuzón.
            if water > 1, w.y < water - 4 {
                if case .sinking = w.state {} else {
                    w.state = .sinking
                    w.age = 0
                    w.alpha = 1
                    for dx: CGFloat in [-7, 0, 7] {
                        sim.addSplash(x: w.x + dx, y: water, onWater: true)
                    }
                }
            }
            walkers[i] = w
        }
        let width = sim.size.width
        walkers.removeAll { w in
            if case .sinking = w.state, w.age >= 1.2 { return true }
            return w.y < -40 || w.x < -60 || w.x > width + 60
        }
    }

    private func spawnWalker(_ sim: RainSimulation, _ ceiling: CGFloat) {
        // Mejor encima de una ventana visible y ancha; si no hay ninguna, en cualquier sitio.
        let candidates = sim.windows.filter { $0.frame.width >= Self.minLandingWidth && $0.frame.maxY < ceiling - 40 }
        let x: CGFloat
        if let w = candidates.randomElement() {
            x = .random(in: (w.frame.minX + 30)...(w.frame.maxX - 30))
        } else {
            guard sim.size.width > 120 else { return }
            x = .random(in: 60...(sim.size.width - 60))
        }
        // Nace por encima del borde de la barra de menús, que lo tapa hasta que asoma.
        walkers.append(Walker(
            state: .falling, x: x, y: ceiling + 40, vx: 0, vy: -Self.terminalSpeed,
            direction: Bool.random() ? 1 : -1, speed: .random(in: 22...30),
            phase: .random(in: 0...(2 * .pi)), turnIn: .random(in: 6...14)
        ))
    }

    // MARK: - Peces

    private func stepFish(_ dt: CGFloat, _ sim: RainSimulation) {
        let water = sim.waterLevel
        let width = sim.size.width
        guard fishEnabled, water > 1, width > 0 else {
            fish.removeAll()
            return
        }

        // Más peces cuanto más hondo y más ancha la pantalla.
        let target = water > 80 ? min(Self.maxFish, Int(water / 110 * max(0.6, width / 1512))) : 0
        if fish.count < target, CGFloat.random(in: 0...1) < dt * 0.8 {
            let heading: CGFloat = Bool.random() ? 1 : -1
            let size = CGFloat.random(in: 9...16) * FigureBrush.figureScale
            let speed = CGFloat.random(in: 30...70)
            let depth = CGFloat.random(in: 0.15...0.85)
            fish.append(Fish(
                x: heading > 0 ? -size * 3 : width + size * 3, y: water * depth, vx: heading * speed,
                size: size, speed: speed, heading: heading, depth: depth,
                phase: .random(in: 0...(2 * .pi)), age: 0, alpha: 0, turnIn: .random(in: 6...20)
            ))
        }

        // Al vaciarse el agua se desvanecen deprisa.
        let fade: CGFloat = water > 40 ? 1 : 0
        for i in fish.indices {
            var f = fish[i]
            f.age += dt
            f.alpha += (fade - f.alpha) * min(1, dt * (fade > 0 ? 1.5 : 5))
            f.turnIn -= dt
            if f.turnIn <= 0 {
                f.turnIn = .random(in: 8...20)
                if f.x > width * 0.15 && f.x < width * 0.85 { f.heading = -f.heading }
            }
            f.vx += (f.heading * f.speed - f.vx) * min(1, dt * 1.5)
            f.x += f.vx * dt
            // Ondula alrededor de su profundidad, sin asomar por la superficie ni tocar el fondo.
            let low = f.size + 6
            let high = max(low, water - 18 - f.size)
            let targetY = min(max(water * f.depth + sin(f.age * 1.1 + f.phase) * 6, low), high)
            f.y += (targetY - f.y) * min(1, dt * 1.5)
            f.y = min(f.y, high)
            fish[i] = f
        }
        fish.removeAll { f in
            (f.vx < 0 && f.x < -f.size * 4) || (f.vx > 0 && f.x > width + f.size * 4) || (fade == 0 && f.alpha < 0.02)
        }
    }
}
