import CoreGraphics
import Foundation

/// Buhar topakları, karbonasyon baloncukları, kayan yoğuşma damlaları ve bira köpüğünün camda bıraktığı izler.
struct DrinkParticles {
    struct Puff {
        var x, y, x0: Double
        var vy: Double
        var size, grow: Double
        var age, life: Double
        var seed: Double
        var strength: Double
        var curl: Double

        var alpha: Double {
            let t = age / life
            let fadeIn = min(1, age / 0.5)
            let fadeOut = max(0, 1 - pow(t, 1.6))
            return 0.1 * strength * fadeIn * fadeOut
        }
        var stretch: CGFloat { CGFloat(1 + 0.5 * age / life) }
    }

    struct Bubble {
        var x, y, r, speed, phase: Double
        var site: Int   // -1 serbest, aksi halde çekirdeklenme noktası
    }

    struct Slider {
        var x, y, startY, r, speed: Double
        var pause: Double
    }

    var puffs: [Puff] = []
    var bubbles: [Bubble] = []
    var sliders: [Slider] = []
    /// Biranın camda köpük izi bıraktığı yükseklikler.
    var lacing: [CGFloat] = []
    private var lastLevel: Double = 1
    private var rng: SeededRandom
    private var steamDebt = 0.0
    private var bubbleDebt = 0.0
    private var slideTimer = 2.0
    private var kind: DrinkKind?
    private var nextGap: CGFloat = 14

    init(seed: UInt64 = 1) { rng = SeededRandom(seed) }

    var count: Int { puffs.count + bubbles.count + sliders.count }

    mutating func step(dt: Double, state s: DrinkState) {
        if kind != s.kind { kind = s.kind; puffs.removeAll(); bubbles.removeAll(); sliders.removeAll(); lacing.removeAll(); lastLevel = s.level }
        let g = DrinkArt.geo(s.kind)
        let factor = s.effects.particleFactor
        stepSteam(dt, s, g, factor)
        if g.bubbles { stepBubbles(dt, s, g, factor); stepLacing(s, g); stepSliders(dt) }
        lastLevel = s.level
    }

    // MARK: - Buhar

    private mutating func stepSteam(_ dt: Double, _ s: DrinkState, _ g: DrinkGeo, _ factor: Double) {
        if g.steamRate > 0, s.steam > 0.02 {
            steamDebt += dt * g.steamRate * factor * min(1, s.steam * 1.3)
            while steamDebt >= 1 {
                steamDebt -= 1
                let surface = g.opaque ? Double(g.rim) : Double(max(g.surface(s.level) + 4, g.rim - 30))
                let half = Double(g.opaque ? g.rimHalf : g.interior(g.surface(s.level)))
                let x = Double(g.mid) + rng.range(-0.62, 0.62) * half
                puffs.append(Puff(x: x, y: surface + rng.range(-2, 4), x0: x, vy: rng.range(13, 22) * (0.7 + 0.3 * s.steam),
                                  size: rng.range(8, 12), grow: rng.range(5.5, 8.5), age: 0, life: rng.range(2.8, 4.4),
                                  seed: rng.range(0, 6.28), strength: s.steam, curl: rng.range(5, 11)))
            }
        } else {
            steamDebt = 0
        }
        // Bardak sürüklenince buhar geride kalır gibi yana yatar.
        let drift = -s.slosh.tilt * 40
        for i in puffs.indices.reversed() {
            var f = puffs[i]
            f.age += dt
            if f.age >= f.life { puffs.remove(at: i); continue }
            let k = f.age / f.life
            f.y += f.vy * dt * (1 - 0.35 * k)
            f.x0 += drift * dt
            // Yükseldikçe genişleyen kıvrım
            f.x = f.x0 + sin(f.age * 1.7 + f.seed) * f.curl * k + sin(f.age * 0.6 + f.seed * 2) * 3 * k
            f.size += f.grow * dt
            puffs[i] = f
        }
        if puffs.count > 160 { puffs.removeFirst(puffs.count - 160) }
    }

    // MARK: - Baloncuklar

    private static let sites: [Double] = [-0.55, -0.12, 0.3, 0.62]

    private mutating func stepBubbles(_ dt: Double, _ s: DrinkState, _ g: DrinkGeo, _ factor: Double) {
        let surface = Double(g.surface(s.level))
        let depth = surface - Double(g.bottom)
        if depth > 6 {
            bubbleDebt += dt * 34 * factor * min(1, depth / 60)
            while bubbleDebt >= 1 {
                bubbleDebt -= 1
                let fromSite = rng.next() < 0.6
                let site = fromSite ? Int(rng.next() * Double(Self.sites.count)) % Self.sites.count : -1
                let u = fromSite ? Self.sites[site] + rng.range(-0.02, 0.02) : rng.range(-0.8, 0.8)
                let y = Double(g.bottom) + 2 + (fromSite ? 0 : rng.range(0, depth * 0.5))
                let half = Double(g.interior(CGFloat(y)))
                bubbles.append(Bubble(x: Double(g.mid) + u * half, y: y, r: rng.range(0.55, fromSite ? 1.1 : 1.6),
                                      speed: rng.range(16, 30), phase: rng.range(0, 6.28), site: site))
            }
        }
        for i in bubbles.indices.reversed() {
            var b = bubbles[i]
            b.speed += dt * 14   // yükseldikçe hızlanır
            b.y += b.speed * dt
            b.r *= 1 + dt * 0.12  // basınç azaldıkça büyür
            b.x += sin(b.y * 0.21 + b.phase) * 0.12 - s.slosh.tilt * 6 * dt
            let half = Double(g.interior(CGFloat(b.y))) - b.r - 1
            b.x = min(Double(g.mid) + half, max(Double(g.mid) - half, b.x))
            let top = surface + s.slosh.height(at: (b.x - Double(g.mid)) / max(1, half), halfWidth: half)
            if b.y >= top - b.r { bubbles.remove(at: i); continue }
            bubbles[i] = b
        }
        if bubbles.count > 140 { bubbles.removeFirst(bubbles.count - 140) }
    }

    // MARK: - Köpük izi ve kayan damlalar

    private mutating func stepLacing(_ s: DrinkState, _ g: DrinkGeo) {
        if s.level > lastLevel + 0.02 {   // yeniden doldu: izler yıkanır
            lacing.removeAll()
            return
        }
        let foamTop = BeerPint.foamTop(g, s)
        let last = lacing.last ?? (g.rim + 100)
        if foamTop < last - nextGap, foamTop < g.rim - 4, s.phase == .focus {
            lacing.append(foamTop)
            nextGap = CGFloat(rng.range(10, 22))   // yudumlar düzensiz aralıklı
        }
    }

    private mutating func stepSliders(_ dt: Double) {
        slideTimer -= dt
        if slideTimer <= 0, sliders.count < 3 {
            slideTimer = rng.range(3, 7)
            let u = rng.range(-0.75, 0.75)
            let y = rng.range(70, 165)
            let g = BeerPint.geo
            sliders.append(Slider(x: Double(g.mid) + u * Double(BeerPint.outer.half(CGFloat(y))) * 0.98, y: y, startY: y,
                                  r: rng.range(1.6, 2.4), speed: rng.range(5, 12), pause: 0))
        }
        for i in sliders.indices.reversed() {
            var d = sliders[i]
            if d.pause > 0 { d.pause -= dt } else {
                d.y -= d.speed * dt
                if rng.next() < dt * 0.7 { d.pause = rng.range(0.2, 0.9) }   // takılıp yeniden kayar
            }
            if d.y < 30 || d.startY - d.y > 70 { sliders.remove(at: i); continue }
            sliders[i] = d
        }
    }
}
