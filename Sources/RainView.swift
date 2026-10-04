import AppKit

// depth: 0 = delante (siempre visible), 1 = detrás (se oculta tras las ventanas)
struct Drop {
    var x: CGFloat
    var y: CGFloat
    var speed: CGFloat
    var length: CGFloat
    var alpha: CGFloat
    var depth: Int
    var mode: Int // 0 cayendo, 1 resbala arriba, 2 resbala lateral
    var slideDir: CGFloat
    var slideLife: Int
    var surfY: CGFloat
    var surfMinX: CGFloat
    var surfMaxX: CGFloat
    var surfMinY: CGFloat
    var sideX: CGFloat
}

struct Splash {
    var x: CGFloat
    var y: CGFloat
    var radius: CGFloat
    var alpha: CGFloat
}

// Micro-gota que rebota al chocar con el borde superior de una ventana
struct Bounce {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: Int
    var alpha: CGFloat
}

// Hilo de agua que baja por el lateral de una ventana
struct River {
    var x: CGFloat
    var y: CGFloat
    var anchorX: CGFloat
    var speed: CGFloat
    var width: CGFloat
    var alpha: CGFloat
    var wobble: CGFloat
    var life: Int
}

class RainView: NSView {
    var intensity: CGFloat = 0.6 { didSet { adjustDropCount() } }
    var wind: CGFloat = 0.25
    var lightningEnabled = true
    var collideEnabled = true
    var reboundLife: CGFloat = 0.6
    var obstacles: [CGRect] = [] {
        didSet {
            matchWetness(old: oldValue)
            cullStaleSlides()
        }
    }
    private var wet: [CGFloat] = []

    private var drops: [Drop] = []
    private var splashes: [Splash] = []
    private var bounces: [Bounce] = []
    private var rivers: [River] = []
    private var flashAlpha: CGFloat = 0
    private var framesUntilBolt = 600
    private var flashSecondPulse = 0
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        adjustDropCount()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = timer {
            RunLoop.current.add(t, forMode: .common)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    private func targetCount() -> Int {
        return Int(150 + 550 * intensity)
    }

    private func adjustDropCount() {
        let target = targetCount()
        if drops.count < target {
            for _ in drops.count..<target {
                drops.append(randomDrop(anyY: true))
            }
        } else if drops.count > target {
            drops = Array(drops.prefix(target))
        }
    }

    private func randomDrop(anyY: Bool) -> Drop {
        let w = bounds.width > 0 ? bounds.width : 1920
        let h = bounds.height > 0 ? bounds.height : 1080
        // 60% delante, 40% detrás (las de detrás se ocultan tras las ventanas)
        let depth = CGFloat.random(in: 0...1) < 0.4 ? 1 : 0
        return Drop(
            x: CGFloat.random(in: -100...w + 100),
            y: anyY ? CGFloat.random(in: 0...h) : h + CGFloat.random(in: 0...80),
            speed: CGFloat.random(in: 10...19),
            length: CGFloat.random(in: 20...38),
            alpha: depth == 0 ? CGFloat.random(in: 0.3...0.52) : CGFloat.random(in: 0.22...0.4),
            depth: depth,
            mode: 0, slideDir: 0, slideLife: 0, surfY: 0, surfMinX: 0, surfMaxX: 0, surfMinY: 0, sideX: 0
        )
    }

    private func respawn(_ i: Int, w: CGFloat) {
        drops[i] = randomDrop(anyY: false)
        drops[i].x = CGFloat.random(in: -100...w + 100)
    }

    private func insideAnyObstacle(_ x: CGFloat, _ y: CGFloat) -> Bool {
        for r in obstacles {
            if x >= r.minX && x <= r.maxX && y >= r.minY && y <= r.maxY {
                return true
            }
        }
        return false
    }

    // Conserva el nivel de "mojado" de cada borde aunque la lista se reordene
    private func matchWetness(old: [CGRect]) {
        var newWet = [CGFloat](repeating: 0, count: obstacles.count)
        for (ni, nr) in obstacles.enumerated() {
            var best: CGFloat = 0
            for (oi, or_) in old.enumerated() {
                if oi < wet.count && abs(nr.minX - or_.minX) < 24 && abs(nr.maxY - or_.maxY) < 24 {
                    best = max(best, wet[oi])
                }
            }
            newWet[ni] = best
        }
        wet = newWet
    }

    // Si la ventana se mueve o se cierra, las gotas que rebotaban ahí no se quedan flotando
    private func cullStaleSlides() {
        for i in drops.indices where drops[i].mode == 1 {
            let y = drops[i].surfY
            let x = drops[i].x
            var alive = false
            for r in obstacles {
                if abs(r.maxY - y) < 12 && x >= r.minX - 12 && x <= r.maxX + 12 {
                    alive = true
                    break
                }
            }
            if !alive {
                drops[i].mode = 0
                drops[i].y = y - 3
            }
        }
    }

    private func tick() {
        guard let window = window, window.isVisible else { return }
        let w = bounds.width
        let dx = wind * 7
        let useCollide = collideEnabled && !obstacles.isEmpty
        if wet.count != obstacles.count {
            wet = [CGFloat](repeating: 0, count: obstacles.count)
        }

        for i in drops.indices {
            // Sin modo deslizamiento: ninguna gota queda pegada a ventanas.
            // Las antiguas en mode 1/2 se liberan a caída normal una vez.
            if drops[i].mode == 1 || drops[i].mode == 2 {
                drops[i].mode = 0
                drops[i].y -= 3
                continue
            }

            let prevX = drops[i].x
            let prevY = drops[i].y
            let newX = prevX + dx
            let newY = prevY - drops[i].speed

            if useCollide {
                var hit = false
                for (ri, rect) in obstacles.enumerated() {
                    if prevY >= rect.maxY && newY < rect.maxY && newX >= rect.minX && newX <= rect.maxX {
                        // Mojar el borde
                        if ri < wet.count {
                            wet[ri] = min(1.0, wet[ri] + 0.02 + intensity * 0.02)
                        }
                        if drops[i].depth == 1 {
                            // Las de detrás siguen cayendo ocultas tras la ventana, sin efecto visible
                        } else {
                            // Delante: splash + micro-rebote y la gota desaparece al instante.
                            // Nada queda pegado a la ventana: imposible que se congele.
                            if splashes.count < 90 {
                                splashes.append(Splash(x: newX, y: rect.maxY + 2, radius: 1.5, alpha: 0.5))
                            }
                            spawnBounce(x: newX, y: rect.maxY + 3, dx: dx)
                            respawn(i, w: w)
                        }
                        hit = true
                        break
                    }
                    // Sin laterales: solo cuenta el borde superior
                }
                if hit { continue }
            }

            drops[i].x = newX
            drops[i].y = newY
            if drops[i].y < 4 {
                if splashes.count < 80 && drops[i].depth == 0 && Bool.random() {
                    splashes.append(Splash(x: drops[i].x, y: 6, radius: 1.5, alpha: 0.45))
                }
                respawn(i, w: w)
            }
            if drops[i].x > w + 120 { drops[i].x = -110 }
            if drops[i].x < -120 { drops[i].x = w + 110 }
        }

        // Secar bordes poco a poco
        for k in wet.indices {
            wet[k] *= 0.998
        }

        // Sin ríos laterales: lista siempre vacía para que no queden restos
        rivers.removeAll()

        // Micro-rebotes con gravedad
        for i in bounces.indices {
            bounces[i].vy -= 0.45
            bounces[i].x += bounces[i].vx + dx * 0.4
            bounces[i].y += bounces[i].vy
            bounces[i].life -= 1
            bounces[i].alpha *= 0.94
        }
        bounces.removeAll { $0.life <= 0 || $0.alpha < 0.03 }

        for i in splashes.indices {
            splashes[i].radius += 0.7
            splashes[i].alpha *= 0.8
        }
        splashes.removeAll { $0.alpha < 0.04 }

        if lightningEnabled {
            if flashSecondPulse > 0 {
                flashSecondPulse -= 1
                if flashSecondPulse == 0 {
                    // Segundo pulso del relámpago, más suave
                    flashAlpha = max(flashAlpha, CGFloat.random(in: 0.08...0.16))
                }
            } else {
                framesUntilBolt -= 1
                if framesUntilBolt <= 0 {
                    flashAlpha = CGFloat.random(in: 0.14...0.26)
                    flashSecondPulse = 6
                    framesUntilBolt = Int.random(in: 480...1200)
                }
            }
        }
        flashAlpha *= 0.90
        if flashAlpha < 0.005 { flashAlpha = 0 }

        needsDisplay = true
    }

    private func spawnBounce(x: CGFloat, y: CGFloat, dx: CGFloat) {
        guard bounces.count < 120 else { return }
        let n = Int.random(in: 2...3)
        // El slider controla la vida del rebote: 0.1s≈6f … 1.5s≈45f
        let baseLife = max(4, Int(reboundLife * 30))
        for _ in 0..<n {
            bounces.append(Bounce(
                x: x + CGFloat.random(in: -3...3),
                y: y,
                vx: CGFloat.random(in: -1.8...1.8),
                vy: CGFloat.random(in: 1.5...4.5),
                life: max(4, baseLife + Int.random(in: -4...4)),
                alpha: CGFloat.random(in: 0.4...0.65)
            ))
        }
    }

    private func maybeSpawnRiver(from rect: CGRect) {
        guard rect.width > 80 && rect.height > 80 else { return }
        let leftSide = Bool.random()
        let x = leftSide ? rect.minX + CGFloat.random(in: 1...3) : rect.maxX - CGFloat.random(in: 1...3)
        rivers.append(River(
            x: x,
            y: rect.maxY - CGFloat.random(in: 0...20),
            anchorX: x,
            speed: CGFloat.random(in: 1.0...2.6),
            width: CGFloat.random(in: 1.2...2.4),
            alpha: CGFloat.random(in: 0.35...0.6),
            wobble: CGFloat.random(in: 0...6),
            life: Int(rect.height / 2)
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if flashAlpha > 0 {
            ctx.setFillColor(NSColor(white: 1.0, alpha: flashAlpha).cgColor)
            ctx.fill(bounds)
        }

        // Bordes mojados: línea sutil en el borde superior + brillo en esquinas
        if collideEnabled {
            for (idx, rect) in obstacles.enumerated() {
                let wetness: CGFloat = idx < wet.count ? wet[idx] : 0
                if wetness > 0.05 {
                    ctx.setStrokeColor(NSColor(white: 0.95, alpha: 0.12 + wetness * 0.25).cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: rect.minX, y: rect.maxY + 1))
                    ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 1))
                    ctx.strokePath()
                    // Charcos en las esquinas
                    for cx in [rect.minX + 6, rect.maxX - 6] {
                        ctx.setFillColor(NSColor(white: 1.0, alpha: wetness * 0.35).cgColor)
                        ctx.fillEllipse(in: CGRect(x: cx - 3, y: rect.maxY - 1, width: 6, height: 4))
                    }
                }
            }
        }

        ctx.setLineCap(.round)
        let dx = wind * 7

        for drop in drops {
            // Las de detrás no se dibujan dentro de las ventanas
            if drop.mode == 0 && drop.depth == 1 && insideAnyObstacle(drop.x, drop.y) {
                continue
            }
            if drop.mode == 0 {
                // Trazo alineado al vector velocidad real para acabado profesional
                // v = (dx, -speed), longitud visual proporcional a |v|
                let vx = dx
                let vy = -drop.speed
                let mag = max(1, sqrt(vx * vx + vy * vy))
                let ux = vx / mag
                let uy = vy / mag
                let tailX = drop.x - ux * drop.length
                let tailY = drop.y - uy * drop.length
                // Halo suave + núcleo
                ctx.setStrokeColor(NSColor(white: 0.9, alpha: drop.alpha * 0.32).cgColor)
                ctx.setLineWidth(3.0)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: drop.x, y: drop.y))
                ctx.addLine(to: CGPoint(x: tailX, y: tailY))
                ctx.strokePath()

                ctx.setStrokeColor(NSColor(white: 0.93, alpha: drop.alpha).cgColor)
                ctx.setLineWidth(drop.depth == 0 ? 1.4 : 1.1)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: drop.x, y: drop.y))
                ctx.addLine(to: CGPoint(x: tailX, y: tailY))
                ctx.strokePath()
            } else if drop.mode == 1 {
                // Gota resbalando: punto brillante + estela horizontal corta
                ctx.setStrokeColor(NSColor(white: 0.95, alpha: 0.5).cgColor)
                ctx.setLineWidth(1.5)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: drop.x, y: drop.y))
                ctx.addLine(to: CGPoint(x: drop.x - drop.slideDir * 6, y: drop.y))
                ctx.strokePath()
                ctx.setFillColor(NSColor(white: 1.0, alpha: 0.65).cgColor)
                ctx.fillEllipse(in: CGRect(x: drop.x - 1.4, y: drop.y - 1.4, width: 2.8, height: 2.8))
            }
        }

        // Micro-rebotes: puntitos con brillo
        for b in bounces {
            ctx.setFillColor(NSColor(white: 1.0, alpha: b.alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: b.x - 1.1, y: b.y - 1.1, width: 2.2, height: 2.2))
        }

        for splash in splashes {
            ctx.setStrokeColor(NSColor(white: 0.9, alpha: splash.alpha).cgColor)
            ctx.setLineWidth(1.0)
            ctx.beginPath()
            ctx.addEllipse(in: CGRect(x: splash.x - splash.radius, y: splash.y - splash.radius / 3, width: splash.radius * 2, height: splash.radius * 0.7))
            ctx.strokePath()
        }
    }

    override var isOpaque: Bool { false }
}
