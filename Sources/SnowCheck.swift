import AppKit
import Metal

/// Kar fiziğini ekran açmadan, hızlandırılmış zamanla dener.
enum SnowCheck {
    private static var failures = 0
    private static let dt: Float = 1.0 / 60

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    private static func run(_ e: SnowEngine, seconds: Float, windows: [SnowWindow]) {
        var poll: Float = 0
        for _ in 0..<Int(seconds * 60) {
            poll += dt
            if poll >= 0.125 { e.apply(windows: windows, dt: poll); poll = 0 }
            e.step(dt)
        }
    }

    private static func settle(_ e: SnowEngine, seconds: Float, windows: [SnowWindow]) {
        let keep = e.intensity
        e.intensity = -0.12   // yeni kar yağmasın
        run(e, seconds: seconds, windows: windows)
        e.intensity = keep
    }

    private static func f(_ v: Float) -> String { String(format: "%.0f", v) }

    static func run(output: URL?) -> Int32 {
        if let output { try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let main = CGRect(x: 240, y: 170, width: 760, height: 480)
        let side = CGRect(x: 1040, y: 420, width: 340, height: 300)
        let wins = [SnowWindow(id: 1, frame: main), SnowWindow(id: 2, frame: side)]

        // 1. Birikme ve sınır
        let e = SnowEngine(width: 1470, height: 956)
        e.intensity = 1
        e.apply(windows: wins, dt: 0.1); e.apply(windows: wins, dt: 0.1)
        // Yağışın başı: çizgi değil, ayrı ayrı yuvarlak kümeler
        let early = SnowEngine(width: 1470, height: 956)
        early.apply(windows: wins, dt: 0.1)
        run(early, seconds: 14, windows: wins)
        let bed = early.ledges[1]!.bed
        let held = bed.caps.indices.filter { bed.caps[$0] > 0 }
        let covered = held.filter { bed.h[$0] > 0 }.count
        var mounds = 0
        for i in held.dropFirst() where bed.h[i] > 0 && bed.h[i - 1] <= 0 { mounds += 1 }
        check("ilk kar çizgi değil, ayrı kümeler oluşturur", mounds >= 8 && Float(covered) / Float(held.count) < 0.75,
              "\(mounds) küme, %\(covered * 100 / held.count) kaplama")
        render(early, wins, output, "0-ilk-kar.png")

        run(e, seconds: 40, windows: wins)
        check("kar taneleri küçüktür", e.particles.filter { $0.kind == .flake && $0.lobes == 1 }.allSatisfy { $0.r <= 1.25 })
        check("havada değen taneler birleşip büyür", e.mergedFlakes > 20, "\(e.mergedFlakes) birleşme")
        check("kar pencerenin üstünde birikir", (e.ledges[1]?.mass ?? 0) > 50, "kütle \(f(e.ledges[1]?.mass ?? 0))")
        check("kar ekranın altında birikir", e.groundMass > 50, "kütle \(f(e.groundMass))")
        render(e, wins, output, "1-yagis.png")

        let began = CACurrentMediaTime()
        run(e, seconds: 900, windows: wins)
        let ms = (CACurrentMediaTime() - began) / (900 * 60) * 1000
        let ledgeMax = e.ledges.values.flatMap(\.h).max() ?? 0
        check("pencerede birikme sınırı aşılmaz", ledgeMax <= e.ledgeLimitNow + 0.01 && ledgeMax > e.ledgeLimitNow * 0.6, "en yüksek \(f(ledgeMax)) / \(f(e.ledgeLimitNow))")
        let groundMax = e.ground.max() ?? 0
        check("zeminde birikme sınırı aşılmaz", groundMax <= e.groundLimitNow + 0.01 && groundMax > e.groundLimitNow * 0.6, "en yüksek \(f(groundMax)) / \(f(e.groundLimitNow))")
        let m1 = e.ledges[1]!.mass
        run(e, seconds: 120, windows: wins)
        check("sınıra gelince daha fazla birikmez", abs(e.ledges[1]!.mass - m1) < m1 * 0.06, "\(f(m1)) → \(f(e.ledges[1]!.mass))")
        let full = e.ledges[1]!
        let corners = full.bed.h.indices.filter { min($0, full.bed.h.count - 1 - $0) < Int(SnowLedge.holdInset) }
        check("yuvarlak köşelerde havada kar kalmaz", corners.allSatisfy { full.bed.h[$0] == 0 })
        let surface = Array(full.bed.surface()[100..<660])
        var peaks: [Int] = []
        for i in 6..<(surface.count - 6) where surface[i] > surface[i - 6] && surface[i] >= surface[i + 6] && surface[i] >= surface[i - 1] && surface[i] >= surface[i + 1] { peaks.append(i) }
        let spacing = Float(surface.count) / Float(max(peaks.count, 1))
        let mean = surface.reduce(0, +) / Float(surface.count)
        let spread = (surface.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(surface.count)).squareRoot()
        check("kar yüzeyi top top değil, geniş topaklıdır", spacing >= 9 && spacing <= 60, String(format: "topak aralığı %.0f nokta", spacing))
        check("kar yüzeyi düz çizgi değildir", spread > 0.6, String(format: "dalga %.1f nokta", spread))
        check("taneciklerin boyutu farklıdır", Set(full.bed.grains.map { Int($0.r * 2) }).count >= 3)
        check("hiçbir tanecik havada durmaz", full.bed.floatingCount == 0 && e.ledges[2]!.bed.floatingCount == 0)
        check("kare başına simülasyon süresi düşük", ms < 2, String(format: "%.2f ms", ms))
        render(e, wins, output, "2-birikmis.png")

        // 2. Yavaş hareket
        let slow = freshLoaded(wins)
        let before = slow.ledges[1]!.mass
        var frame = main
        for _ in 0..<180 {
            frame.origin.x += 0.33
            slow.apply(windows: [SnowWindow(id: 1, frame: frame), wins[1]], dt: dt)
            slow.step(dt)
        }
        check("yavaş taşınan pencerede kar durur", slow.ledges[1]!.mass > before * 0.85, "\(f(before)) → \(f(slow.ledges[1]!.mass))")

        // 3. Sallama
        let shake = freshLoaded(wins)
        let loaded = shake.ledges[1]!.mass
        frame = main
        var peak = 0
        var shot = false
        for i in 0..<60 {
            frame.origin.x = main.minX + CGFloat(sin(Float(i) * 0.55)) * 150
            frame.origin.y = main.minY + CGFloat(sin(Float(i) * 0.8)) * 40
            shake.apply(windows: [SnowWindow(id: 1, frame: frame), wins[1]], dt: dt)
            shake.step(dt)
            peak = max(peak, shake.clumpCount)
            if i == 34, !shot { shot = true; render(shake, [SnowWindow(id: 1, frame: frame), wins[1]], output, "3-sallama.png") }
        }
        check("sallanan pencereden kar dökülür", shake.ledges[1]!.mass < loaded * 0.45, "\(f(loaded)) → \(f(shake.ledges[1]!.mass))")
        check("dökülmeden sonra kalan kar havada kalmaz", shake.ledges[1]!.bed.floatingCount == 0)
        check("dökülen kar topaklara ayrılır", peak >= 25, "\(peak) topak")

        // 4. Boyut değiştirme
        let resize = freshLoaded(wins)
        let wide = resize.ledges[1]!.mass
        var small = main
        for _ in 0..<30 {
            small.size.width -= 12
            resize.apply(windows: [SnowWindow(id: 1, frame: small), wins[1]], dt: dt)
            resize.step(dt)
        }
        check("pencere daralınca taşan kar düşer", resize.clumpCount > 10 && resize.ledges[1]!.mass < wide * 0.7, "\(f(wide)) → \(f(resize.ledges[1]!.mass))")
        check("kalan kar yeni genişliğe uyar", resize.ledges[1]!.h.count == Int(small.width))

        // 5. Kapatma ve Dock'a indirme: kütle yere düşer
        let close = SnowEngine(width: 1470, height: 956)
        close.limit = 1.6
        close.intensity = 1
        run(close, seconds: 90, windows: [wins[0]])
        close.intensity = -0.12
        run(close, seconds: 8, windows: [wins[0]])
        let onWindow = close.ledges[1]!.mass, groundBefore = close.groundMass
        close.apply(windows: [], dt: 0.1); close.apply(windows: [], dt: 0.1)
        check("kapanan pencerenin karı anında kopar", close.ledges[1] == nil && close.clumpCount > 15, "\(close.clumpCount) topak")
        render(close, [], output, "4-kapanma.png")
        run(close, seconds: 6, windows: [])
        let gained = close.groundMass - groundBefore
        check("kopan kar yere iner ve yığılır", gained > onWindow * 0.75, "pencerede \(f(onWindow)), yere inen \(f(gained))")
        check("havada topak kalmaz", close.clumpCount == 0)

        // 6. Masaüstü değişimi
        let space = freshLoaded(wins)
        let kept = space.ledges[1]!.mass
        let airborne = space.clumpCount
        space.noteSpaceChange()
        space.apply(windows: [], dt: 0.1); space.apply(windows: [], dt: 0.1)
        let noFall = space.clumpCount
        space.apply(windows: wins, dt: 0.1)
        check("masaüstü değişince kar dökülmez, geri gelir", noFall <= airborne + 8 && abs((space.ledges[1]?.mass ?? 0) - kept) < 1)

        // 7. Önündeki pencere
        let cover = SnowEngine(width: 1470, height: 956)
        cover.intensity = 1
        let front = CGRect(x: 500, y: 120, width: 300, height: 300)
        let stacked = [SnowWindow(id: 9, frame: front), SnowWindow(id: 1, frame: main)]
        run(cover, seconds: 60, windows: stacked)
        let l = cover.ledges[1]!
        let hidden = l.h.indices.filter { l.covered[$0] }
        let hiddenMass = hidden.reduce(Float(0)) { $0 + l.h[$1] }
        check("önde kalan pencerenin altına kar yağmaz", hidden.count > 100 && hiddenMass < Float(hidden.count), "\(hidden.count) sütun, kütle \(f(hiddenMass))")

        // 8. Kapatınca erime
        let melt = freshLoaded(wins)
        melt.setMelting(true)
        run(melt, seconds: 12, windows: wins)
        check("kar kapatılınca tamamen erir", melt.isFinished, "kalan \(f(melt.groundMass + melt.ledgeMass))")

        // 9. Kar küreme aracı
        let off = SnowEngine(width: 1470, height: 956)
        off.intensity = 1
        run(off, seconds: 420, windows: [])
        check("araç kapalıyken hiç gelmez", off.plowTrips == 0 && off.groundFill >= SnowEngine.plowThreshold, String(format: "doluluk %%%.0f", off.groundFill * 100))

        let plow = SnowEngine(width: 1470, height: 956)
        plow.intensity = 1
        plow.plowEnabled = true
        var waited: Float = 0
        while plow.plow == nil, waited < 600 { plow.step(dt); waited += dt }
        check("zemin dolunca araç kendiliğinden gelir", plow.plow != nil && plow.groundFill >= SnowEngine.plowThreshold, "\(f(waited)) sn sonra")
        let snowBefore = plow.groundMass
        plow.intensity = -0.12
        var sprayed = 0, clean = true, shotPlow = false
        var drive: Float = 0
        while plow.plow != nil, drive < 40 {
            plow.step(dt); drive += dt
            sprayed = max(sprayed, plow.clumpCount)
            if let p = plow.plow, p.x > 300, p.x < 1200 {
                let blade = p.x + p.dir * SnowPlow.bladeReach
                let behind = plow.groundGrains.filter { p.dir > 0 ? $0.x < blade - 90 && $0.x > blade - 150 : $0.x > blade + 90 && $0.x < blade + 150 }
                if behind.count > 40 { clean = false }
                if !shotPlow, p.x > 650 { shotPlow = true; render(plow, [], output, "5-kureme.png") }
            }
        }
        check("araç ekranı geçip çıkar", plow.plow == nil && drive < 20, "\(f(drive)) sn")
        check("geçtiği yerde kar kalmaz", clean)
        check("kar bıçağın önünden savrulur", sprayed >= 10, "\(sprayed) topak")
        run(plow, seconds: 6, windows: [])
        check("zemin temizlenir", plow.groundMass < snowBefore * 0.3, "\(f(snowBefore)) → \(f(plow.groundMass))")
        plow.intensity = 1
        let trips = plow.plowTrips
        run(plow, seconds: 20, windows: [])
        check("araç hemen geri dönmez", plow.plowTrips == trips)

        // 10. Çizim
        check("Metal çizici hazırlanır", SnowRenderer() != nil)

        print(failures == 0 ? "KAR_GECTI" : "KAR_KALDI \(failures)")
        return failures == 0 ? 0 : 1
    }

    private static func freshLoaded(_ wins: [SnowWindow]) -> SnowEngine {
        let e = SnowEngine(width: 1470, height: 956)
        e.intensity = 1
        run(e, seconds: 200, windows: wins)
        return e
    }

    // MARK: - Görsel kontrol

    private static func render(_ e: SnowEngine, _ wins: [SnowWindow], _ output: URL?, _ name: String) {
        guard let output, let r = SnowRenderer() else { return }
        let w = Int(e.width), h = Int(e.height)
        let k = 2
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w * 2, height: h * 2, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let tex = r.device.makeTexture(descriptor: d) else { return }
        r.draw(e, to: tex, drawable: nil, wait: true)

        var bytes = [UInt8](repeating: 0, count: w * h * 16)
        tex.getBytes(&bytes, bytesPerRow: w * 8, from: MTLRegionMake2D(0, 0, w * 2, h * 2), mipmapLevel: 0)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let snowCtx = CGContext(data: &bytes, width: w * 2, height: h * 2, bitsPerComponent: 8, bytesPerRow: w * 8, space: space, bitmapInfo: info),
              let snow = snowCtx.makeImage(),
              let c = CGContext(data: nil, width: w * k, height: h * k, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return }
        c.scaleBy(x: CGFloat(k), y: CGFloat(k))

        let g = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.10, green: 0.17, blue: 0.32, alpha: 1),
                                                        CGColor(srgbRed: 0.30, green: 0.40, blue: 0.56, alpha: 1)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        for win in wins.reversed() {
            let rect = CGRect(x: win.frame.minX, y: CGFloat(h) - win.frame.maxY, width: win.frame.width, height: win.frame.height)
            let path = CGPath(roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(gray: 0, alpha: 0.5))
            c.addPath(path); c.setFillColor(CGColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1)); c.fillPath()
            c.restoreGState()
            c.setFillColor(CGColor(srgbRed: 0.20, green: 0.21, blue: 0.24, alpha: 1))
            c.saveGState(); c.addPath(path); c.clip()
            c.fill(CGRect(x: rect.minX, y: rect.maxY - 30, width: rect.width, height: 30))
            c.restoreGState()
            for (i, col) in [(0.93, 0.36, 0.33), (0.96, 0.75, 0.25), (0.35, 0.78, 0.36)].enumerated() {
                c.setFillColor(CGColor(srgbRed: col.0, green: col.1, blue: col.2, alpha: 1))
                c.fillEllipse(in: CGRect(x: rect.minX + 13 + CGFloat(i) * 19, y: rect.maxY - 21, width: 12, height: 12))
            }
        }
        c.draw(snow, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = c.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name))
    }
}
