import AppKit

/// Bir karede içeceği çizmek için gereken her şey.
struct DrinkState {
    var kind: DrinkKind = .tea
    /// Görünen sıvı seviyesi (0 boş, 1 dolu).
    var level: Double = 1
    /// Dolum akışının gücü (0 akış yok).
    var pour: Double = 0
    /// Buharın gücü (0 soğuk).
    var steam: Double = 0.7
    var progress: Double = 0
    var phase: PomoPhase = .idle
    var running = false
    var slosh = SloshPhysics()
    var time: Double = 0
    /// Süre bitince bardağın titremesi (1'den 0'a iner).
    var shake: Double = 0
    var effects: DrinkEffects = .high
}

/// Sıvının bulunduğu iç bölge ve içeceğin davranışı.
struct DrinkGeo {
    var mid: CGFloat
    /// Sıvının dibi ve tam doluyken yüzeyi.
    var bottom: CGFloat
    var top: CGFloat
    var rim: CGFloat
    var rimHalf: CGFloat
    /// Bir yükseklikte iç yarı genişlik.
    var interior: (CGFloat) -> CGFloat
    var opaque = false
    var steamRate = 0.0
    var bubbles = false
    /// Perspektif: yüzey elipsinin yüksekliğinin genişliğe oranı.
    var tilt: CGFloat = 0.16

    func surface(_ level: Double) -> CGFloat { bottom + (top - bottom) * CGFloat(min(1, max(0, level))) }
}

/// İçeceklerin ortak ölçüleri ve çizimi. Tüm ölçüler 1x ölçekte, sol alt köşe başlangıçlı 220×300 tuvalde verilir.
/// Durağan katmanlar (tabak, cam, porselen, motifler) bir kez çizilip önbelleğe alınır; her karede yalnızca sıvı,
/// köpük, buhar ve baloncuklar çizilir.
enum DrinkArt {
    static let canvas = CGSize(width: 220, height: 300)

    /// Core Animation'ın doğrudan kullandığı piksel düzeni (BGRA); kopyalama gerekmez.
    static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    /// Bitmaplerin renk alanı. Ekranınkiyle aynı olunca Core Animation her karede renk dönüşümü yapmaz.
    static var space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)! {
        didSet {
            guard space != oldValue else { return }
            cache.removeAll()
            puffImage = nil
            steamBuffer = nil
            sprites.removeAll()
        }
    }

    /// Tutulabilen gövde (bardak ve tabak); tıklama alanı budur.
    static func body(_ kind: DrinkKind) -> CGRect {
        switch kind {
        case .tea: return CGRect(x: 36, y: 10, width: 148, height: 132)
        case .turkishCoffee: return CGRect(x: 30, y: 10, width: 160, height: 108)
        case .mug: return CGRect(x: 42, y: 4, width: 150, height: 162)
        case .beer: return CGRect(x: 54, y: 6, width: 112, height: 196)
        }
    }

    static func geo(_ kind: DrinkKind) -> DrinkGeo {
        switch kind {
        case .tea: return TeaGlass.geo
        case .turkishCoffee: return TurkishCoffee.geo
        case .mug: return CoffeeMug.geo
        case .beer: return BeerPint.geo
        }
    }

    // MARK: - Çizim

    static func draw(_ s: DrinkState, particles p: DrinkParticles, in ctx: CGContext, size: CGSize, pixelScale: CGFloat) {
        ctx.saveGState()
        ctx.scaleBy(x: size.width / canvas.width, y: size.height / canvas.height)
        if s.shake > 0 {   // süre bitince hafif titreme
            let a = s.shake * s.shake * 1.8
            ctx.translateBy(x: CGFloat(sin(s.time * 64) * a), y: CGFloat(abs(sin(s.time * 47)) * a * 0.4))
        }
        let layers = cached(s.kind, pixels: CGSize(width: size.width * pixelScale, height: size.height * pixelScale))
        let full = CGRect(origin: .zero, size: canvas)
        if let back = layers.back { ctx.draw(back, in: full) }
        dynamic(s, particles: p, in: ctx)
        if s.pour > 0.01 { pourStream(ctx, s) }
        if let front = layers.front { ctx.draw(front, in: full) }
        if s.kind == .tea { TeaGlass.overlay(ctx, s, p) }
        steam(ctx, p)
        ctx.restoreGState()
    }

    /// Her karede değişen kısım: sıvı, köpük, baloncuklar ve biranın buğusu.
    static func dynamic(_ s: DrinkState, particles p: DrinkParticles, in ctx: CGContext) {
        switch s.kind {
        case .tea: TeaGlass.liquid(ctx, s, p)
        case .turkishCoffee: TurkishCoffee.liquid(ctx, s, p)
        case .mug: CoffeeMug.liquid(ctx, s, p)
        case .beer: BeerPint.liquid(ctx, s, p); BeerPint.overlay(ctx, s, p)
        }
    }

    /// Her karede yeniden çizilen bölgeler (tuval koordinatında).
    static func regions(_ kind: DrinkKind) -> (liquid: CGRect, pour: CGRect, spoon: CGRect?) {
        let g = geo(kind)
        let pour = CGRect(x: g.mid - 8, y: g.opaque ? g.rim - 20 : g.bottom - 8, width: 24, height: canvas.height)
        switch kind {
        case .tea: return (CGRect(x: 72, y: 24, width: 76, height: 118), pour, CGRect(x: 130, y: 8, width: 72, height: 42))
        case .turkishCoffee: return (CGRect(x: 68, y: 86, width: 84, height: 36), pour, nil)
        case .mug: return (CGRect(x: 44, y: 128, width: 104, height: 42), pour, nil)
        case .beer: return (CGRect(x: 56, y: 6, width: 108, height: 206), pour, nil)
        }
    }

    /// Önbelleğe alınmış durağan katmanlar.
    struct Layers { var back: CGImage?; var front: CGImage? }
    private static var cache: [String: Layers] = [:]

    static func cached(_ kind: DrinkKind, pixels: CGSize) -> Layers {
        let w = max(1, Int(pixels.width.rounded())), h = max(1, Int(pixels.height.rounded()))
        let key = "\(kind.rawValue)-\(w)x\(h)"
        if let l = cache[key] { return l }
        if cache.count > 12 { cache.removeAll() }
        let l = Layers(back: bake(w, h) { ctx in staticPart(kind, front: false, ctx) },
                       front: bake(w, h) { ctx in staticPart(kind, front: true, ctx) })
        cache[key] = l
        return l
    }

    private static func staticPart(_ kind: DrinkKind, front: Bool, _ ctx: CGContext) {
        switch kind {
        case .tea: front ? TeaGlass.front(ctx) : TeaGlass.back(ctx)
        case .turkishCoffee: front ? TurkishCoffee.front(ctx) : TurkishCoffee.back(ctx)
        case .mug: front ? CoffeeMug.front(ctx) : CoffeeMug.back(ctx)
        case .beer: front ? BeerPint.front(ctx) : BeerPint.back(ctx)
        }
    }

    static func bake(_ w: Int, _ h: Int, _ paint: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: DrinkArt.bitmapInfo) else { return nil }
        ctx.scaleBy(x: CGFloat(w) / canvas.width, y: CGFloat(h) / canvas.height)
        ctx.interpolationQuality = .high
        paint(ctx)
        return ctx.makeImage()
    }

    /// Belirli bir anın görüntüsü (panel kartları, testler ve README görselleri için).
    static func render(_ s: DrinkState, particles: DrinkParticles, size: CGSize, scale: CGFloat) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: DrinkArt.bitmapInfo) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        draw(s, particles: particles, in: ctx, size: size, pixelScale: scale)
        return ctx.makeImage()
    }

    /// Panel kartı için hazır görüntü: buhar ve baloncuklar birkaç saniye ilerletilmiş halde.
    static func thumbnail(_ kind: DrinkKind, size: CGSize, scale: CGFloat = 2, level: Double = 0.82) -> NSImage {
        var s = DrinkState()
        s.kind = kind
        s.level = level
        s.steam = 0.8
        var p = DrinkParticles(seed: 7)
        for _ in 0..<240 { s.time += 1.0 / 60; p.step(dt: 1.0 / 60, state: s) }
        guard let cg = render(s, particles: p, size: size, scale: scale) else { return NSImage(size: size) }
        return NSImage(cgImage: cg, size: size)
    }

    // MARK: - Ortak parçalar

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
                   locations: stops.map(\.0))!
    }

    /// Yatay doğrusal gradyanla bir yolu doldurur (silindir gölgelemesi için).
    static func fillAcross(_ ctx: CGContext, _ path: CGPath, from x0: CGFloat, to x1: CGFloat, _ stops: [(CGFloat, CGColor)]) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: x0, y: 0), end: CGPoint(x: x1, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    static func fillDown(_ ctx: CGContext, _ path: CGPath, from y0: CGFloat, to y1: CGFloat, _ stops: [(CGFloat, CGColor)]) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// Masaya düşen yumuşak gölge.
    static func shadow(_ ctx: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: 1, y: ry / rx)
        ctx.drawRadialGradient(gradient([(0, rgb(0, 0, 0, alpha)), (0.55, rgb(0, 0, 0, alpha * 0.55)), (1, rgb(0, 0, 0, 0))]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx, options: [])
        ctx.restoreGState()
    }

    static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
        CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)
    }

    /// Elipsin üst (arka) ya da alt (ön) yarısı.
    static func halfEllipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, upper: Bool) -> CGPath {
        let p = CGMutablePath()
        let n = 40
        for i in 0...n {
            let a = CGFloat.pi * CGFloat(i) / CGFloat(n)
            let pt = CGPoint(x: c.x - cos(a) * rx, y: c.y + (upper ? 1 : -1) * sin(a) * ry)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }

    // MARK: - Sıvı yüzeyi

    /// Çalkalanan sıvının gövdesi (dipten arka kenara) ve üst yüzeyi (ön ve arka kenar arası).
    static func liquidShape(_ g: DrinkGeo, _ s: DrinkState, level: Double, bottomCurve: CGFloat = 0.5) -> (body: CGPath, top: CGPath, front: [CGPoint]) {
        let base = g.surface(level)
        let n = 28
        let damp = min(1, level * 5)
        func h(_ u: Double, _ y: CGFloat) -> CGFloat {
            let half = g.interior(y)
            return CGFloat(s.slosh.height(at: u, halfWidth: Double(half))) * CGFloat(damp)
        }
        var front: [CGPoint] = [], back: [CGPoint] = []
        for i in 0...n {
            let u = Double(i) / Double(n) * 2 - 1
            let half = g.interior(base)
            let e = half * g.tilt * CGFloat(sqrt(max(0, 1 - u * u)))
            let mid = min(g.rim - 1, max(g.bottom + 0.5, base + h(u, base)))
            let yf = max(g.bottom, mid - e), yb = min(g.rim, mid + e)
            front.append(CGPoint(x: g.mid + CGFloat(u) * g.interior(yf), y: yf))
            back.append(CGPoint(x: g.mid + CGFloat(u) * g.interior(yb), y: yb))
        }
        let body = CGMutablePath()
        let bHalf = g.interior(g.bottom)
        for i in 0...n {
            let u = Double(i) / Double(n) * 2 - 1
            let y = g.bottom - bHalf * g.tilt * bottomCurve * CGFloat(sqrt(max(0, 1 - u * u)))
            let pt = CGPoint(x: g.mid + CGFloat(u) * bHalf, y: y)
            i == 0 ? body.move(to: pt) : body.addLine(to: pt)
        }
        // Sağ duvar boyunca yukarı
        let rightTop = back.last!.y
        var y = g.bottom
        while y < rightTop { body.addLine(to: CGPoint(x: g.mid + g.interior(y), y: y)); y += 4 }
        for pt in back.reversed() { body.addLine(to: pt) }
        y = back.first!.y
        while y > g.bottom { body.addLine(to: CGPoint(x: g.mid - g.interior(y), y: y)); y -= 4 }
        body.closeSubpath()
        let top = CGMutablePath()
        top.addLines(between: front)
        for pt in back.reversed() { top.addLine(to: pt) }
        top.closeSubpath()
        return (body, top, front)
    }

    // MARK: - Dolum akışı ve buhar

    static func pourStream(_ ctx: CGContext, _ s: DrinkState) {
        let g = geo(s.kind)
        let x = g.mid + 6
        let end = g.opaque ? g.rim - g.rimHalf * g.tilt * 0.4 : g.surface(s.level)
        let w = 4.6 * CGFloat(min(1, s.pour))
        let p = CGMutablePath()
        let topY = canvas.height + 4
        var pts: [CGPoint] = []
        var y = topY
        while y > end {
            let k = (topY - y) / max(1, topY - end)
            let wob = sin(Double(y) * 0.12 + s.time * 18) * 0.7 * Double(k)
            pts.append(CGPoint(x: x + CGFloat(wob) - k * 2, y: y))
            y -= 6
        }
        pts.append(CGPoint(x: x - 2, y: end))
        let narrow: (CGFloat) -> CGFloat = { yy in w * (0.62 + 0.38 * (yy - end) / max(1, topY - end)) }
        p.move(to: CGPoint(x: pts[0].x - narrow(pts[0].y) / 2, y: pts[0].y))
        for pt in pts { p.addLine(to: CGPoint(x: pt.x - narrow(pt.y) / 2, y: pt.y)) }
        for pt in pts.reversed() { p.addLine(to: CGPoint(x: pt.x + narrow(pt.y) / 2, y: pt.y)) }
        p.closeSubpath()
        let c = streamColor(s.kind)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(1, s.pour)))
        ctx.addPath(p)
        ctx.setFillColor(c)
        ctx.fillPath()
        // Akışın üzerindeki ince parlaklık
        ctx.setStrokeColor(rgb(1, 1, 1, 0.45))
        ctx.setLineWidth(0.8)
        ctx.addLines(between: pts.map { CGPoint(x: $0.x - w * 0.18, y: $0.y) })
        ctx.strokePath()
        // Çarptığı yerde köpüklü halka
        let splash = sin(s.time * 30) * 0.8
        ctx.setFillColor(s.kind == .beer ? rgb(1, 0.98, 0.92, 0.85) : rgb(1, 1, 1, 0.22))
        ctx.fillEllipse(in: ellipse(CGPoint(x: x - 2, y: end + 1), 7 + CGFloat(splash), 2.2))
        ctx.restoreGState()
    }

    static func streamColor(_ k: DrinkKind) -> CGColor {
        switch k {
        case .tea: return rgb(0.72, 0.2, 0.07, 0.9)
        case .turkishCoffee: return rgb(0.3, 0.17, 0.09, 1)
        case .mug: return rgb(0.25, 0.13, 0.06, 1)
        case .beer: return rgb(0.97, 0.7, 0.2, 0.92)
        }
    }

    /// Yumuşak beyaz buhar topağı; her partikül bu görüntüyü saydamlıkla çizer.
    private static var puffImage: CGImage?
    static var puff: CGImage? {
        if puffImage == nil {
            puffImage = bakeSquare(64) { ctx in
                ctx.drawRadialGradient(gradient([(0, rgb(1, 1, 1, 1)), (0.35, rgb(1, 1, 1, 0.55)), (0.7, rgb(1, 1, 1, 0.16)), (1, rgb(1, 1, 1, 0))]),
                                       startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            }
        }
        return puffImage
    }

    static func bakeSquare(_ side: Int, _ paint: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: DrinkArt.bitmapInfo) else { return nil }
        paint(ctx)
        return ctx.makeImage()
    }

    /// Buhar yumuşak olduğu için düşük çözünürlüklü ayrı bir tamponda çizilip büyütülür; işlemci yükü çok azalır.
    private static var steamBuffer: CGContext?
    static let steamResolution: CGFloat = 0.45   // tuval noktası başına piksel

    /// Tuvalin tamamını kaplayan düşük çözünürlüklü buhar görüntüsü (katman içerik olarak büyütür).
    static func steamImage(_ p: DrinkParticles) -> CGImage? {
        guard let puff, !p.puffs.isEmpty else { return nil }
        let w = Int(canvas.width * steamResolution), h = Int(canvas.height * steamResolution)
        if steamBuffer == nil { _ = makeSteamBuffer(w, h) }
        guard let buf = steamBuffer else { return nil }
        buf.clear(CGRect(origin: .zero, size: canvas))
        let res = steamResolution
        for f in p.puffs where f.alpha > 0.004 {
            buf.setAlpha(CGFloat(f.alpha))
            // Hazır boyutlu topak piksel ızgarasına oturtularak çizilir; yeniden örnekleme gerekmez.
            let rPx = max(2, Int((CGFloat(f.size) * res).rounded()))
            let st = Int(((f.stretch - 1) * 8).rounded())
            guard let sprite = puffSprite(rPx, st) else { continue }
            let wPx = CGFloat(sprite.width), hPx = CGFloat(sprite.height)
            let x = (CGFloat(f.x) * res - wPx / 2).rounded(), y = (CGFloat(f.y) * res - hPx / 2).rounded()
            buf.draw(sprite, in: CGRect(x: x / res, y: y / res, width: wPx / res, height: hPx / res))
        }
        return buf.makeImage()
    }

    private static func makeSteamBuffer(_ w: Int, _ h: Int) -> Bool {
        steamBuffer = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: DrinkArt.bitmapInfo)
        steamBuffer?.scaleBy(x: steamResolution, y: steamResolution)
        steamBuffer?.interpolationQuality = .low
        return steamBuffer != nil
    }

    private static var sprites: [Int: CGImage] = [:]

    /// Belirli piksel yarıçapında ve yana uzamada önceden çizilmiş buhar topağı.
    private static func puffSprite(_ rPx: Int, _ stretchStep: Int) -> CGImage? {
        let key = rPx * 16 + stretchStep
        if let s = sprites[key] { return s }
        let h = rPx * 2, w = Int((CGFloat(h) * (1 + CGFloat(stretchStep) / 8)).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo),
              let puff else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(puff, in: CGRect(x: 0, y: 0, width: w, height: h))
        let img = ctx.makeImage()
        if sprites.count > 400 { sprites.removeAll() }
        sprites[key] = img
        return img
    }

    static func steam(_ ctx: CGContext, _ p: DrinkParticles) {
        guard let puff, !p.puffs.isEmpty else { return }
        let w = Int(canvas.width * steamResolution), h = Int(canvas.height * steamResolution)
        if steamBuffer == nil { _ = makeSteamBuffer(w, h) }
        guard let buf = steamBuffer else { return }
        var bounds = CGRect.null
        for f in p.puffs where f.alpha > 0.004 {
            let r = CGFloat(f.size)
            bounds = bounds.union(CGRect(x: CGFloat(f.x) - r * f.stretch, y: CGFloat(f.y) - r, width: r * 2 * f.stretch, height: r * 2))
        }
        bounds = bounds.intersection(CGRect(origin: .zero, size: canvas))
        guard !bounds.isNull, bounds.width > 1, bounds.height > 1 else { return }
        // Yalnızca buharın kapladığı bölge temizlenir ve büyütülür.
        let px = CGRect(x: floor(bounds.minX * steamResolution), y: floor(bounds.minY * steamResolution),
                        width: ceil(bounds.width * steamResolution) + 2, height: ceil(bounds.height * steamResolution) + 2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        let area = CGRect(x: px.minX / steamResolution, y: px.minY / steamResolution,
                          width: px.width / steamResolution, height: px.height / steamResolution)
        buf.clear(area)
        for f in p.puffs {
            let a = f.alpha
            guard a > 0.004 else { continue }
            buf.setAlpha(CGFloat(a))
            let r = CGFloat(f.size)
            // Yükseldikçe yanlara uzayan, kıvrılan topak
            buf.draw(puff, in: CGRect(x: CGFloat(f.x) - r * f.stretch, y: CGFloat(f.y) - r, width: r * 2 * f.stretch, height: r * 2))
        }
        // CGImage satırları yukarıdan aşağı sayılır.
        let crop = CGRect(x: px.minX, y: CGFloat(h) - px.maxY, width: px.width, height: px.height)
        guard let img = buf.makeImage()?.cropping(to: crop) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: area)
        ctx.restoreGState()
    }

    // MARK: - Cam

    /// Cam bardağın kenar parlaklığı: profil boyunca uzanan ince ışık şeridi.
    static func highlightStrip(_ ctx: CGContext, mid: CGFloat, half: (CGFloat) -> CGFloat, u0: CGFloat, u1: CGFloat,
                               from y0: CGFloat, to y1: CGFloat, alpha: CGFloat) {
        let p = CGMutablePath()
        var y = y0
        p.move(to: CGPoint(x: mid + u0 * half(y0), y: y0))
        while y <= y1 { p.addLine(to: CGPoint(x: mid + u0 * half(y), y: y)); y += 3 }
        y = y1
        while y >= y0 { p.addLine(to: CGPoint(x: mid + u1 * half(y), y: y)); y -= 3 }
        p.closeSubpath()
        fillDown(ctx, p, from: y0, to: y1, [(0, rgb(1, 1, 1, 0)), (0.18, rgb(1, 1, 1, alpha)), (0.75, rgb(1, 1, 1, alpha * 0.8)), (1, rgb(1, 1, 1, 0))])
    }

    /// Profilden kapalı yol (sol kenar aşağıdan yukarı, sağ kenar yukarıdan aşağı).
    static func silhouette(mid: CGFloat, from y0: CGFloat, to y1: CGFloat, half: (CGFloat) -> CGFloat, step: CGFloat = 2) -> CGMutablePath {
        let p = CGMutablePath()
        var y = y0
        p.move(to: CGPoint(x: mid - half(y0), y: y0))
        while y < y1 { y = min(y1, y + step); p.addLine(to: CGPoint(x: mid - half(y), y: y)) }
        y = y1
        p.addLine(to: CGPoint(x: mid + half(y1), y: y1))
        while y > y0 { y = max(y0, y - step); p.addLine(to: CGPoint(x: mid + half(y), y: y)) }
        p.closeSubpath()
        return p
    }
}

/// Yükseklik–yarı genişlik noktalarından yumuşak bardak profili (Catmull–Rom).
struct Profile {
    let pts: [(y: CGFloat, h: CGFloat)]

    func half(_ y: CGFloat) -> CGFloat {
        guard let first = pts.first, let last = pts.last else { return 0 }
        if y <= first.y { return first.h }
        if y >= last.y { return last.h }
        var i = 0
        while i < pts.count - 2, y > pts[i + 1].y { i += 1 }
        let p0 = pts[max(0, i - 1)].h, p1 = pts[i].h, p2 = pts[i + 1].h, p3 = pts[min(pts.count - 1, i + 2)].h
        let t = (y - pts[i].y) / (pts[i + 1].y - pts[i].y)
        let t2 = t * t, t3 = t2 * t
        return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }
}

/// Tekrarlanabilir rastgele sayılar: motifler ve damlalar her açılışta aynı yerde durur.
struct SeededRandom {
    private var s: UInt64
    init(_ seed: UInt64) { s = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    mutating func cg(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat(range(Double(a), Double(b))) }
}
