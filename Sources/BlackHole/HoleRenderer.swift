import Metal
import QuartzCore

/// Kara deliğin o anki görünüşü. Uzunluklar piksel cinsindendir, y aşağı doğrudur.
struct HoleLook {
    var size = SIMD2<Float>(0, 0)
    var center = SIMD2<Float>(0, 0)
    var rs: Float = 36              // olay ufkunun yarıçapı
    var time: Float = 0
    var spin: Float = 1             // diskin dönüş hızı
    var pull: Float = 0             // 0...1, dosya sürüklenince çekim alanı büyür
    var tint = SIMD3<Float>(0.62, 0.48, 1)
    var tintAmount: Float = 0
    var pulse: Float = 0            // işlenirken titreşim
    var cursor = SIMD2<Float>(0, 0)
    var cursorOn: Float = 0
    var burst: Float = -1           // fırlatma dalgası (0...1)
    var alpha: Float = 1

    var packed: [SIMD4<Float>] {
        [SIMD4(size.x, size.y, center.x, center.y),
         SIMD4(rs, time, spin, pull),
         SIMD4(tint.x, tint.y, tint.z, tintAmount),
         SIMD4(pulse, cursor.x, cursor.y, cursorOn),
         SIMD4(burst, alpha, 0, 0)]
    }
}

/// Işığı büken birikim diski, foton halkası ve karanlık çekirdek. Tek bir tam ekran üçgenle çizilir.
final class HoleRenderer {
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct VO { float4 p [[position]]; };
    vertex VO holeVertex(uint i [[vertex_id]]) {
        float2 v[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        VO o; o.p = float4(v[i], 0, 1); return o;
    }
    float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
    float noise(float2 p) {
        float2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
        float a = hash(i), b = hash(i + float2(1, 0)), c = hash(i + float2(0, 1)), d = hash(i + float2(1, 1));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }
    float fbm(float2 p) {
        float s = 0.0, a = 0.5;
        for (int k = 0; k < 4; k++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
        return s;
    }
    // Açı üzerinde dikiş olmasın diye gürültü daire üzerinde örneklenir.
    float ringNoise(float r, float ang, float twist, float rs, float as) {
        float2 q = float2(cos(ang + twist), sin(ang + twist)) * as;
        return fbm(float2(r * rs, 0.0) + q * 1.7 + float2(q.y, q.x) * 0.6);
    }
    fragment float4 holeFragment(VO in [[stage_in]], constant float4* u [[buffer(0)]]) {
        float2 c = u[0].zw;
        float rs = u[1].x, t = u[1].y, spin = u[1].z, pull = u[1].w;
        float3 tint = u[2].rgb; float tintAmt = u[2].a;
        float pulse = u[3].x; float2 cur = u[3].yz; float curOn = u[3].w;
        float burst = u[4].x, alpha = u[4].y;

        float2 p = (in.p.xy - c) / rs; p.y = -p.y;
        float r = length(p);
        float ang = atan2(p.y, p.x);
        float3 warm = float3(1.0, 0.90, 0.85);
        float3 hot = mix(warm, tint, tintAmt);
        float throb = pulse * (0.5 + 0.5 * sin(t * 16.0));
        float swell = 1.0 + pull * 0.35 + throb * 0.12;
        float3 col = float3(0.0); float a = 0.0;

        // Dış parıltı: çekim alanı büyüdükçe genişler
        float g = exp(-max(r - 1.0, 0.0) * (1.35 - pull * 0.55)) * (0.30 + 0.28 * pull + 0.25 * throb);
        col += hot * g * 0.6; a = max(a, g * 0.6);

        // Diskin arka yüzü ışık bükülmesiyle deliğin üstünde ve altında halka olarak görünür
        float upper = smoothstep(-0.55, 0.55, p.y / max(r, 0.001));
        float thick = mix(0.36, 1.2, upper) * swell;
        float inner = 1.09;
        float hb = smoothstep(inner - 0.03, inner + 0.07, r) * (1.0 - smoothstep(inner + thick * 0.3, inner + thick, r));
        float flow = ringNoise(r, ang, -t * spin * 0.9 / max(r, 0.6), 7.0, 2.2);
        float halo = hb * (0.6 + 0.9 * flow) * (0.85 + 0.45 * upper);
        col += hot * halo; a = max(a, min(1.0, halo));

        // Foton halkası
        float ring = exp(-pow((r - 1.03) / 0.022, 2.0)) * (0.95 + 0.4 * throb);
        col += float3(1.0, 0.98, 0.96) * ring; a = max(a, ring);

        // Olay ufku
        float shadow = 1.0 - smoothstep(0.965, 1.005, r);
        col *= (1.0 - shadow); a = max(a, shadow);

        // Önden geçen ince disk; deliğin arkasında kalan yarısı görünmez
        float k = 0.075 * (1.0 + pull * 0.3);
        float2 dp = float2(p.x, p.y / k);
        float rd = length(dp);
        float dang = atan2(dp.y, dp.x);
        float band = smoothstep(1.15, 1.6, rd) * (1.0 - smoothstep(3.6 * swell, 6.2 * swell, rd));
        float behind = step(0.0, p.y) * (1.0 - smoothstep(0.96, 1.02, r));
        float df = ringNoise(rd, dang, -t * spin * 1.4 / max(rd, 0.7), 5.0, 1.6);
        float dop = 1.0 + 0.4 * (-dp.x / max(rd, 0.5));
        float disk = band * (0.4 + 0.95 * df) * dop * (1.0 - behind);
        float wisp = smoothstep(0.42, 0.9, ringNoise(rd * 0.6, dang, -t * spin * 0.4 / max(rd, 1.0), 2.4, 1.1));
        float outer = smoothstep(3.4, 5.0, rd) * (1.0 - smoothstep(5.4, 9.0, rd)) * wisp * 0.65 * (1.0 - behind);
        float dA = clamp(disk + outer, 0.0, 1.0);
        float3 dcol = hot * (disk + outer);
        col = dcol + col * (1.0 - dA); a = dA + a * (1.0 - dA);

        // Sürüklenen dosyaya doğru uzanan çekim akıntısı
        if (curOn > 0.5) {
            float2 q = (cur - c) / rs; q.y = -q.y;
            float h = clamp(dot(p, q) / max(dot(q, q), 0.001), 0.0, 1.0);
            float2 bend = float2(-q.y, q.x) * sin(h * 3.14159) * 0.18;
            float d = length(p - q * h - bend);
            float w = 0.04 + 0.22 * h;
            float s = exp(-d * d / (w * w)) * (0.35 + 0.9 * noise(float2(h * 14.0 + t * 7.0, d * 5.0)))
                      * smoothstep(0.0, 0.2, h) * step(1.0, r) * pull;
            col += hot * s * 0.9; a = max(a, s * 0.9);
        }

        // Fırlatma dalgası
        if (burst >= 0.0 && burst < 1.0) {
            float br = 1.0 + burst * 4.8;
            float bw = exp(-pow((r - br) / (0.12 + burst * 0.25), 2.0)) * (1.0 - burst) * 0.9;
            col += hot * bw; a = max(a, bw);
        }
        col = min(col, float3(a));
        return float4(col, a) * alpha;
    }
    """

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let inFlight = DispatchSemaphore(value: 3)

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "holeVertex")
        d.fragmentFunction = library.makeFunction(name: "holeFragment")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func draw(_ look: HoleLook, to texture: MTLTexture, drawable: MTLDrawable?, wait: Bool = false) {
        inFlight.wait()
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        var u = look.packed
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<SIMD4<Float>>.stride * u.count, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        if let drawable { cmd.present(drawable) }
        let sem = inFlight
        cmd.addCompletedHandler { _ in sem.signal() }
        cmd.commit()
        if wait { cmd.waitUntilCompleted() }
    }
}
