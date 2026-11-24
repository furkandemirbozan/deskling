import AppKit
import QuartzCore

/// İçeceğin masaüstündeki görünümü. Katmanlara ayrılmıştır: tabak, cam ve porselen bir kez yüklenir;
/// her karede yalnızca sıvının bulunduğu küçük bölge ile düşük çözünürlüklü buhar yeniden çizilir.
/// Böylece ekran kartına gönderilen görüntü küçük kalır ve işlemci yükü düşer.
final class DrinkView: NSView {
    var state = DrinkState()
    var particles = DrinkParticles(seed: UInt64(Date().timeIntervalSince1970))

    private let shaker = CALayer()
    private let back = CALayer(), liquid = CALayer(), pour = CALayer(), front = CALayer(), spoon = CALayer(), steam = CALayer()
    private var builtKey = ""
    private var liquidCtx: CGContext?, pourCtx: CGContext?, spoonCtx: CGContext?
    private var spoonDrawn = false
    private var steamTick = false
    private var liquidKey = ""
    /// Denetleyici yüksek kare hızına geçince buhar her iki karede bir çizilir.
    var fastFrames = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        layer = root
        wantsLayer = true
        root.addSublayer(shaker)
        for l in [back, liquid, pour, front, spoon, steam] {
            l.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull(), "transform": NSNull()]
            shaker.addSublayer(l)
        }
        shaker.actions = ["transform": NSNull(), "position": NSNull(), "bounds": NSNull()]
        steam.magnificationFilter = .linear
        steam.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    private var pixelScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    private var k: CGFloat { bounds.width / DrinkArt.canvas.width }

    private func viewRect(_ r: CGRect) -> CGRect { CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k) }

    /// Boyut, tema ya da ekran çözünürlüğü değişince durağan katmanlar yeniden hazırlanır.
    private func rebuildIfNeeded() {
        let key = "\(state.kind.rawValue)-\(bounds.width)-\(pixelScale)"
        guard key != builtKey, bounds.width > 0 else { return }
        builtKey = key
        liquidKey = ""
        if let cs = window?.screen?.colorSpace?.cgColorSpace ?? NSScreen.main?.colorSpace?.cgColorSpace { DrinkArt.space = cs }
        let ps = pixelScale
        shaker.frame = bounds
        let layers = DrinkArt.cached(state.kind, pixels: CGSize(width: bounds.width * ps, height: bounds.height * ps))
        for (l, img) in [(back, layers.back), (front, layers.front)] {
            l.frame = bounds
            l.contents = img
            l.contentsScale = ps
        }
        steam.frame = bounds
        let regions = DrinkArt.regions(state.kind)
        liquid.frame = viewRect(regions.liquid)
        liquidCtx = Self.context(regions.liquid, k: k * ps)
        pour.frame = viewRect(regions.pour)
        pourCtx = Self.context(regions.pour, k: k * ps)
        if let r = regions.spoon {
            spoon.frame = viewRect(r)
            spoonCtx = Self.context(r, k: k * ps)
        } else {
            spoonCtx = nil
            spoon.contents = nil
        }
        spoonDrawn = false
        for l in [liquid, pour, spoon] { l.contentsScale = ps }
    }

    private static func context(_ r: CGRect, k: CGFloat) -> CGContext? {
        let ctx = CGContext(data: nil, width: max(1, Int(ceil(r.width * k))), height: max(1, Int(ceil(r.height * k))), bitsPerComponent: 8,
                            bytesPerRow: 0, space: DrinkArt.space, bitmapInfo: DrinkArt.bitmapInfo)
        ctx?.scaleBy(x: k, y: k)
        ctx?.translateBy(x: -r.minX, y: -r.minY)
        return ctx
    }

    private func paint(_ ctx: CGContext?, _ r: CGRect, into l: CALayer, _ draw: (CGContext) -> Void) {
        guard let ctx else { return }
        ctx.clear(r.insetBy(dx: -1, dy: -1))
        draw(ctx)
        l.contents = ctx.makeImage()
    }

    func render() {
        rebuildIfNeeded()
        let s = state, p = particles
        let regions = DrinkArt.regions(s.kind)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Titreme bütün bardağı birlikte oynatır; yeniden çizim gerekmez.
        if s.shake > 0 {
            let a = s.shake * s.shake * 1.8 * Double(k)
            shaker.setAffineTransform(CGAffineTransform(translationX: CGFloat(sin(s.time * 64) * a), y: CGFloat(abs(sin(s.time * 47)) * a * 0.4)))
        } else {
            shaker.setAffineTransform(.identity)
        }
        // Sıvı yalnızca değiştiğinde yeniden çizilir; durgun çayda kareler bedavaya gelir.
        let moving = s.slosh.energy > 1e-6 || s.pour > 0 || s.shake > 0 || s.kind == .beer
        let key = "\(s.kind.rawValue)|\(Int(s.level * 600))|\(Int(s.progress * 200))|\(s.phase.rawValue)|\(s.kind == .turkishCoffee ? Int(s.time * 8) : 0)"
        if moving || key != liquidKey || liquid.contents == nil {
            liquidKey = moving ? "" : key
            paint(liquidCtx, regions.liquid, into: liquid) { DrinkArt.dynamic(s, particles: p, in: $0) }
        }
        if s.pour > 0.01 {
            pour.isHidden = false
            paint(pourCtx, regions.pour, into: pour) { DrinkArt.pourStream($0, s) }
        } else if !pour.isHidden {
            pour.isHidden = true
        }
        if let r = regions.spoon, s.shake > 0 || !spoonDrawn {
            spoonDrawn = s.shake == 0
            paint(spoonCtx, r, into: spoon) { TeaGlass.overlay($0, s, p) }
        }
        // Buhar yavaş hareket eder; hızlı karelerde yarı hızda güncellenmesi gözle fark edilmez.
        steamTick.toggle()
        if steamTick || s.effects.fps >= 30 && !fastFrames || p.puffs.isEmpty { steam.contents = DrinkArt.steamImage(p) }
        CATransaction.commit()
    }
}
