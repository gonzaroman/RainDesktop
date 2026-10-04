import AppKit
import QuartzCore

/// Anima la simulación de una pantalla y la pinta con `RainRenderer`.
///
/// La ventana está por encima de las ventanas normales, pero cada forma lleva una profundidad:
/// - la lluvia en caída libre queda detrás de todas las ventanas;
/// - el agua posada en la ventana *k* solo la tapan las ventanas que hay delante de *k*.
final class RainView: NSView {
    private let sim = RainSimulation()
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
        sim.step(dt: CGFloat(dt))
        if sim.didStrike { onLightning?() }

        // Con una ventana a pantalla completa no hay nada que ver: se limpia una vez y se deja de pintar.
        if fullyCovered {
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
                let width = 1.6 + 2.6 * st.strength
                let alpha = 0.2 + 0.4 * min(1, st.strength * 1.5)
                let seed: CGFloat = isLeft ? 0 : 2.1
                func wobble(_ y: CGFloat) -> CGFloat {
                    sin(y * 0.045 + sim.time * 1.6 + seed) * 0.7 * min(1, (f.maxY - r - y) / 30)
                }
                // Cada tramo lleva un halo suave y un núcleo más claro, para que se lea como agua.
                func water(_ a: CGPoint, _ b: CGPoint) {
                    add(.segment, a, b, width: width + 2.4, alpha: alpha * 0.3, depth: UInt32(k))
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
            add(.ring, center, radii, width: 0.9, alpha: 0.45 * (1 - t), depth: depth(s.window))
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
