import CoreGraphics
import Foundation

/// Modo Mafia: un tipo trajeado e invencible contra oleadas de mafiosos que bajan en cuerda desde la barra
/// de menús, saltan desde los lados o llegan en lancha cuando la pantalla está inundada.
/// Todo es de dibujos animados: los derribados salen volando dando vueltas. Solo física; lo dibuja `RainView`.
final class MafiaFight {
    enum Ground: Equatable {
        case window(UInt32)
        /// El borde inferior de la pantalla, sin inundación.
        case floor
        /// Nadando en la inundación (solo el protagonista; los mafiosos se hunden).
        case water
        case boat(Int)
    }

    /// Delante de qué se pinta cada cosa.
    enum Layer: Equatable {
        /// Detrás de todas las ventanas, como la lluvia.
        case back
        /// En la capa de una ventana: la tapan solo las de delante.
        case window(UInt32)
        /// Delante de todo, como el agua.
        case front
    }

    enum Move: Equatable {
        case stand
        case run
        /// En el aire; `flips` vueltas completas repartidas en el vuelo (negativas, hacia delante).
        case jump(flips: CGFloat)
        /// Voltereta por el suelo para esquivar.
        case roll
        /// Patada voladora.
        case kick
        /// Bajando por una cuerda.
        case rope
        /// Aterrizaje; el del protagonista al llegar es con una rodilla en el suelo.
        case land(heroic: Bool)
        /// Derribado: sale volando dando vueltas.
        case knocked
        /// Se hunde en el agua.
        case sinking
        /// Nadando: solo el protagonista, mientras busca una lancha o una ventana.
        case swim
    }

    struct Fighter {
        let id: Int
        let hero: Bool
        /// Posición de los pies.
        var x, y, vx, vy: CGFloat
        var ground: Ground?
        /// En una ventana, distancia a su borde izquierdo; en una lancha, al centro; en el suelo o el agua, la x.
        var offset: CGFloat = 0
        var layer: Layer = .back
        /// 1 hacia la derecha, -1 hacia la izquierda.
        var facing: CGFloat
        var move: Move
        var moveTime: CGFloat = 0
        /// Duración prevista del movimiento o del vuelo.
        var moveLength: CGFloat = 0
        /// Giro del cuerpo (positivo, hacia atrás).
        var angle: CGFloat = 0
        var spin: CGFloat = 0
        var think: CGFloat
        var cooldown: CGFloat
        var burst = 0
        var health: Int
        var speed: CGFloat
        var targetX: CGFloat?
        /// Dirección de los brazos al apuntar, en la pantalla; se apunta mientras `aimTime` > 0.
        var aim: CGFloat = 0
        var aimTime: CGFloat = 0
        /// Fogonazo del último disparo y mano que disparó (el protagonista lleva dos pistolas).
        var flash: CGFloat = 0
        var hand = 0
        var runPhase: CGFloat = 0
        var alpha: CGFloat = 0
        var hitDone = false
        /// Altura a la que está atada la cuerda.
        var ropeTop: CGFloat = 0
        /// Tiempo hasta la próxima salpicadura al nadar.
        var splashIn: CGFloat = 0

        var dead: Bool { move == .knocked || move == .sinking }
        var scale: CGFloat { hero ? MafiaFight.heroScale : MafiaFight.enemyScale }
        /// Centro del cuerpo, para los disparos.
        var center: CGPoint { CGPoint(x: x, y: y + 12 * scale) }
        var shoulder: CGPoint { CGPoint(x: x, y: y + 16 * scale) }
    }

    struct Bullet {
        var x, y, vx, vy: CGFloat
        var hero: Bool
        var age: CGFloat
        var layer: Layer
    }

    struct Casing {
        var x, y, vx, vy, angle, spin, age: CGFloat
        var resting: Bool
        var layer: Layer
    }

    struct Boat {
        let id: Int
        var x, vx: CGFloat
        var health: Int
        /// Segundos hundiéndose, o -1 si flota.
        var sinking: CGFloat = -1
        var wake: CGFloat = 0
        var alpha: CGFloat = 0
        var facing: CGFloat { vx >= 0 ? 1 : -1 }
    }

    /// Tamaños respecto al diseño original: todos un 20 % más grandes y el protagonista algo más.
    static let enemyScale: CGFloat = FigureBrush.figureScale
    static let heroScale: CGFloat = 1.15 * FigureBrush.figureScale
    static let boatScale: CGFloat = FigureBrush.figureScale
    static let gravity: CGFloat = 1500
    private static let bulletSpeed: CGFloat = 1600
    private static let maxAlive = 18
    private static let maxCasings = 120

    var enabled = false {
        didSet { if !enabled { reset() } }
    }

    private(set) var fighters: [Fighter] = []
    private(set) var bullets: [Bullet] = []
    private(set) var casings: [Casing] = []
    private(set) var boats: [Boat] = []

    private var sim: RainSimulation!
    private var ceiling: CGFloat = 0
    private var nextId = 0
    private var wave = 0
    private var toSpawn = 0
    private var rest: CGFloat = 2.5
    private var spawnTimer: CGFloat = 0
    private var heroTimer: CGFloat = 0.4

    private func reset() {
        fighters.removeAll()
        bullets.removeAll()
        casings.removeAll()
        boats.removeAll()
        wave = 0
        toSpawn = 0
        rest = 2.5
        heroTimer = 0.4
    }

    /// Avanza un paso. `ceiling` es la altura por debajo de la barra de menús.
    func step(dt: CGFloat, sim: RainSimulation, ceiling: CGFloat) {
        guard enabled, sim.size.width > 0, sim.size.height > 0 else { return }
        self.sim = sim
        self.ceiling = ceiling

        if let h = fighters.firstIndex(where: { $0.hero }) {
            // Si se ha perdido fuera de la pantalla, vuelve a bajar del cielo.
            let f = fighters[h]
            if f.x < -60 || f.x > sim.size.width + 60 || f.y < -80 {
                fighters.remove(at: h)
                spawnHero()
            }
            stepWaves(dt)
        } else {
            heroTimer -= dt
            if heroTimer <= 0 { spawnHero() }
        }
        stepBoats(dt)
        for i in fighters.indices { stepFighter(i, dt) }
        stepBullets(dt)
        stepCasings(dt)
        cleanUp()
    }

    // MARK: - Aparecer

    private func newId() -> Int {
        nextId += 1
        return nextId
    }

    private func spawnHero() {
        let width = sim.size.width
        let spot = randomSpot() ?? CGPoint(x: width / 2, y: sim.waterLevel > 1 ? sim.waterLevel : 0)
        var h = Fighter(id: newId(), hero: true, x: spot.x, y: ceiling + 30, vx: 0, vy: -250, facing: 1,
                        move: .jump(flips: -1), think: 0.8, cooldown: 1, health: .max, speed: 200)
        h.moveLength = Self.flightTime(from: h.y, vy: h.vy, to: spot.y)
        fighters.append(h)
        rest = 2.5
    }

    private func stepWaves(_ dt: CGFloat) {
        let alive = fighters.reduce(0) { $0 + (!$1.hero && !$1.dead ? 1 : 0) }
        if toSpawn == 0 {
            // Entre oleadas, un respiro; luego llega una más grande.
            if alive == 0 {
                rest -= dt
                if rest <= 0 {
                    wave += 1
                    toSpawn = min(40, 6 + wave * 4)
                    rest = 3.5
                }
            }
            return
        }
        spawnTimer -= dt
        guard spawnTimer <= 0, alive < Self.maxAlive else { return }
        spawnTimer = .random(in: 0.25...0.7)
        toSpawn = max(0, toSpawn - spawnEnemies())
    }

    /// Hace aparecer uno o varios enemigos (una lancha trae a varios) y dice cuántos.
    private func spawnEnemies() -> Int {
        let width = sim.size.width
        let water = sim.waterLevel
        if water > 70, boats.count < 3, Int.random(in: 0..<3) == 0 || randomSpot() == nil {
            return spawnBoat()
        }
        if let spot = randomSpot() {
            if Bool.random() {
                // Baja en cuerda desde la barra de menús.
                var e = makeEnemy(x: spot.x, y: ceiling + 20, move: .rope)
                e.ropeTop = ceiling + 40
                e.vy = -.random(in: 260...360)
                fighters.append(e)
            } else {
                // Entra saltando desde un lado.
                let fromLeft = spot.x < width / 2
                var e = makeEnemy(x: fromLeft ? -20 : width + 20,
                                  y: min(ceiling - 40, spot.y + .random(in: 40...160)), move: .stand)
                launch(&e, to: spot, flips: Bool.random() ? -1 : 0)
                fighters.append(e)
            }
            return 1
        }
        if water <= 1 {
            // Sin ventanas ni agua: entra corriendo por el suelo.
            let fromLeft = Bool.random()
            var e = makeEnemy(x: fromLeft ? -20 : width + 20, y: 0, move: .run)
            e.ground = .floor
            e.offset = e.x
            e.facing = fromLeft ? 1 : -1
            e.targetX = .random(in: (width * 0.2)...(width * 0.8))
            fighters.append(e)
            return 1
        }
        return 0
    }

    private func makeEnemy(x: CGFloat, y: CGFloat, move: Move) -> Fighter {
        Fighter(id: newId(), hero: false, x: x, y: y, vx: 0, vy: 0, facing: 1, move: move,
                think: .random(in: 0.3...0.8), cooldown: .random(in: 0.8...1.8),
                health: Int.random(in: 0..<4) == 0 ? 2 : 1, speed: .random(in: 150...230))
    }

    private func spawnBoat() -> Int {
        let width = sim.size.width
        let fromLeft = Bool.random()
        let speed = CGFloat.random(in: 120...170)
        let boat = Boat(id: newId(), x: fromLeft ? -60 : width + 60, vx: fromLeft ? speed : -speed, health: 6)
        boats.append(boat)
        let crew = Int.random(in: 2...3)
        for k in 0..<crew {
            var e = makeEnemy(x: boat.x, y: sim.waterLevel, move: .stand)
            e.ground = .boat(boat.id)
            e.offset = (CGFloat(k) * 15 - 15) * Self.boatScale
            e.facing = boat.facing
            e.layer = .front
            fighters.append(e)
        }
        return crew
    }

    // MARK: - Por dónde se anda

    /// Un punto visible en el borde superior de alguna ventana, por encima del agua y por debajo de la
    /// barra de menús. Con `near`, el más cercano de unos cuantos al azar.
    private func randomSpot(near: CGFloat? = nil, excluding: UInt32? = nil) -> CGPoint? {
        let windows = sim.windows
        let water = sim.waterLevel
        let usable = windows.indices.filter { i in
            let f = windows[i].frame
            return f.width >= 70 && f.maxY < ceiling - 30 && f.maxY > water + 14 && windows[i].id != excluding
        }
        var best: CGPoint?
        for _ in 0..<(near == nil ? 6 : 10) {
            guard let i = usable.randomElement() else { break }
            let f = windows[i].frame
            let x = CGFloat.random(in: (f.minX + 16)...(f.maxX - 16))
            let y = Surface.top(of: f, at: x)?.y ?? f.maxY
            let p = CGPoint(x: x, y: y)
            guard !Terrain.isCovered(CGPoint(x: x, y: y + 1), in: windows, before: i) else { continue }
            guard let near else { return p }
            if best.map({ abs($0.x - near) > abs(x - near) }) ?? true { best = p }
        }
        if best == nil, water <= 1, usable.isEmpty, sim.size.width > 100 {
            return CGPoint(x: .random(in: 40...(sim.size.width - 40)), y: 0)
        }
        return best
    }

    /// Tiempo hasta bajar a `y1` cayendo desde `y0` con velocidad vertical `vy`.
    private static func flightTime(from y0: CGFloat, vy: CGFloat, to y1: CGFloat) -> CGFloat {
        let g = gravity
        let disc = vy * vy + 2 * g * (y0 - y1)
        guard disc > 0 else { return 0.6 }
        return max(0.2, (vy + disc.squareRoot()) / g)
    }

    /// Salto en parábola hasta `target`, pasando por encima con algo de altura.
    private func launch(_ f: inout Fighter, to target: CGPoint, flips: CGFloat) {
        let g = Self.gravity
        let apex = max(f.y, target.y) + .random(in: 50...110)
        let up = (2 * g * (apex - f.y)).squareRoot()
        let t = up / g + (2 * (apex - target.y) / g).squareRoot()
        f.vx = (target.x - f.x) / t
        f.vy = up
        f.facing = f.vx >= 0 ? 1 : -1
        f.ground = nil
        f.move = .jump(flips: flips)
        f.moveTime = 0
        f.moveLength = t
        f.targetX = nil
    }

    /// Lo coloca sobre su suelo. Devuelve `false` si se ha quedado sin suelo.
    private func follow(_ f: inout Fighter) -> Bool {
        let width = sim.size.width
        switch f.ground {
        case .window(let id)?:
            guard let fr = sim.frame(of: id) else { return false }
            f.x = fr.minX + f.offset
            guard f.x >= fr.minX, f.x <= fr.maxX else { return false }
            f.y = Surface.top(of: fr, at: f.x)?.y ?? fr.maxY
        case .floor?:
            guard sim.waterLevel <= 1 else { return false }
            f.offset = min(max(f.offset, -30), width + 30)
            f.x = f.offset
            f.y = 0
        case .water?:
            guard sim.waterLevel > 2 else { return false }
            f.offset = min(max(f.offset, 12), width - 12)
            f.x = f.offset
            // Nadando, solo asoman la cabeza, los hombros y los brazos.
            f.y = sim.waterSurface(at: f.x) - 12 * f.scale
        case .boat(let id)?:
            guard let b = boats.first(where: { $0.id == id }), b.sinking < 0 else { return false }
            f.x = b.x + f.offset
            f.y = deck(of: b)
        case nil:
            return false
        }
        return true
    }

    /// Altura de la cubierta de una lancha, sobre las olas.
    func deck(of b: Boat) -> CGFloat {
        sim.waterSurface(at: b.x) + 5 - max(0, b.sinking) * 30
    }

    /// Hasta dónde puede correr en su suelo actual.
    private func runRange(_ f: Fighter) -> ClosedRange<CGFloat>? {
        switch f.ground {
        case .window(let id)?:
            guard let fr = sim.frame(of: id), fr.width > 30 else { return nil }
            return (fr.minX + 12)...(fr.maxX - 12)
        case .floor?:
            return 20...max(21, sim.size.width - 20)
        default:
            return nil
        }
    }

    // MARK: - Cada personaje

    private func stepFighter(_ i: Int, _ dt: CGFloat) {
        var f = fighters[i]
        f.moveTime += dt
        f.alpha = min(1, f.alpha + dt * 4)
        f.aimTime -= dt
        f.flash -= dt
        f.cooldown -= dt
        let px = f.x, py = f.y

        switch f.move {
        case .knocked:
            f.vy -= Self.gravity * dt
            f.x += f.vx * dt
            f.y += f.vy * dt
            f.angle += f.spin * dt
            if f.moveTime > 1.6 { f.alpha = max(0, 1 - (f.moveTime - 1.6) / 0.6) }
            dunk(&f)

        case .sinking:
            f.y -= 25 * dt
            f.alpha = max(0, 1 - f.moveTime / 1.2)

        case .rope:
            f.y += f.vy * dt
            if let (id, fr) = Terrain.landing(on: sim.windows, from: CGPoint(x: px, y: py),
                                              to: CGPoint(x: f.x, y: f.y)) {
                land(&f, on: .window(id), frame: fr)
            } else if f.y < 2, sim.waterLevel <= 1 {
                land(&f, on: .floor, frame: nil)
            }
            dunk(&f)
            enemyShoot(&f)

        case .jump(let flips):
            f.vy -= Self.gravity * dt
            f.x += f.vx * dt
            f.y += f.vy * dt
            let progress = min(1, f.moveTime / max(f.moveLength, 0.2))
            f.angle = flips * 2 * .pi * progress
            if f.vy < 0, let (id, fr) = Terrain.landing(on: sim.windows, from: CGPoint(x: px, y: py),
                                                         to: CGPoint(x: f.x, y: f.y)) {
                land(&f, on: .window(id), frame: fr)
            } else if f.hero, f.vy < 0, let b = boats.first(where: { b in
                let d = deck(of: b)
                return b.sinking < 0 && abs(f.x - b.x) < 38 * Self.boatScale && py >= d && f.y < d
            }) {
                board(&f, b)
            } else if f.vy < 0, sim.waterLevel <= 1, f.y <= 0 {
                land(&f, on: .floor, frame: nil)
            } else if f.vy < 0, sim.waterLevel > 1, f.y < sim.waterSurface(at: f.x) {
                if f.hero {
                    land(&f, on: .water, frame: nil)
                    for dx: CGFloat in [-6, 0, 6] { sim.addSplash(x: f.x + dx, y: sim.waterLevel, onWater: true) }
                } else {
                    dunk(&f)
                }
            }
            if f.hero { heroShoot(&f) } else { enemyShoot(&f) }

        case .stand, .run, .roll, .kick, .land, .swim:
            if !follow(&f) {
                fall(&f)
                break
            }
            if !f.hero, f.move != .sinking, sim.waterLevel > 1, f.y < sim.waterLevel - 3 {
                // La inundación le cubre la ventana.
                dunk(&f)
                if f.move == .sinking { break }
            }
            if f.hero, sim.waterLevel > 1, f.y < sim.waterLevel - 3, f.ground != .water {
                // La inundación le cubre la ventana: se pone a nadar.
                land(&f, on: .water, frame: nil)
                sim.addSplash(x: f.x, y: sim.waterLevel, onWater: true)
            }
            grounded(&f, i, dt)
        }
        fighters[i] = f
    }

    /// Se queda sin suelo: cae (o sigue la trayectoria con la que salió del borde).
    private func fall(_ f: inout Fighter) {
        f.ground = nil
        f.move = .jump(flips: 0)
        f.moveTime = 0
        f.moveLength = 0.6
        f.vy = max(f.vy, 0)
        if f.vx == 0 { f.vx = f.facing * 40 }
    }

    private func land(_ f: inout Fighter, on ground: Ground, frame: CGRect?) {
        let heroic = f.hero && f.health == .max && f.moveTime > 0.5 && f.vy < -500
        f.ground = ground
        switch ground {
        case .window(let id):
            f.offset = f.x - (frame?.minX ?? 0)
            f.layer = .window(id)
        case .water:
            f.offset = f.x
            f.layer = .front
            f.move = .swim
            f.moveTime = 0
            f.targetX = nil
            f.angle = 0
            f.vx = 0
            f.vy = 0
            _ = follow(&f)
            return
        case .boat(let id):
            let bx = boats.first { $0.id == id }?.x ?? f.x
            f.offset = min(max(f.x - bx, -18 * Self.boatScale), 18 * Self.boatScale)
            f.layer = .front
        case .floor:
            f.offset = f.x
            f.layer = .back
        }
        f.move = .land(heroic: heroic)
        f.moveTime = 0
        f.moveLength = heroic ? 0.5 : 0.15
        f.angle = 0
        f.vx = 0
        f.vy = 0
        _ = follow(&f)
    }

    /// El protagonista sube de un salto a una lancha y echa al agua a los que haya en ella.
    private func board(_ h: inout Fighter, _ b: Boat) {
        land(&h, on: .boat(b.id), frame: nil)
        for j in fighters.indices where fighters[j].ground == .boat(b.id) && !fighters[j].hero && !fighters[j].dead {
            let away: CGFloat = fighters[j].x >= h.x ? 1 : -1
            knock(j, vx: away * .random(in: 220...380), vy: .random(in: 360...500))
            fighters[j].layer = .front
        }
    }

    /// Si el protagonista va en la lancha `id`.
    private func heroAboard(_ id: Int) -> Bool {
        fighters.contains { $0.hero && $0.ground == .boat(id) }
    }

    /// Un enemigo que acaba en el agua se hunde con un chapuzón.
    private func dunk(_ f: inout Fighter) {
        guard !f.hero, f.move != .sinking, sim.waterLevel > 1, f.y < sim.waterSurface(at: f.x) - 2 else { return }
        if case .boat = f.ground { return }
        f.move = .sinking
        f.moveTime = 0
        f.ground = nil
        f.layer = .front
        for dx: CGFloat in [-6, 0, 6] { sim.addSplash(x: f.x + dx, y: sim.waterLevel, onWater: true) }
    }

    private func grounded(_ f: inout Fighter, _ i: Int, _ dt: CGFloat) {
        switch f.move {
        case .land:
            if f.moveTime >= f.moveLength { f.move = .stand }
        case .roll:
            f.offset += f.facing * 260 * dt
            if f.moveTime >= f.moveLength { f.move = .stand }
        case .kick:
            f.offset += f.facing * 60 * dt
            if !f.hitDone, f.moveTime > 0.12 {
                f.hitDone = true
                kickHits(from: f)
            }
            if f.moveTime >= f.moveLength { f.move = .stand }
        case .run:
            if let target = f.targetX {
                let step = f.facing * f.speed * dt
                if abs(target - f.x) <= abs(step) {
                    f.move = .stand
                    f.targetX = nil
                } else {
                    f.offset += step
                    f.runPhase += f.speed * dt * 0.11
                }
            } else {
                f.move = .stand
            }
        case .swim:
            // Crol con salpicaduras; sin destino, se mantiene a flote.
            if let target = f.targetX {
                let step = f.facing * 80 * dt
                if abs(target - f.x) <= abs(step) {
                    f.targetX = nil
                } else {
                    f.offset += step
                }
            }
            f.runPhase += dt * (f.targetX == nil ? 3 : 7)
            f.splashIn -= dt
            if f.splashIn <= 0, f.targetX != nil {
                f.splashIn = 0.35
                sim.addSplash(x: f.x + f.facing * 8, y: sim.waterLevel, onWater: true)
            }
        default:
            break
        }
        // En una lancha va donde la lleve la lancha.
        if case .boat = f.ground { f.offset = min(max(f.offset, -18 * Self.boatScale), 18 * Self.boatScale) }

        // Al salirse por el borde de la ventana, cae.
        if case .window = f.ground, !follow(&f) {
            f.vx = f.facing * (f.move == .roll ? 260 : f.speed * 0.8)
            fall(&f)
            return
        }

        f.think -= dt
        let busy: Bool
        switch f.move {
        case .roll, .kick, .land: busy = true
        default: busy = false
        }
        if f.think <= 0, !busy {
            if f.hero { heroThink(&f) } else { enemyThink(&f) }
        }
        if f.hero { heroShoot(&f) } else { enemyShoot(&f) }
    }

    // MARK: - Protagonista

    private func nearestEnemy(to f: Fighter) -> Int? {
        var best: Int?
        var bestDistance = CGFloat.infinity
        for (j, e) in fighters.enumerated() where !e.hero && !e.dead && e.alpha > 0.3 {
            let d = hypot(e.x - f.x, e.y - f.y)
            if d < bestDistance {
                bestDistance = d
                best = j
            }
        }
        return best
    }

    private func heroThink(_ h: inout Fighter) {
        if h.ground == .water {
            swimThink(&h)
            return
        }
        h.think = .random(in: 0.22...0.5)
        if case .boat(let mine)? = h.ground, Int.random(in: 0..<4) == 0,
           let b = boats.first(where: { b in
               b.id != mine && b.sinking < 0 && abs(b.x - h.x) < 320
                   && fighters.contains { $0.ground == .boat(b.id) && !$0.dead }
           }) {
            // Salta al abordaje de otra lancha.
            launch(&h, to: CGPoint(x: b.x + b.vx * 0.4, y: deck(of: b)), flips: -1)
            h.layer = .front
            return
        }
        let range = runRange(h)
        guard let ti = nearestEnemy(to: h) else {
            // Sin enemigos: pasea por la ventana o salta a otra.
            if Int.random(in: 0..<4) == 0, let spot = randomSpot(excluding: currentWindow(h)) {
                launch(&h, to: spot, flips: -1)
            } else if let range {
                run(&h, to: .random(in: range))
            }
            return
        }
        let e = fighters[ti]
        let dx = e.x - h.x, dy = e.y - h.y
        let roll = CGFloat.random(in: 0...1)
        if abs(dx) < 36, abs(dy) < 26, e.ground != nil {
            // Cuerpo a cuerpo: patada voladora.
            h.facing = dx >= 0 ? 1 : -1
            h.move = .kick
            h.moveTime = 0
            h.moveLength = 0.38
            h.hitDone = false
        } else if bulletIncoming(h), roll < 0.5, range != nil {
            h.facing = Bool.random() ? 1 : -1
            h.move = .roll
            h.moveTime = 0
            h.moveLength = 0.42
        } else if roll < 0.2, let spot = randomSpot(near: Bool.random() ? e.x : nil, excluding: currentWindow(h)) {
            launch(&h, to: spot, flips: [-1, -1, -2, 1].randomElement()!)
        } else if let range {
            // Hacia el enemigo si está en la misma ventana; si no, a cualquier sitio.
            let x = h.ground == e.ground && Bool.random() ? e.x - (dx >= 0 ? 24 : -24) : .random(in: range)
            run(&h, to: min(max(x, range.lowerBound), range.upperBound))
        }
    }

    /// Nadando: sube a la lancha más cercana o salta a una ventana; si no, nada hacia la lancha.
    private func swimThink(_ h: inout Fighter) {
        h.think = .random(in: 0.3...0.6)
        let boat = boats.filter { $0.sinking < 0 }.min { abs($0.x - h.x) < abs($1.x - h.x) }
        if let b = boat, abs(b.x - h.x) < 70 {
            launch(&h, to: CGPoint(x: b.x + b.vx * 0.4, y: deck(of: b)), flips: -1)
            h.layer = .front
        } else if CGFloat.random(in: 0...1) < 0.35, let spot = randomSpot(near: h.x),
                  spot.y - sim.waterLevel < 260 {
            launch(&h, to: spot, flips: -1)
            h.layer = .front
        } else if let b = boat {
            swim(&h, to: b.x)
        } else {
            swim(&h, to: .random(in: 40...max(41, sim.size.width - 40)))
        }
    }

    private func swim(_ f: inout Fighter, to x: CGFloat) {
        f.targetX = x
        f.facing = x > f.x ? 1 : -1
    }

    private func currentWindow(_ f: Fighter) -> UInt32? {
        if case .window(let id)? = f.ground { return id }
        return nil
    }

    private func run(_ f: inout Fighter, to x: CGFloat) {
        guard abs(x - f.x) > 4 else { return }
        f.targetX = x
        f.facing = x > f.x ? 1 : -1
        f.move = .run
    }

    private func bulletIncoming(_ h: Fighter) -> Bool {
        let c = h.center
        return bullets.contains { b in
            guard !b.hero else { return false }
            let toward = (c.x - b.x) * b.vx + (c.y - b.y) * b.vy > 0
            return toward && hypot(c.x - b.x, c.y - b.y) < 220
        }
    }

    private func heroShoot(_ h: inout Fighter) {
        guard h.cooldown <= 0, let ti = nearestEnemy(to: h) else { return }
        let e = fighters[ti]
        // A veces apunta al casco de la lancha para hundirla.
        var target = e.center
        if case .boat(let id)? = e.ground, Int.random(in: 0..<3) == 0, let b = boats.first(where: { $0.id == id }) {
            target = CGPoint(x: b.x, y: deck(of: b) - 5)
        }
        fire(&h, at: target, spread: 0.02)
        h.burst += 1
        if h.burst >= 3 {
            h.burst = 0
            h.cooldown = .random(in: 0.3...0.7)
        } else {
            h.cooldown = 0.11
        }
        h.hand = 1 - h.hand
    }

    private func kickHits(from h: Fighter) {
        for j in fighters.indices where !fighters[j].hero && !fighters[j].dead {
            let e = fighters[j]
            let ahead = (e.x - h.x) * h.facing
            if ahead > -12, ahead < 46, abs(e.y - h.y) < 30 {
                knock(j, vx: h.facing * .random(in: 420...600), vy: .random(in: 380...520))
            }
        }
    }

    private func knock(_ j: Int, vx: CGFloat, vy: CGFloat) {
        var e = fighters[j]
        e.move = .knocked
        e.moveTime = 0
        e.ground = nil
        e.vx = vx
        e.vy = vy
        e.spin = .random(in: 9...16) * (Bool.random() ? 1 : -1)
        e.health = 0
        e.aimTime = 0
        fighters[j] = e
    }

    // MARK: - Mafiosos

    private func enemyThink(_ e: inout Fighter) {
        e.think = .random(in: 0.35...0.9)
        guard let h = fighters.first(where: { $0.hero }) else { return }
        let roll = CGFloat.random(in: 0...1)
        if case .boat? = e.ground {
            // Desde la lancha, alguno salta a las ventanas.
            if roll < 0.12, let spot = randomSpot(near: h.x) {
                launch(&e, to: spot, flips: -1)
                e.layer = .front
            }
            return
        }
        guard let range = runRange(e) else { return }
        let dx = h.x - e.x
        if e.ground == h.ground, abs(dx) < 180, roll < 0.6 {
            // A por él.
            run(&e, to: min(max(h.x - (dx >= 0 ? 16 : -16), range.lowerBound), range.upperBound))
        } else if roll < 0.3, let spot = randomSpot(near: h.x, excluding: currentWindow(e)) {
            launch(&e, to: spot, flips: [0, 0, -1, 1].randomElement()!)
        } else {
            run(&e, to: .random(in: range))
        }
    }

    private func enemyShoot(_ e: inout Fighter) {
        guard e.cooldown <= 0, e.alpha > 0.5, let h = fighters.first(where: { $0.hero }) else { return }
        e.cooldown = .random(in: 0.9...2.0)
        // Tienen muy mala puntería.
        fire(&e, at: h.center, spread: 0.22)
    }

    private func fire(_ f: inout Fighter, at target: CGPoint, spread: CGFloat) {
        let from = f.shoulder
        let a = atan2(target.y - from.y, target.x - from.x) + .random(in: -spread...spread)
        f.aim = a
        f.aimTime = 0.45
        f.flash = 0.06
        if f.move == .stand || f.move == .run || (f.move == .swim && f.targetX == nil) {
            f.facing = cos(a) >= 0 ? 1 : -1
        }
        let dir = CGVector(dx: cos(a), dy: sin(a))
        let muzzle = CGPoint(x: from.x + dir.dx * 13 * f.scale, y: from.y + dir.dy * 13 * f.scale)
        bullets.append(Bullet(x: muzzle.x, y: muzzle.y, vx: dir.dx * Self.bulletSpeed, vy: dir.dy * Self.bulletSpeed,
                              hero: f.hero, age: 0, layer: f.layer))
        if casings.count < Self.maxCasings {
            casings.append(Casing(x: from.x + dir.dx * 8, y: from.y + dir.dy * 8 + 1,
                                  vx: -f.facing * .random(in: 40...100), vy: .random(in: 120...220),
                                  angle: .random(in: 0...(2 * .pi)), spin: .random(in: -20...20), age: 0,
                                  resting: false, layer: f.layer))
        }
    }

    // MARK: - Balas, casquillos y lanchas

    private func stepBullets(_ dt: CGFloat) {
        let width = sim.size.width, height = sim.size.height
        var hits: [Int] = []
        for i in bullets.indices {
            var b = bullets[i]
            b.age += dt
            let p = CGPoint(x: b.x, y: b.y)
            b.x += b.vx * dt
            b.y += b.vy * dt
            let q = CGPoint(x: b.x, y: b.y)
            if b.hero {
                if let j = fighters.indices.first(where: { j in
                    let e = fighters[j]
                    return !e.hero && !e.dead && e.alpha > 0.3 && Self.distance(e.center, p, q) < 8 * e.scale
                }) {
                    hit(j, by: b)
                    hits.append(i)
                    continue
                }
                if let k = boats.indices.first(where: { k in
                    let boat = boats[k]
                    let d = deck(of: boat)
                    return boat.sinking < 0 && !heroAboard(boat.id) && abs(q.x - boat.x) < 34 * Self.boatScale
                        && q.y < d && q.y > d - 12 * Self.boatScale
                }) {
                    boats[k].health -= 1
                    sim.addSplash(x: q.x, y: deck(of: boats[k]) - 3, onWater: true)
                    if boats[k].health <= 0 { sink(k) }
                    hits.append(i)
                    continue
                }
            }
            if sim.waterLevel > 1, b.y < sim.waterLevel {
                sim.addSplash(x: b.x, y: sim.waterLevel, onWater: true)
                b.age = .infinity
            }
            if b.x < -40 || b.x > width + 40 || b.y < -40 || b.y > height + 40 { b.age = .infinity }
            bullets[i] = b
        }
        for i in hits { bullets[i].age = .infinity }
        bullets.removeAll { $0.age > 1.2 }
    }

    private func hit(_ j: Int, by b: Bullet) {
        fighters[j].health -= 1
        let dir: CGFloat = b.vx >= 0 ? 1 : -1
        if fighters[j].health <= 0 {
            knock(j, vx: dir * .random(in: 180...360), vy: .random(in: 260...420))
        } else {
            // Aguanta uno: retrocede un poco.
            fighters[j].offset += dir * 8
            fighters[j].think = 0.3
        }
    }

    /// Distancia de `c` al segmento p→q.
    private static func distance(_ c: CGPoint, _ p: CGPoint, _ q: CGPoint) -> CGFloat {
        let dx = q.x - p.x, dy = q.y - p.y
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? min(1, max(0, ((c.x - p.x) * dx + (c.y - p.y) * dy) / len2)) : 0
        return hypot(c.x - (p.x + dx * t), c.y - (p.y + dy * t))
    }

    private func stepCasings(_ dt: CGFloat) {
        for i in casings.indices {
            var c = casings[i]
            c.age += dt
            if !c.resting {
                let p = CGPoint(x: c.x, y: c.y)
                c.vy -= Self.gravity * 0.7 * dt
                c.x += c.vx * dt
                c.y += c.vy * dt
                c.angle += c.spin * dt
                if c.vy < 0, let (_, fr) = Terrain.landing(on: sim.windows, from: p, to: CGPoint(x: c.x, y: c.y)) {
                    c.y = (Surface.top(of: fr, at: c.x)?.y ?? fr.maxY) + 0.8
                    c.resting = true
                } else if c.y < max(1, sim.waterLevel) {
                    c.age = .infinity
                }
            }
            casings[i] = c
        }
        casings.removeAll { $0.age > 2.5 }
    }

    private func sink(_ k: Int) {
        boats[k].sinking = 0
        let id = boats[k].id
        for j in fighters.indices where fighters[j].ground == .boat(id) && fighters[j].hero {
            fighters[j].vy = 250
            fighters[j].vx = 0
            fall(&fighters[j])
        }
        for j in fighters.indices where fighters[j].ground == .boat(id) && !fighters[j].dead {
            knock(j, vx: .random(in: -200...200), vy: .random(in: 300...450))
            fighters[j].layer = .front
        }
    }

    private func stepBoats(_ dt: CGFloat) {
        let width = sim.size.width
        for k in boats.indices {
            var b = boats[k]
            b.alpha = min(1, b.alpha + dt * 3)
            if b.sinking >= 0 {
                b.sinking += dt
                b.alpha = max(0, 1 - b.sinking / 1.5)
                boats[k] = b
                continue
            }
            if sim.waterLevel < 40 {
                // Se queda sin agua: se hunde.
                boats[k] = b
                sink(k)
                continue
            }
            let id = b.id
            let crew = fighters.contains { $0.ground == .boat(id) && !$0.dead }
            let swimming = fighters.contains { $0.hero && $0.ground == .water }
            if !crew && swimming && b.x > 0 && b.x < width {
                // Vacía: se queda a la deriva para que el protagonista pueda subir.
                b.vx += (b.facing * 15 - b.vx) * min(1, dt * 1.5)
            } else if !crew {
                // Sin tripulación, se marcha a toda velocidad.
                b.vx += b.facing * 200 * dt
            } else if b.x > width * 0.1 && b.x < width * 0.9 {
                // Ya dentro, patrulla despacio y da la vuelta antes de salirse.
                b.vx += (b.facing * 45 - b.vx) * min(1, dt * 0.8)
                if (b.x < width * 0.12 && b.vx < 0) || (b.x > width * 0.88 && b.vx > 0) { b.vx = -b.vx }
            }
            b.x += b.vx * dt
            b.wake -= dt
            if b.wake <= 0 {
                b.wake = 0.08
                sim.addSplash(x: b.x - b.facing * 38 * Self.boatScale, y: sim.waterLevel, onWater: true)
            }
            boats[k] = b
        }
        let gone = Set(boats.filter { $0.sinking > 1.5 || $0.x < -120 || $0.x > width + 120 }.map(\.id))
        if !gone.isEmpty {
            boats.removeAll { gone.contains($0.id) }
            fighters.removeAll { f in
                if case .boat(let id)? = f.ground { return gone.contains(id) }
                return false
            }
        }
    }

    private func cleanUp() {
        let width = sim.size.width
        fighters.removeAll { f in
            if f.hero { return false }
            if f.dead && f.alpha <= 0.01 && f.moveTime > 0.3 { return true }
            return f.x < -120 || f.x > width + 120 || f.y < -100
        }
    }
}
