import AppKit
import QuartzCore

/// Anima la simulación de una pantalla y la pinta con `RainRenderer`.
///
/// La ventana está por encima de las ventanas normales, pero cada forma lleva una profundidad:
/// - la lluvia en caída libre queda detrás de todas las ventanas;
/// - el agua posada en la ventana *k* solo la tapan las ventanas que hay delante de *k*.
final class RainView: NSView {
    private let sim = RainSimulation()
    private let creatures = Creatures()
    private let renderer = RainRenderer()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    /// Franja superior que tapa todo (la barra de menús), en puntos.
    var menuBarHeight: CGFloat = 0 { didSet { rebuildOcclusion() } }

    private var shapes: [RainRenderer.Shape] = []
    private var depthOf: [UInt32: Int] = [:]
    private var fullyCovered = false
    private var clearedWhileCovered = false
    private var instances: [RainRenderer.Instance] = []

    /// Se llama cuando cae un rayo en esta pantalla.
    var onLightning: (() -> Void)?
    /// Grosor en puntos de un hilo lateral con el caudal máximo.
    private var streamWidth: CGFloat = 1.0
    /// Inundación compartida por todas las pantallas.
    var flood: FloodState?
    /// Altura máxima del agua, como fracción de la pantalla.
    static let floodMaxFraction: CGFloat = 0.85
    private var flooding = false

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        sim.size = frameRect.size
        rebuildOcclusion()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no soportado")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = renderer?.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.maximumDrawableCount = 3
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        return layer
    }

    override var isOpaque: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sim.size = newSize
        rebuildOcclusion()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private func updateDrawableSize() {
        guard let metalLayer else { return }
        let scale = backingScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    func configure(with settings: RainSettings, lightning: Bool) {
        sim.intensity = CGFloat(settings.intensity)
        sim.wind = CGFloat(settings.wind)
        sim.bounce = CGFloat(settings.bounce)
        sim.collide = settings.collide
        sim.sideCollide = settings.collide && settings.sideCollide
        sim.lightning = lightning
        streamWidth = CGFloat(settings.streamWidth)
        creatures.walkersEnabled = settings.walkers
        creatures.fishEnabled = settings.fish
    }

    /// Ventanas de esta pantalla, en coordenadas locales y ordenadas de delante a atrás.
    func setObstacles(_ obstacles: [Obstacle]) {
        guard obstacles != sim.windows else { return }
        sim.setWindows(obstacles)
        rebuildOcclusion()
    }

    // MARK: - Animación

    func startAnimating() {
        guard link == nil else { return }
        updateDrawableSize()
        let newLink = displayLink(target: self, selector: #selector(frameTick(_:)))
        // En modo de bajo consumo basta con 30 fps.
        let fps: Float = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: fps, preferred: fps)
        newLink.add(to: .main, forMode: .common)
        link = newLink
        lastTimestamp = 0
    }

    func stopAnimating() {
        link?.invalidate()
        link = nil
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60.0 : min(max(now - lastTimestamp, 0), 1.0 / 30.0)
        lastTimestamp = now
        flood?.advance(to: now)
        // El agua se queda por debajo del borde superior para que siga viéndose la lluvia.
        sim.waterLevel = (flood?.level ?? 0) * bounds.height * Self.floodMaxFraction
        updateFloodLayering()
        sim.step(dt: CGFloat(dt))
        creatures.step(dt: CGFloat(dt), sim: sim, ceiling: bounds.height - menuBarHeight)
        if sim.didStrike { onLightning?() }

        // Con una ventana a pantalla completa no hay nada que ver: se limpia una vez y se deja de pintar.
        if fullyCovered && sim.waterLevel <= 0.5 {
            guard !clearedWhileCovered else { return }
            clearedWhileCovered = true
            instances.removeAll(keepingCapacity: true)
        } else {
            clearedWhileCovered = false
            buildInstances()
        }
        guard let renderer, let metalLayer else { return }
        renderer.render(to: metalLayer, viewport: bounds.size, scale: backingScale,
                        shapes: shapes, instances: instances)
    }

    /// Mientras hay agua, la ventana sube por encima del Dock y de la barra de menús para que la
    /// inundación lo cubra todo; al vaciarse vuelve justo encima de las ventanas normales.
    private func updateFloodLayering() {
        let nowFlooding = sim.waterLevel > 0.5
        guard nowFlooding != flooding, let window else { return }
        flooding = nowFlooding
        window.level = nowFlooding ? RainWindow.floodLevel : RainWindow.rainLevel
    }

    // MARK: - Oclusión

    private func rebuildOcclusion() {
        var list: [RainRenderer.Shape] = []
        if menuBarHeight > 0 {
            list.append(Self.shape(CGRect(x: -1, y: bounds.height - menuBarHeight,
                                          width: bounds.width + 2, height: menuBarHeight + 1), radius: 0))
        }
        var depths: [UInt32: Int] = [:]
        for w in sim.windows where list.count < RainRenderer.maxShapes {
            list.append(Self.shape(w.frame, radius: Surface.radius(of: w.frame)))
            // Lo posado en esta ventana lo tapa todo lo que hay delante, incluida la barra de menús.
            depths[w.id] = list.count - 1
        }
        shapes = list
        depthOf = depths
        fullyCovered = sim.windows.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(bounds) }
    }

    private static func shape(_ f: CGRect, radius: CGFloat) -> RainRenderer.Shape {
        RainRenderer.Shape(rect: SIMD4(Float(f.minX), Float(f.minY), Float(f.maxX), Float(f.maxY)),
                           params: SIMD4(Float(radius), 0, 0, 0))
    }

    // MARK: - Formas

    private func buildInstances() {
        instances.removeAll(keepingCapacity: true)
        let background = UInt32(shapes.count)
        func depth(_ id: UInt32?) -> UInt32 { id.flatMap { depthOf[$0] }.map(UInt32.init) ?? background }

        if sim.flash > 0 {
            add(.fullscreen, .zero, .zero, width: 0, alpha: sim.flash, depth: background)
        }

        for d in sim.drops {
            let speed = max(1, (d.vx * d.vx + d.vy * d.vy).squareRoot())
            let head = CGPoint(x: d.x, y: d.y)
            let tail = CGPoint(x: d.x - d.vx / speed * d.length, y: d.y - d.vy / speed * d.length)
            if d.near {
                add(.segment, head, tail, width: 2.6, alpha: d.alpha * 0.3, depth: background)
                add(.segment, head, tail, width: 1.1, alpha: d.alpha, depth: background)
            } else {
                add(.segment, head, tail, width: 0.8, alpha: d.alpha, depth: background)
            }
        }

        for (id, wet) in sim.wetness where wet > 0.05 {
            guard let k = depthOf[id], let f = sim.frame(of: id) else { continue }
            let r = Surface.radius(of: f)
            add(.segment, CGPoint(x: f.minX + r, y: f.maxY + 0.5), CGPoint(x: f.maxX - r, y: f.maxY + 0.5),
                width: 1, alpha: wet * 0.25, depth: UInt32(k))
        }

        // Hilos de agua por los laterales: dan la vuelta a la esquina, bajan ondulando y gotean.
        for (id, pair) in sim.streams {
            guard let k = depthOf[id], let f = sim.frame(of: id) else { continue }
            let r = Surface.radius(of: f)
            for (isLeft, st) in [(true, pair.left), (false, pair.right)] where st.length > 1 {
                let edgeX = isLeft ? f.minX - 0.8 : f.maxX + 0.8
                let inward: CGFloat = isLeft ? 1 : -1
                // Con poco caudal el hilo baja al 38 % del grosor elegido.
                let width = streamWidth * (0.38 + 0.62 * st.strength)
                let alpha = 0.2 + 0.4 * min(1, st.strength * 1.5)
                let seed: CGFloat = isLeft ? 0 : 2.1
                func wobble(_ y: CGFloat) -> CGFloat {
                    sin(y * 0.045 + sim.time * 1.6 + seed) * 0.7 * min(1, (f.maxY - r - y) / 30)
                }
                // Cada tramo lleva un halo suave y un núcleo más claro, para que se lea como agua.
                func water(_ a: CGPoint, _ b: CGPoint) {
                    add(.segment, a, b, width: width + streamWidth * 0.57, alpha: alpha * 0.3, depth: UInt32(k))
                    add(.segment, a, b, width: width, alpha: alpha, depth: UInt32(k))
                }
                // Vuelta a la esquina redondeada.
                water(CGPoint(x: edgeX + inward * r * 0.45, y: f.maxY - r * 0.12), CGPoint(x: edgeX, y: f.maxY - r))
                // Bajada por el lateral, en tramos con un ligero ondulado.
                let top = f.maxY - r
                let bottom = top - st.length
                var y = top
                while y > bottom {
                    let next = max(bottom, y - 12)
                    water(CGPoint(x: edgeX + wobble(y), y: y), CGPoint(x: edgeX + wobble(next), y: next))
                    y = next
                }
                // Al llegar abajo, el chorro asoma por debajo del borde antes de romperse en gotas.
                if st.length >= f.height - r - 1 && st.strength > 0.04 {
                    water(CGPoint(x: edgeX, y: f.minY), CGPoint(x: edgeX, y: f.minY - 4 - 8 * st.strength))
                }
                // Gota colgando abajo que crece hasta soltarse.
                if st.charge > 0.05 {
                    add(.ellipse, CGPoint(x: edgeX, y: f.minY - 1 - st.charge * 2.5),
                        CGPoint(x: 1 + st.charge * 0.9, y: 1.2 + st.charge * 1.7),
                        width: 0, alpha: 0.4 + 0.3 * st.charge, depth: UInt32(k))
                }
            }
        }

        for s in sim.splashes {
            let t = s.age / RainSimulation.splashDuration
            let rx = 2 + t * 7
            let center = s.vertical ? CGPoint(x: s.x, y: s.y) : CGPoint(x: s.x, y: s.y + rx * 0.23)
            let radii = s.vertical ? CGPoint(x: rx * 0.35, y: rx) : CGPoint(x: rx, y: rx * 0.35)
            add(.ring, center, radii, width: 0.9, alpha: 0.45 * (1 - t), depth: s.onWater ? 0 : depth(s.window))
        }

        for d in sim.droplets {
            let fadeStart = d.life * 0.6
            let fade = d.age > fadeStart ? max(0, 1 - (d.age - fadeStart) / (d.life - fadeStart)) : 1
            let speed = (d.vx * d.vx + d.vy * d.vy).squareRoot()
            if d.drip && speed > 120 {
                // El agua que cae de una ventana se estira en la dirección de caída.
                let stretch = min(0.03, 26 / speed)
                add(.segment, CGPoint(x: d.x, y: d.y), CGPoint(x: d.x - d.vx * stretch, y: d.y - d.vy * stretch),
                    width: d.radius * 1.7, alpha: 0.55 * fade, depth: depth(d.window))
            } else {
                add(.ellipse, CGPoint(x: d.x, y: d.y), CGPoint(x: d.radius, y: d.radius),
                    width: 0, alpha: 0.6 * fade, depth: depth(d.window))
            }
        }

        for b in sim.beads {
            let k = depth(b.window)
            if b.edge == .top {
                let fade = min(1, (b.life - b.age) / 0.6)
                add(.ellipse, CGPoint(x: b.x, y: b.y + b.radius * 0.4), CGPoint(x: b.radius, y: b.radius * 0.8),
                    width: 0, alpha: 0.65 * fade, depth: k)
            } else {
                let x = b.x + sin(b.age * 5 + b.phase) * 0.4
                add(.segment, CGPoint(x: x, y: b.y), CGPoint(x: b.x, y: b.y + min(18, b.age * 70)),
                    width: 0.9, alpha: 0.22, depth: k)
                add(.ellipse, CGPoint(x: x, y: b.y), CGPoint(x: b.radius * 0.8, y: b.radius * 1.1),
                    width: 0, alpha: 0.6, depth: k)
            }
        }

        // Antes que el agua, para que tape a los monigotes que se hunden.
        addWalkers()
        addWater()
    }

    private func addWater() {
        let level = sim.waterLevel
        guard level > 0.5 else { return }
        // Olas más altas cuanto más llueve; casi planas al empezar a subir.
        let amplitude = min(level * 0.5, 3 + 5 * sim.intensity)
        add(.water, CGPoint(x: level, y: sim.time), CGPoint(x: 0, y: amplitude), width: 0, alpha: 1, depth: 0)

        // Burbujas: aro transparente con un brillo arriba a la izquierda.
        for b in sim.bubbles {
            let fadeIn = min(1, b.age / 0.3)
            add(.ring, CGPoint(x: b.x, y: b.y), CGPoint(x: b.radius, y: b.radius),
                width: max(0.7, b.radius * 0.22), alpha: 0.5 * fadeIn, depth: 0)
            add(.ellipse, CGPoint(x: b.x - b.radius * 0.35, y: b.y + b.radius * 0.4),
                CGPoint(x: b.radius * 0.28, y: b.radius * 0.22), width: 0, alpha: 0.7 * fadeIn, depth: 0)
        }
        addFish()
    }

    /// Monigote con paraguas: pies en (x, y), unos 30 pt de alto.
    private func addWalkers() {
        let background = UInt32(shapes.count)
        for w in creatures.walkers {
            let k: UInt32
            let walking: Bool
            if case .walking(let id, _) = w.state {
                k = depthOf[id].map(UInt32.init) ?? background
                walking = true
            } else {
                // Al caer se queda en la capa de la ventana de la que viene, delante de ella.
                k = w.layer.flatMap { depthOf[$0] }.map(UInt32.init) ?? background
                walking = false
            }
            let alpha = 0.5 * w.alpha
            let x = w.x, y = w.y
            let d = w.direction

            // Piernas: andando se balancean; colgando, casi juntas.
            let swing = walking ? sin(w.phase) * 3.5 : sin(sim.time * 3 + w.phase) * 1.2
            let hip = CGPoint(x: x, y: y + 9)
            add(.segment, hip, CGPoint(x: x + swing, y: y), width: 1.4, alpha: alpha, depth: k)
            add(.segment, hip, CGPoint(x: x - swing, y: walking ? y : y + 0.8), width: 1.4, alpha: alpha, depth: k)
            // Tronco, cabeza y el brazo que sujeta el paraguas.
            add(.segment, hip, CGPoint(x: x, y: y + 17), width: 1.7, alpha: alpha, depth: k)
            add(.ellipse, CGPoint(x: x, y: y + 20.5), CGPoint(x: 2.7, y: 2.7), width: 0, alpha: alpha, depth: k)
            let hand = CGPoint(x: x + d * 3.5, y: y + 15)
            add(.segment, CGPoint(x: x, y: y + 16), hand, width: 1.2, alpha: alpha, depth: k)

            // Paraguas: se inclina con el viento; al caer, más abierto y con el mango hacia el movimiento.
            let tilt = walking ? sim.wind * 4 : max(-6, min(6, -w.vx * 0.08))
            let top = CGPoint(x: hand.x + tilt, y: y + 30)
            let radii = walking ? CGPoint(x: 12, y: 7) : CGPoint(x: 13.5, y: 8.5)
            add(.segment, CGPoint(x: hand.x, y: hand.y - 1.5), top, width: 0.9, alpha: alpha, depth: k)
            add(.dome, top, radii, width: 0, alpha: alpha * 0.85, depth: k)
            add(.segment, CGPoint(x: top.x - radii.x, y: top.y), CGPoint(x: top.x + radii.x, y: top.y),
                width: 1, alpha: alpha * 0.6, depth: k)
            add(.segment, CGPoint(x: top.x, y: top.y + radii.y), CGPoint(x: top.x, y: top.y + radii.y + 2.5),
                width: 1, alpha: alpha, depth: k)
        }
    }

    /// Peces: cuerpo, cola que se mueve, aleta y un brillo en el ojo. Se ven a través del agua.
    private func addFish() {
        for f in creatures.fish {
            let s: CGFloat = f.vx >= 0 ? 1 : -1
            // Al darse la vuelta el cuerpo se ve de frente y se estrecha.
            let turn = max(0.35, min(1, abs(f.vx) / f.speed))
            let len = f.size * turn
            let alpha = 0.42 * f.alpha
            add(.ellipse, CGPoint(x: f.x, y: f.y), CGPoint(x: len, y: f.size * 0.42), width: 0, alpha: alpha, depth: 0)
            let wag = sin(sim.time * 8 + f.phase) * f.size * 0.18
            let base = CGPoint(x: f.x - s * len * 0.85, y: f.y)
            for side: CGFloat in [1, -1] {
                add(.segment, base, CGPoint(x: f.x - s * len * 1.55, y: f.y + side * f.size * 0.42 + wag),
                    width: f.size * 0.22, alpha: alpha, depth: 0)
            }
            add(.segment, CGPoint(x: f.x - s * len * 0.1, y: f.y + f.size * 0.36),
                CGPoint(x: f.x - s * len * 0.5, y: f.y + f.size * 0.62), width: f.size * 0.16, alpha: alpha, depth: 0)
            add(.ellipse, CGPoint(x: f.x + s * len * 0.55, y: f.y + f.size * 0.1),
                CGPoint(x: f.size * 0.09, y: f.size * 0.09), width: 0, alpha: 0.85 * f.alpha, depth: 0)
        }
    }

    private func add(_ kind: RainRenderer.Kind, _ a: CGPoint, _ b: CGPoint,
                     width: CGFloat, alpha: CGFloat, depth: UInt32) {
        guard alpha > 0.004 else { return }
        instances.append(RainRenderer.Instance(
            a: SIMD2(Float(a.x), Float(a.y)),
            b: SIMD2(Float(b.x), Float(b.y)),
            width: Float(width),
            alpha: Float(min(alpha, 1)),
            kind: kind.rawValue,
            depth: depth
        ))
    }
}
