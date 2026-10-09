import Metal
import QuartzCore
import simd

/// Pinta la lluvia con Metal: cada forma es un quad instanciado cuyo borde se suaviza con una
/// función de distancia. El recorte detrás de las ventanas también se hace en el shader:
/// un fragmento con profundidad *k* se descarta si cae dentro de alguna de las *k* ventanas de delante.
final class RainRenderer {
    enum Kind: UInt32 {
        case segment = 0   // a → b, grosor `width`
        case ellipse = 1   // centro a, radios b
        case ring = 2      // centro a, radios b, grosor `width`
        case fullscreen = 3
        case water = 4     // a = (nivel, tiempo), b.y = altura de las olas
        case dome = 5      // mitad superior de la elipse de centro a y radios b (un paraguas)
    }

    /// Bits de `Instance.kind` por encima de la forma.
    enum Flag {
        /// Pinta en negro en vez del color de la lluvia (bordes de los personajes).
        static let ink: UInt32 = 1 << 8
        /// `dome` boca abajo: la mitad inferior de la elipse (el casco de una lancha).
        static let flipped: UInt32 = 1 << 9
    }

    /// Mismo diseño de memoria que `Instance` en el shader (32 bytes).
    struct Instance {
        var a: SIMD2<Float>
        var b: SIMD2<Float>
        var width: Float
        var alpha: Float
        var kind: UInt32
        var depth: UInt32
    }

    /// Ventana para el recorte: (minX, minY, maxX, maxY) y radio de las esquinas.
    struct Shape {
        var rect: SIMD4<Float>
        var params: SIMD4<Float>
    }

    private struct Uniforms {
        var viewport: SIMD2<Float>
        var scale: Float
        var shapeCount: UInt32
    }

    static let maxShapes = 32
    private static let maxInstances = 32768
    private static let framesInFlight = 3

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var buffers: [MTLBuffer] = []
    private var bufferIndex = 0
    private let inFlight = DispatchSemaphore(value: framesInFlight)

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "rain_vertex")
            desc.fragmentFunction = library.makeFunction(name: "rain_fragment")
            let color = desc.colorAttachments[0]!
            color.pixelFormat = .bgra8Unorm
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("RainDesktop: no se pudo preparar Metal: \(error)")
            return nil
        }
        let length = MemoryLayout<Instance>.stride * Self.maxInstances
        for _ in 0..<Self.framesInFlight {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
            buffers.append(buffer)
        }
    }

    /// Pinta un fotograma. Si la GPU va atrasada, se salta el fotograma en vez de bloquear.
    func render(to layer: CAMetalLayer, viewport: CGSize, scale: CGFloat,
                shapes: [Shape], instances: [Instance]) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }

        let count = min(instances.count, Self.maxInstances)
        let buffer = buffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % Self.framesInFlight
        if count > 0 {
            instances.withUnsafeBytes { raw in
                buffer.contents().copyMemory(from: raw.baseAddress!, byteCount: count * MemoryLayout<Instance>.stride)
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store

        if let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
            if count > 0 {
                var uniforms = Uniforms(
                    viewport: SIMD2(Float(viewport.width), Float(viewport.height)),
                    scale: Float(scale),
                    shapeCount: UInt32(min(shapes.count, Self.maxShapes))
                )
                var shapeData = Array(shapes.prefix(Self.maxShapes))
                if shapeData.isEmpty { shapeData.append(Shape(rect: .zero, params: .zero)) }
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&shapeData, length: MemoryLayout<Shape>.stride * shapeData.count, index: 2)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
            }
            encoder.endEncoding()
        }

        let semaphore = inFlight
        commands.addCompletedHandler { _ in semaphore.signal() }
        commands.present(drawable)
        commands.commit()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Instance { float2 a; float2 b; float width; float alpha; uint kind; uint depth; };
    struct Shape { float4 rect; float4 params; };
    struct Uniforms { float2 viewport; float scale; uint shapeCount; };

    struct VOut {
        float4 position [[position]];
        float2 p;
        uint iid [[flat]];
    };

    constant float3 tint = float3(0.86, 0.91, 1.0);
    constant float3 ink = float3(0.02, 0.02, 0.05);

    vertex VOut rain_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                            const device Instance* inst [[buffer(0)]],
                            constant Uniforms& u [[buffer(1)]]) {
        Instance s = inst[iid];
        uint kind = s.kind & 0xFFu;
        float pad = 1.5 / u.scale + s.width;
        float2 lo, hi;
        if (kind == 0) { lo = min(s.a, s.b) - pad; hi = max(s.a, s.b) + pad; }
        else if (kind == 3) { lo = float2(0.0); hi = u.viewport; }
        else if (kind == 4) { lo = float2(0.0); hi = float2(u.viewport.x, s.a.x + s.b.y * 2.0 + pad); }
        else { lo = s.a - s.b - pad; hi = s.a + s.b + pad; }
        float2 p = mix(lo, hi, float2(float(vid & 1), float(vid >> 1)));
        VOut o;
        o.position = float4(p / u.viewport * 2.0 - 1.0, 0.0, 1.0);
        o.p = p;
        o.iid = iid;
        return o;
    }

    float roundedRectDistance(float2 p, float4 r, float radius) {
        float2 c = (r.xy + r.zw) * 0.5;
        float2 h = (r.zw - r.xy) * 0.5;
        float2 q = abs(p - c) - h + radius;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    }

    fragment float4 rain_fragment(VOut in [[stage_in]],
                                  const device Instance* inst [[buffer(0)]],
                                  constant Uniforms& u [[buffer(1)]],
                                  constant Shape* shapes [[buffer(2)]]) {
        Instance s = inst[in.iid];
        uint kind = s.kind & 0xFFu;
        float2 p = in.p;
        uint depth = min(s.depth, u.shapeCount);
        for (uint i = 0; i < depth; i++) {
            if (roundedRectDistance(p, shapes[i].rect, shapes[i].params.x) < 0.0) discard_fragment();
        }
        if (kind == 4) {
            // Agua: superficie con tres trenes de olas, color según la profundidad,
            // reflejos (cáusticas) en movimiento y una franja brillante en la superficie.
            float t = s.a.y;
            float amp = s.b.y;
            float surface = s.a.x + amp * (0.6 * sin(p.x * 0.012 + t * 1.3)
                                         + 0.3 * sin(p.x * 0.031 - t * 2.1)
                                         + 0.1 * sin(p.x * 0.070 + t * 3.3));
            float dist = surface - p.y;
            float cover = clamp(dist * u.scale + 0.5, 0.0, 1.0);
            if (cover <= 0.0) discard_fragment();
            float deep = clamp(dist / 700.0, 0.0, 1.0);
            float3 col = mix(float3(0.30, 0.55, 0.95), float3(0.04, 0.14, 0.42), deep);
            float c = sin(p.x * 0.021 + t * 0.9) + sin(p.y * 0.027 - t * 1.2)
                    + sin((p.x - p.y) * 0.016 + t * 0.6) + sin((p.x + p.y) * 0.011 - t * 0.8);
            c = pow(clamp(1.0 - abs(c) * 0.5, 0.0, 1.0), 6.0);
            col += float3(0.5, 0.7, 1.0) * c * 0.25 * (1.0 - deep);
            float a = 0.18 + 0.30 * deep + c * 0.06;
            float band = clamp(1.0 - dist / 3.0, 0.0, 1.0);
            col = mix(col, float3(0.85, 0.93, 1.0), band * 0.8);
            a = max(a, band * 0.75) * cover * s.alpha;
            return float4(col * a, a);
        }
        float d;
        if (kind == 0) {
            float2 ba = s.b - s.a;
            float t = clamp(dot(p - s.a, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
            d = length(p - s.a - ba * t) - s.width * 0.5;
        } else if (kind == 1) {
            d = (length((p - s.a) / s.b) - 1.0) * min(s.b.x, s.b.y);
        } else if (kind == 2) {
            d = abs((length((p - s.a) / s.b) - 1.0) * min(s.b.x, s.b.y)) - s.width * 0.5;
        } else if (kind == 5) {
            float cut = (s.kind & 512u) != 0u ? p.y - s.a.y : s.a.y - p.y;
            d = max((length((p - s.a) / s.b) - 1.0) * min(s.b.x, s.b.y), cut);
        } else {
            d = -1.0;
        }
        float a = s.alpha * clamp(0.5 - d * u.scale, 0.0, 1.0);
        if (a < 0.002) discard_fragment();
        float3 color = kind == 3 ? float3(1.0) : ((s.kind & 256u) != 0u ? ink : tint);
        return float4(color * a, a);
    }
    """
}
