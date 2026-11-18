import CoreGraphics
import Foundation

struct SnowWindow {
    let id: UInt32
    let frame: CGRect   // ekranın sol üstüne göre, CGWindowList koordinatları
}

/// Yüzeye tutunmuş yuvarlak kar taneciği.
struct SnowGrain {
    var x: Float        // yatağın solundan uzaklık
    var y: Float        // yüzeyden yükseklik (merkez)
    var r: Float
    var tone: Float
}

/// Taneciklerin üst üste tutunarak oluşturduğu kar yığını.
final class SnowBed {
    static let maxGrain: Float = 3.6

    var h: [Float] { didSet { surfaceDirty = true } }
    var caps: [Float]
    var grains: [SnowGrain] = []

    private var surfaceDirty = true
    private var display: [Float] = []
    private var lumps: [Float] = []

    init(columns: Int) {
        h = Array(repeating: 0, count: columns)
        caps = Array(repeating: 0, count: columns)
    }

    var mass: Float { grains.reduce(0) { $0 + .pi * $1.r * $1.r } }

    private static func smoothNoise(_ x: Float, spacing: Float, seed: Float) -> Float {
        func lattice(_ i: Float) -> Float {
            let v = sin((i + seed) * 12.9898) * 43758.5453
            return (v - v.rounded(.down)) * 2 - 1
        }
        let p = x / spacing, i = p.rounded(.down), t = p - i
        let k = t * t * (3 - 2 * t)
        return lattice(i) * (1 - k) + lattice(i + 1) * k
    }

    private static func boxBlur(_ a: [Float], radius: Int) -> [Float] {
        let n = a.count
        var out = [Float](repeating: 0, count: n)
        var sum: Float = 0
        for i in 0...min(radius, n - 1) { sum += a[i] }
        var count = min(radius, n - 1) + 1
        for i in 0..<n {
            out[i] = sum / Float(count)
            if i + radius + 1 < n { sum += a[i + radius + 1]; count += 1 }
            if i - radius >= 0 { sum -= a[i - radius]; count -= 1 }
        }
        return out
    }

    /// Tanecikleri tek parça, düzensiz topaklı bir kar yüzeyine dönüştürür.
    func surface() -> [Float] {
        let n = h.count
        guard surfaceDirty || display.count != n else { return display }
        surfaceDirty = false
        if lumps.count != n {
            let seed = Float(n % 211) * 0.37
            lumps = (0..<n).map { i in
                let x = Float(i)
                return SnowBed.smoothNoise(x, spacing: 26, seed: seed) * 0.52
                    + SnowBed.smoothNoise(x, spacing: 11, seed: seed + 9) * 0.32
                    + SnowBed.smoothNoise(x, spacing: 5, seed: seed + 23) * 0.16
            }
        }
        let fine = SnowBed.boxBlur(h, radius: 1)
        let wide = SnowBed.boxBlur(SnowBed.boxBlur(h, radius: 4), radius: 4)
        var out = [Float](repeating: 0, count: n)
        for c in 0..<n where caps[c] > 0 {
            let base = fine[c] * 0.35 + wide[c] * 0.65
            out[c] = max(0, base + lumps[c] * min(base * 0.3, 4))
        }
        display = out
        return out
    }

    private func stamp(_ g: SnowGrain) {
        let a = max(0, Int(g.x - g.r)), b = min(h.count - 1, Int(g.x + g.r) + 1)
        guard a <= b else { return }
        for c in a...b {
            let d = Float(c) - g.x
            let s = g.r * g.r - d * d
            if s > 0 { h[c] = max(h[c], g.y + s.squareRoot()) }
        }
    }

    private func support(_ x: Float, _ r: Float, in profile: [Float]) -> Float {
        let reach = r * 0.6
        let a = max(0, Int(x - reach)), b = min(profile.count - 1, Int(x + reach) + 1)
        guard a <= b else { return 0 }
        var top: Float = 0
        for c in a...b { top = max(top, profile[c]) }
        return top
    }

    private func rest(on base: Float, _ r: Float) -> Float { base > 0.01 ? base + r * 0.45 : r * 0.8 }

    /// Tanecik yüzeye konur. Çukura yuvarlanır, değdiği küçük taneciğe tutunup onunla büyüyebilir.
    @discardableResult
    func add(x: Float, r: Float, tone: Float, fuse: Bool) -> Bool {
        var c = Int(x)
        guard x >= 0, c < h.count, caps[c] > 0 else { return false }
        for _ in 0..<6 {
            let left = c > 0 && caps[c - 1] > 0 ? h[c - 1] : Float.infinity
            let right = c < h.count - 1 && caps[c + 1] > 0 ? h[c + 1] : Float.infinity
            if left < h[c] - 0.3, left <= right { c -= 1 } else if right < h[c] - 0.3 { c += 1 } else { break }
        }
        let px = Float(c)

        if fuse {
            var best = -1
            var bestDistance = Float.infinity
            for i in grains.indices {
                let g = grains[i]
                guard abs(g.x - px) < g.r + r + 1.4 else { continue }
                let d = hypot(g.x - px, g.y - h[c])
                if d < g.r + r + 1.4, d < bestDistance, g.r * g.r + r * r <= SnowBed.maxGrain * SnowBed.maxGrain {
                    best = i
                    bestDistance = d
                }
            }
            if best >= 0 {
                var g = grains[best]
                let grown = (g.r * g.r + r * r).squareRoot()
                let weight = r * r / (grown * grown)
                let y = g.y + (grown - g.r) * 0.55
                if y + grown <= caps[min(h.count - 1, max(0, Int(g.x)))] {
                    g.x += (px - g.x) * weight
                    g.y = y
                    g.r = grown
                    grains[best] = g
                    stamp(g)
                    return true
                }
            }
        }

        let y = rest(on: support(px, r, in: h), r)
        guard y + r <= caps[c] else { return false }
        let g = SnowGrain(x: px, y: y, r: r, tone: tone)
        grains.append(g)
        stamp(g)
        return true
    }

    /// Altındaki kar gidince üstteki tanecikler aşağı oturur, havada tanecik kalmaz.
    func resettle() {
        grains.sort { $0.y < $1.y }
        for c in h.indices { h[c] = 0 }
        for i in grains.indices {
            var g = grains[i]
            g.y = min(g.y, rest(on: support(g.x, g.r, in: h), g.r))
            grains[i] = g
            stamp(g)
        }
    }

    /// Bıçağın geçtiği aralıktaki karı kazır, kazınan miktarı döndürür.
    func scrape(from a: Float, to b: Float) -> Float {
        let lo = min(a, b), hi = max(a, b)
        var area: Float = 0
        var kept: [SnowGrain] = []
        kept.reserveCapacity(grains.count)
        for g in grains {
            if g.x >= lo, g.x <= hi { area += .pi * g.r * g.r } else { kept.append(g) }
        }
        guard kept.count != grains.count else { return 0 }
        grains = kept
        let c0 = max(0, Int(lo) - 5), c1 = min(h.count - 1, Int(hi) + 5)
        if c0 <= c1 {
            for c in c0...c1 { h[c] = 0 }
            for g in grains where g.x + g.r >= Float(c0) && g.x - g.r <= Float(c1) { stamp(g) }
        }
        return area
    }

    /// Testler için: altında desteği olmayan tanecik sayısı.
    var floatingCount: Int {
        grains.indices.filter { i in
            let g = grains[i]
            if g.y - g.r <= 0.3 { return false }   // doğrudan yüzeye oturuyor
            return !grains.indices.contains { j in
                guard j != i else { return false }
                let o = grains[j]
                return o.y < g.y && hypot(o.x - g.x, o.y - g.y) <= g.r + o.r + 0.6
            }
        }.count
    }
}

/// Bir pencerenin üst kenarındaki kar.
final class SnowLedge {
    static let cornerRadius: Float = 22
    static let holdInset: Float = 11

    let id: UInt32
    var frame: CGRect
    let bed: SnowBed
    var drop: [Float]
    var covered: [Bool]
    var vx: Float = 0
    var vy: Float = 0
    var missing = 0

    init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
        let n = max(2, Int(frame.width))
        bed = SnowBed(columns: n)
        drop = Array(repeating: 0, count: n)
        covered = Array(repeating: false, count: n)
    }

    var h: [Float] { bed.h }
    var mass: Float { bed.mass }
    var top: Float { Float(frame.minY) }
    var left: Float { Float(frame.minX) }
}

/// Zemindeki karı önüne katıp ekrandan çıkaran küreme aracı.
struct SnowPlow {
    static let bladeReach: Float = 68
    static let margin: Float = 190

    var x: Float
    var dir: Float
    var speed: Float = 0
    var wheel: Float = 0
    var pushed: Float = 0
    var clock: Float = 0
    var sprayDebt: Float = 0
}

/// Ekrandan bağımsız kar fiziği: taneler, topaklar, toz ve tutunan yığınlar.
final class SnowEngine {
    struct Particle {
        enum Kind: UInt8 { case flake, backdrop, clump, powder }
        var kind: Kind
        var x: Float, y: Float, vx: Float, vy: Float
        var r: Float, mass: Float
        var phase: Float, depth: Float, life: Float
        var lobes: UInt8 = 1
        var rollLedge: UInt32 = 0
        var rollDir: Float = 0
    }

    static let groundLimit: Float = 44
    static let ledgeLimit: Float = 16
    static let maxParticles = 3200
    static let maxFlakeRadius: Float = 2.3
    static let plowThreshold: Float = 0.5
    static let plowCooldown: Float = 60

    let width: Float, height: Float
    var intensity: Float = 0.5
    var limit: Float = 1 { didSet { if limit != oldValue { rebuildCaps() } } }
    var minimumTop: Float = 30
    var plowEnabled = false

    private let groundBed: SnowBed
    private(set) var ledges: [UInt32: SnowLedge] = [:]
    private var dormant: [UInt32: SnowLedge] = [:]
    private var order: [UInt32] = []
    private(set) var particles: [Particle] = []
    private(set) var melting = false
    private(set) var meltAlpha: Float = 1
    private(set) var lastMotion: Float = 1000
    private(set) var mergedFlakes = 0
    private(set) var plow: SnowPlow?
    private(set) var plowTrips = 0

    private var plowWait: Float = 0
    private var nextPlowDir: Float = 1
    private var time: Float = 0
    private var spawnDebt: Float = 0
    private var seed: UInt32
    private var spaceHoldUntil: Float = -1
    private var frameIndex = 0
    private var cellHead: [Int32] = []
    private var cellNext: [Int32] = []

    init(width: CGFloat, height: CGFloat, seed: UInt32 = 0x5EED1) {
        self.width = Float(width)
        self.height = Float(height)
        self.seed = seed
        groundBed = SnowBed(columns: max(2, Int(width) + 1))
        particles.reserveCapacity(Self.maxParticles + 64)
        rebuildCaps()
    }

    // MARK: - Durum

    var ground: [Float] { groundBed.h }
    var groundGrains: [SnowGrain] { groundBed.grains }
    var groundMass: Float { groundBed.mass }
    var ledgeMass: Float { ledges.values.reduce(0) { $0 + $1.mass } }
    var clumpCount: Int { particles.lazy.filter { $0.kind == .clump }.count }
    var isFinished: Bool { melting && particles.isEmpty && groundMass < 0.5 && ledgeMass < 0.5 }
    var isMoving: Bool { lastMotion < 0.6 }
    var ledgeLimitNow: Float { Self.ledgeLimit * limit }
    var groundLimitNow: Float { Self.groundLimit * limit }

    /// Zeminin sınırına göre doluluğu (0...1).
    var groundFill: Float {
        let capTotal = groundBed.caps.reduce(0, +)
        return capTotal > 0 ? groundBed.h.reduce(0, +) / capTotal : 0
    }

    func setMelting(_ on: Bool) {
        melting = on
        if !on { meltAlpha = 1 }
    }

    func noteSpaceChange() { spaceHoldUntil = time + 1.5 }

    // MARK: - Rastgelelik

    private func random() -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(seed) / Float(UInt32.max)
    }

    private func random(_ a: Float, _ b: Float) -> Float { a + (b - a) * random() }

    private func wave(_ i: Int, _ s: Float) -> Float {
        let x = Float(i)
        return 0.5 + 0.28 * sin(x * 0.024 + s) + 0.14 * sin(x * 0.065 + s * 2.3) + 0.08 * sin(x * 0.155 + s * 3.7)
    }

    private func rebuildCaps() {
        for i in groundBed.caps.indices { groundBed.caps[i] = groundLimitNow * (0.68 + 0.32 * wave(i, 1.7)) }
        trim(groundBed, ledge: nil)
        for l in ledges.values { buildCaps(l); trim(l.bed, ledge: l) }
        for l in dormant.values { buildCaps(l); trim(l.bed, ledge: nil) }
    }

    /// Yuvarlak köşede kar tutunmaz; kenara yaklaştıkça yığın alçalır.
    private func buildCaps(_ l: SnowLedge) {
        let n = l.bed.h.count, s = Float(l.id % 97) * 0.31
        let R = SnowLedge.cornerRadius, hold = SnowLedge.holdInset
        for i in 0..<n {
            let d = min(Float(i), Float(n - 1 - i))
            if d < R {
                let k = R - d
                l.drop[i] = R - max(0, R * R - k * k).squareRoot()
            } else {
                l.drop[i] = 0
            }
            l.bed.caps[i] = d < hold ? 0 : min(ledgeLimitNow * (0.78 + 0.22 * wave(i, s)), (d - hold) * 0.85 + 1.6)
        }
    }

    private func trim(_ bed: SnowBed, ledge: SnowLedge?) {
        var kept: [SnowGrain] = []
        kept.reserveCapacity(bed.grains.count)
        var removed = false
        for g in bed.grains {
            let c = max(0, min(bed.h.count - 1, Int(g.x)))
            if g.y + g.r <= bed.caps[c] + 0.01 {
                kept.append(g)
            } else {
                removed = true
                if let ledge { emitClump(area: .pi * g.r * g.r, x: ledge.left + g.x, y: ledge.top - g.y, vx: random(-30, 30), vy: random(-30, 10)) }
            }
        }
        if removed {
            bed.grains = kept
            bed.resettle()
        }
    }

    // MARK: - Pencereler

    /// Pencereler önden arkaya sıralı gelir.
    func apply(windows: [SnowWindow], dt: Float) {
        let dt = max(dt, 1.0 / 120)
        let usable = windows.filter { Float($0.frame.minY) >= minimumTop && $0.frame.width >= 100 }
        var seen = Set<UInt32>()
        for w in usable {
            seen.insert(w.id)
            if let l = ledges[w.id] {
                l.missing = 0
                update(l, to: w.frame, dt: dt)
            } else if let d = dormant.removeValue(forKey: w.id) {
                d.missing = 0
                ledges[w.id] = d
                if abs(d.frame.minX - w.frame.minX) >= 1 || abs(d.frame.minY - w.frame.minY) >= 1 || abs(d.frame.width - w.frame.width) >= 1 {
                    update(d, to: w.frame, dt: 1.0 / 60)
                    shed(d, fraction: 1, vx: 0, vy: 0)
                }
            } else {
                let l = SnowLedge(id: w.id, frame: w.frame)
                buildCaps(l)
                ledges[w.id] = l
            }
        }
        for (id, l) in ledges where !seen.contains(id) {
            l.missing += 1
            guard l.missing >= 2 else { continue }
            ledges[id] = nil
            if time < spaceHoldUntil {
                if dormant.count < 40 { dormant[id] = l }   // masaüstü değişti: kar pencereyle beklesin
            } else {
                shed(l, fraction: 1, vx: l.vx * 0.3, vy: 0)   // kapandı veya Dock'a indi
            }
        }
        order = usable.map(\.id)
        updateCoverage(usable)
    }

    private func updateCoverage(_ list: [SnowWindow]) {
        for (index, w) in list.enumerated() {
            guard let l = ledges[w.id] else { continue }
            let front = list[..<index].map(\.frame)
            for i in l.covered.indices {
                let x = CGFloat(l.left + Float(i))
                let base = CGPoint(x: x, y: CGFloat(l.top) - 2)
                let tip = CGPoint(x: x, y: CGFloat(l.top - max(l.bed.h[i], 1)))
                l.covered[i] = front.contains { $0.contains(base) || $0.contains(tip) }
            }
        }
    }

    private func update(_ l: SnowLedge, to f: CGRect, dt: Float) {
        let vx = Float(f.minX - l.frame.minX) / dt
        let vy = Float(f.minY - l.frame.minY) / dt
        let resized = abs(f.width - l.frame.width) > 0.5 || abs(f.height - l.frame.height) > 0.5
        if resized { resample(l, to: f) }
        let speed = hypot(vx, vy)
        let accel = hypot(vx - l.vx, vy - l.vy) / dt

        var fraction: Float = 0
        if speed > 70 { fraction += min(0.45, (speed - 70) / 2400) }
        if accel > 2600 { fraction += min(0.35, (accel - 2600) / 42000) }
        if resized { fraction = max(fraction, 0.035) }
        fraction *= vy > 0 ? 1.5 : (vy < 0 ? 0.6 : 1)     // aşağı inen pencerenin karı havada kalır
        fraction = min(0.9, fraction * min(dt * 60, 2))

        l.frame = f
        l.vx = vx
        l.vy = vy
        if speed > 5 || resized { lastMotion = 0 }
        if fraction > 0.002 { shed(l, fraction: fraction, vx: vx, vy: vy) }
    }

    /// Boyut değişince tanecikler ekrandaki yerinde kalır, kenardan taşanlar düşer.
    private func resample(_ l: SnowLedge, to f: CGRect) {
        let n = max(2, Int(f.width))
        let shift = Float(f.minX - l.frame.minX)
        let old = l.bed.grains
        l.bed.h = Array(repeating: 0, count: n)
        l.bed.caps = Array(repeating: 0, count: n)
        l.drop = Array(repeating: 0, count: n)
        l.covered = Array(repeating: false, count: n)
        buildCaps(l)
        var kept: [SnowGrain] = []
        kept.reserveCapacity(old.count)
        for var g in old {
            let worldX = l.left + g.x
            g.x -= shift
            let c = Int(g.x)
            if g.x >= 0, c < n, g.y + g.r <= l.bed.caps[c] + 0.5 {
                kept.append(g)
            } else {
                emitClump(area: .pi * g.r * g.r, x: worldX, y: l.top - g.y, vx: random(-45, 45), vy: random(-70, 10))
            }
        }
        l.bed.grains = kept
        l.bed.resettle()
    }

    /// Kopan komşu tanecikler birlikte yuvarlak bir topak olarak düşer.
    private func shed(_ l: SnowLedge, fraction: Float, vx: Float, vy: Float) {
        let bed = l.bed
        guard !bed.grains.isEmpty else { return }
        bed.grains.sort { $0.x < $1.x }
        let n = Float(max(bed.h.count - 1, 1))
        let tallest = max(bed.h.max() ?? 1, 1)
        var kept: [SnowGrain] = []
        kept.reserveCapacity(bed.grains.count)
        var area: Float = 0, sumX: Float = 0, sumY: Float = 0, startX: Float = 0

        func flush() {
            guard area > 0 else { return }
            emitClump(area: area, x: l.left + sumX / area, y: l.top - sumY / area,
                      vx: vx * 0.55 + random(-60, 60), vy: min(vy * 0.45, 260) + random(-120, 70))
            area = 0; sumX = 0; sumY = 0
        }

        for g in bed.grains {
            let pos = g.x / n
            let trailing = vx > 0 ? 1 - pos : (vx < 0 ? pos : 0.5)
            let height = g.y / tallest
            let chance = fraction >= 1 ? 1 : fraction * (0.55 + 1.1 * trailing) * (0.7 + 0.8 * height) * random(0.6, 1.3)
            guard random() < chance else { kept.append(g); continue }
            let a = Float.pi * g.r * g.r
            if area > 0, g.x - startX > random(7, 20) || area > 70 { flush() }
            if area == 0 { startX = g.x }
            area += a; sumX += g.x * a; sumY += g.y * a
        }
        flush()
        if kept.count != bed.grains.count {
            bed.grains = kept
            bed.resettle()
        }
    }

    private func emitClump(area: Float, x: Float, y: Float, vx: Float, vy: Float) {
        guard area > 0.01 else { return }
        if particles.count >= Self.maxParticles {
            _ = scatter(area: area, x: x, spread: 6, bed: groundBed, originX: 0)
            return
        }
        let r = max(1.1, min(7, (area / .pi).squareRoot()))
        particles.append(Particle(kind: .clump, x: x + random(-3, 3), y: y + random(-3, 3), vx: vx, vy: vy, r: r, mass: area,
                                  phase: random(0, 6.28), depth: 1, life: 1, lobes: UInt8(min(6, 2 + Int(r)))))
    }

    /// Çarpan topak parçalanır, parçaları yüzeye tutunur. Sığmayan miktarı döndürür.
    private func scatter(area: Float, x: Float, spread: Float, bed: SnowBed, originX: Float) -> Float {
        var left = area, missed: Float = 0
        while left > 0.2 {
            let r = min(random(1.4, 3.3), (left / .pi).squareRoot())
            let a = Float.pi * r * r
            left -= a
            let px = x - originX + random(-spread, spread)
            if !bed.add(x: px, r: max(0.7, r), tone: random(0.93, 1), fuse: false) { missed += a }
        }
        return missed
    }

    // MARK: - Küreme aracı

    private func updatePlow(_ dt: Float) {
        plowWait = max(0, plowWait - dt)
        if melting { plow = nil; return }
        if plow == nil {
            guard plowEnabled, plowWait <= 0, frameIndex % 30 == 0, groundFill >= Self.plowThreshold else { return }
            plow = SnowPlow(x: nextPlowDir > 0 ? -SnowPlow.margin : width + SnowPlow.margin, dir: nextPlowDir)
            nextPlowDir = -nextPlowDir
            plowTrips += 1
        }
        guard var p = plow else { return }
        p.clock += dt
        p.speed = min(170, p.speed + 120 * dt)
        let step = p.speed * dt * p.dir
        let bladeBefore = p.x + p.dir * SnowPlow.bladeReach
        p.x += step
        p.wheel += step / 11
        let bladeAfter = p.x + p.dir * SnowPlow.bladeReach
        p.pushed += groundBed.scrape(from: bladeBefore, to: bladeAfter)

        // Bıçağın önünde biriken kar yukarı ve ileri savrulur.
        p.sprayDebt += min(1, p.pushed / 500) * 46 * dt
        while p.sprayDebt >= 1, p.pushed > 8 {
            p.sprayDebt -= 1
            let area = min(p.pushed * 0.5, random(5, 22))
            p.pushed -= area
            emitClump(area: area, x: bladeAfter + p.dir * random(2, 16), y: height - random(10, 34),
                      vx: p.dir * random(150, 340), vy: random(-400, -170))
        }
        // Egzoz dumanı
        if Int(p.clock * 7) != Int((p.clock - dt) * 7), particles.count < Self.maxParticles {
            particles.append(Particle(kind: .powder, x: p.x - p.dir * 54, y: height - 20, vx: -p.dir * random(20, 45), vy: random(-70, -40),
                                      r: random(1, 2), mass: 0, phase: 0, depth: 1, life: 1))
        }
        let gone = p.dir > 0 ? p.x > width + SnowPlow.margin : p.x < -SnowPlow.margin
        if gone {
            plow = nil
            plowWait = Self.plowCooldown
        } else {
            plow = p
        }
    }

    // MARK: - Simülasyon

    func step(_ dtIn: Float) {
        let dt = min(dtIn, 1.0 / 24)
        time += dt
        lastMotion += dt
        frameIndex &+= 1
        let wind = 13 * sin(time * 0.13) + 8 * sin(time * 0.37 + 1.2)

        if melting {
            meltAlpha = max(0, meltAlpha - dt * 0.55)
            let k = exp(-dt * 1.4)
            melt(groundBed, k)
            for l in ledges.values { melt(l.bed, k) }
            if meltAlpha <= 0 {
                particles.removeAll(keepingCapacity: true)
                groundBed.grains.removeAll()
                for l in ledges.values { l.bed.grains.removeAll() }
            }
        } else {
            spawnDebt += (18 + intensity * 150) * dt
            while spawnDebt >= 1 {
                spawnDebt -= 1
                if particles.count < Self.maxParticles - 400 { spawnFlake() }
            }
        }
        updatePlow(dt)

        var i = 0
        while i < particles.count {
            var p = particles[i]   // çarpışmada yeni toz parçacıkları eklenebilir
            if advance(&p, dt: dt, wind: wind) {
                particles[i] = p
                i += 1
            } else {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
            }
        }
        if frameIndex % 2 == 0 { mergeFlakes() }
    }

    private func melt(_ bed: SnowBed, _ k: Float) {
        for i in bed.grains.indices { bed.grains[i].r *= k; bed.grains[i].y *= k }
        bed.grains.removeAll { $0.r < 0.3 }
        for c in bed.h.indices { bed.h[c] *= k }
    }

    private func spawnFlake() {
        let back = random() < 0.32
        let depth = back ? random(0.15, 0.4) : random(0.45, 1)
        let r = back ? 0.28 + depth * 0.5 : 0.45 + depth * 0.75
        particles.append(Particle(kind: back ? .backdrop : .flake, x: random(-30, width + 30), y: random(-14, -4),
                                  vx: 0, vy: 0, r: r, mass: .pi * r * r, phase: random(0, 6.28), depth: depth, life: 1))
    }

    /// Havada birbirine değen kar taneleri tutunup daha büyük bir tane olur.
    private func mergeFlakes() {
        let cell: Float = 10
        let cols = Int(width / cell) + 12, rows = Int(height / cell) + 12
        if cellHead.count != cols * rows { cellHead = Array(repeating: -1, count: cols * rows) }
        for i in cellHead.indices { cellHead[i] = -1 }
        if cellNext.count < particles.count { cellNext = Array(repeating: -1, count: particles.count + 256) }
        var removed = false

        for i in particles.indices where particles[i].kind == .flake && particles[i].life > 0 {
            let p = particles[i]
            let cx = Int((p.x + 40) / cell), cy = Int((p.y + 40) / cell)
            guard p.x > -30, p.y > -30, cx >= 1, cy >= 1, cx < cols - 1, cy < rows - 1 else { continue }
            var merged = false
            search: for ny in (cy - 1)...(cy + 1) {
                for nx in (cx - 1)...(cx + 1) {
                    var j = cellHead[ny * cols + nx]
                    while j >= 0 {
                        let q = particles[Int(j)]
                        let grown = (p.r * p.r + q.r * q.r).squareRoot()
                        if grown <= Self.maxFlakeRadius, hypot(p.x - q.x, p.y - q.y) < p.r + q.r + 2.4, random() < 0.5 {
                            var o = q
                            o.x = (q.x * q.mass + p.x * p.mass) / (q.mass + p.mass)
                            o.y = (q.y * q.mass + p.y * p.mass) / (q.mass + p.mass)
                            o.mass += p.mass
                            o.r = grown
                            o.lobes = min(5, q.lobes + p.lobes)
                            o.depth = max(q.depth, p.depth)
                            particles[Int(j)] = o
                            particles[i].life = -1
                            merged = true
                            removed = true
                            mergedFlakes += 1
                            break search
                        }
                        j = cellNext[Int(j)]
                    }
                }
            }
            if !merged {
                let key = cy * cols + cx
                cellNext[i] = cellHead[key]
                cellHead[key] = Int32(i)
            }
        }
        if removed { particles.removeAll { $0.life < 0 } }
    }

    /// Parçacığı bir adım ilerletir; yaşamaya devam ediyorsa true döner.
    private func advance(_ p: inout Particle, dt: Float, wind: Float) -> Bool {
        let y0 = p.y
        switch p.kind {
        case .flake, .backdrop:
            let fall = 30 + 52 * p.depth + 12 * p.r   // büyüyen tane daha hızlı düşer
            p.vy += (fall - p.vy) * min(1, dt * 3)
            p.vx = wind * (0.4 + p.depth) + cos(time * (0.9 + p.depth) + p.phase) * (8 + 11 * p.depth)
        case .clump:
            if p.rollLedge != 0 { return roll(&p, dt: dt) }
            p.vy += 980 * dt
            let drag = max(0, 1 - 0.32 * dt)
            p.vx *= drag; p.vy *= drag
        case .powder:
            p.vy += 420 * dt
            let drag = max(0, 1 - 2.4 * dt)
            p.vx *= drag; p.vy *= drag
            p.life -= dt * 1.9
            if p.life <= 0 { return false }
        }
        p.x += p.vx * dt
        p.y += p.vy * dt

        if p.x < -40 || p.x > width + 40 { return false }
        if p.kind == .backdrop { return p.y < height + 6 }
        if p.kind == .powder { return p.y < height + 4 }
        guard p.vy > 0 else { return true }

        // Önce pencerelerin üst kenarları, sonra zemin
        let radius = p.kind == .clump ? p.r * 0.6 : 0
        var hit: SnowLedge?
        var hitY = Float.greatestFiniteMagnitude
        for id in order {
            guard let l = ledges[id] else { continue }
            let offset = p.x - l.left
            guard offset >= 0 else { continue }
            let c = Int(offset)
            guard c < l.bed.h.count, l.bed.caps[c] > 0, !l.covered[c] else { continue }
            let s = l.top + l.drop[c] - l.bed.h[c]
            if y0 + radius <= s + 1, p.y + radius >= s, s < hitY { hitY = s; hit = l }
        }
        let g = max(0, min(groundBed.h.count - 1, Int(max(p.x, 0))))
        let floor = height - groundBed.h[g]
        if p.y + radius >= floor, floor < hitY { return land(&p, bed: groundBed, originX: 0, ledge: nil, surface: floor) }
        if let l = hit { return land(&p, bed: l.bed, originX: l.left, ledge: l, surface: hitY) }
        return p.y < height + 12
    }

    private func land(_ p: inout Particle, bed: SnowBed, originX: Float, ledge: SnowLedge?, surface: Float) -> Bool {
        if melting { return false }
        if p.kind == .flake {
            // Tanelerin bir kısmı değdiği an erir, kalanı yüzeye tutunur.
            guard random() < 0.45 else { return false }
            bed.add(x: p.x - originX, r: max(0.75, p.r * 1.1), tone: random(0.94, 1), fuse: true)
            return false
        }
        let missed = scatter(area: p.mass, x: p.x, spread: max(3, p.r * 1.7), bed: bed, originX: originX)
        splash(p, surface: surface)
        if let ledge, missed > 4 {   // yer kalmadı: topak kenara yuvarlanıp düşer
            p.mass = missed
            p.r = max(1.1, min(7, (missed / .pi).squareRoot()))
            p.rollLedge = ledge.id
            p.rollDir = p.x - ledge.left < Float(ledge.bed.h.count) / 2 ? -1 : 1
            p.vy = 0
            return true
        }
        return false
    }

    private func roll(_ p: inout Particle, dt: Float) -> Bool {
        guard let l = ledges[p.rollLedge] else { p.rollLedge = 0; return true }
        p.x += p.rollDir * 150 * dt
        p.phase += p.rollDir * dt * 150 / max(p.r, 1)
        let offset = p.x - l.left
        let c = Int(max(offset, 0))
        guard offset >= 0, c < l.bed.h.count, l.bed.caps[c] > 0 else {
            p.rollLedge = 0
            p.vx = p.rollDir * 70
            p.vy = 10
            return true
        }
        p.y = l.top + l.drop[c] - l.bed.h[c] - p.r * 0.7
        return true
    }

    private func splash(_ p: Particle, surface: Float) {
        let count = min(8, Int(2 + p.r))
        for _ in 0..<count where particles.count < Self.maxParticles {
            let a = random(-2.7, -0.45)
            let v = random(35, 70 + p.r * 16)
            particles.append(Particle(kind: .powder, x: p.x + random(-p.r, p.r), y: surface - 1, vx: cos(a) * v, vy: sin(a) * v,
                                      r: random(0.4, 1), mass: 0, phase: 0, depth: 1, life: random(0.45, 1)))
        }
    }

    // MARK: - Çizim verisi

    /// Her köşe: x, y, u, v, r, g, b, a, yumuşaklık (9 Float).
    func buildVertices(into out: UnsafeMutablePointer<Float>, capacity: Int) -> Int {
        var n = 0
        let alpha = meltAlpha

        @inline(__always) func vc(_ x: Float, _ y: Float, _ u: Float, _ w: Float, _ r: Float, _ g: Float, _ b: Float, _ a: Float, _ soft: Float) {
            let p = out + n * 9
            p[0] = x; p[1] = y; p[2] = u; p[3] = w
            p[4] = r * a; p[5] = g * a; p[6] = min(1, b) * a; p[7] = a; p[8] = soft
            n += 1
        }
        @inline(__always) func v(_ x: Float, _ y: Float, _ u: Float, _ w: Float, _ c: Float, _ b: Float, _ a: Float, _ soft: Float) {
            vc(x, y, u, w, c, c, b, a, soft)
        }
        @inline(__always) func ball(_ x: Float, _ y: Float, _ s: Float, _ c: Float, _ b: Float, _ a: Float, _ soft: Float) {
            let x0 = x - s, x1 = x + s, y0 = y - s, y1 = y + s
            v(x0, y0, 0, 0, c, b, a, soft); v(x1, y0, 1, 0, c, b, a, soft); v(x0, y1, 0, 1, c, b, a, soft)
            v(x1, y0, 1, 0, c, b, a, soft); v(x1, y1, 1, 1, c, b, a, soft); v(x0, y1, 0, 1, c, b, a, soft)
        }
        typealias RGB = (Float, Float, Float)
        @inline(__always) func soft(_ x: Float, _ y: Float, _ s: Float, _ c: RGB, _ a: Float, _ edge: Float = 0) {
            let x0 = x - s, x1 = x + s, y0 = y - s, y1 = y + s
            vc(x0, y0, 0, 0, c.0, c.1, c.2, a, edge); vc(x1, y0, 1, 0, c.0, c.1, c.2, a, edge); vc(x0, y1, 0, 1, c.0, c.1, c.2, a, edge)
            vc(x1, y0, 1, 0, c.0, c.1, c.2, a, edge); vc(x1, y1, 1, 1, c.0, c.1, c.2, a, edge); vc(x0, y1, 0, 1, c.0, c.1, c.2, a, edge)
        }
        @inline(__always) func band(_ x0: Float, _ x1: Float, _ t0: Float, _ t1: Float, _ top: RGB, _ topA: Float,
                                    _ b0: Float, _ b1: Float, _ bottom: RGB, _ bottomA: Float) {
            vc(x0, t0, 0, 0, top.0, top.1, top.2, topA, -1); vc(x1, t1, 0, 0, top.0, top.1, top.2, topA, -1)
            vc(x0, b0, 0, 0, bottom.0, bottom.1, bottom.2, bottomA, -1)
            vc(x1, t1, 0, 0, top.0, top.1, top.2, topA, -1); vc(x1, b1, 0, 0, bottom.0, bottom.1, bottom.2, bottomA, -1)
            vc(x0, b0, 0, 0, bottom.0, bottom.1, bottom.2, bottomA, -1)
        }

        func draw(_ bed: SnowBed, originX: Float, baseY: Float, drop: [Float]?, covered: [Bool]?, onWindow: Bool) {
            let d = bed.surface()
            let count = d.count
            guard count > 12 else { return }
            let deep: RGB = (0.79, 0.85, 0.95)

            // Kar kütlesi: üstü parlak, çukurları ve derinliği hafif mavi gölgeli
            var c = 0
            while c + 2 < count {
                guard n + 36 < capacity else { return }
                defer { c += 2 }
                let a = d[c], b = d[c + 2]
                if a < 0.25, b < 0.25 { continue }
                if let covered, covered[c] || covered[c + 2] { continue }
                let x0 = originX + Float(c), x1 = x0 + 2
                let base0 = baseY + (drop?[c] ?? 0), base1 = baseY + (drop?[c + 2] ?? 0)
                let t0 = base0 - a, t1 = base1 - b

                let slope = (d[min(count - 1, c + 7)] - d[max(0, c - 6)]) / 13   // dikey çizgi oluşmasın diye geniş bakılır
                let lit = max(0, min(1, 0.62 + slope * 0.6))
                let around = (d[max(0, c - 12)] + d[min(count - 1, c + 12)]) / 2
                let hollow = max(0, min(0.32, (around - a) * 0.075))
                let rim: RGB = (0.90 + 0.10 * lit - hollow * 0.55, 0.94 + 0.06 * lit - hollow * 0.4, 1 - hollow * 0.12)
                let body: RGB = (0.915, 0.95, 0.995)
                let thin = min(1, max(a, b) / 1.4) * alpha

                band(x0, x1, t0 - 1.1, t1 - 1.1, rim, 0, t0, t1, rim, thin)            // yumuşak üst kenar
                let m0 = t0 + min(a * 0.5, 6), m1 = t1 + min(b * 0.5, 6)
                band(x0, x1, t0, t1, rim, thin, m0, m1, body, thin)
                let blend = min(1, max(a, b) / 26)
                let low: RGB = (body.0 + (deep.0 - body.0) * blend, body.1 + (deep.1 - body.1) * blend, body.2 + (deep.2 - body.2) * blend)
                band(x0, x1, m0, m1, body, thin, base0 + 0.6, base1 + 0.6, low, thin)
                if onWindow, max(a, b) > 1 {                                           // pencereye düşen gölge
                    band(x0, x1, base0 + 0.6, base1 + 0.6, (0, 0, 0), 0.2 * alpha, base0 + 5, base1 + 5, (0, 0, 0), 0)
                }
            }

            // İçteki topaklar: belli belirsiz aydınlık ve gölgeli lekeler
            for i in stride(from: 0, to: bed.grains.count, by: 2) {
                guard n + 12 < capacity else { return }
                let g = bed.grains[i]
                let k = max(0, min(count - 1, Int(max(g.x, 0))))
                let top = d[k]
                if top < 4 { continue }
                if let covered, covered[k] { continue }
                let y = min(g.y, top - 3)
                let R = min(g.r * 2.7, max(2.5, top - y))
                let py = baseY + (drop?[k] ?? 0) - y
                if Int(g.x * 7 + g.tone * 90) % 3 == 0 {
                    soft(originX + g.x + 0.8, py + 1, R, (0.70, 0.78, 0.93), 0.2 * alpha)
                } else {
                    soft(originX + g.x, py, R * 0.86, (1, 1, 1), 0.34 * alpha)
                }
            }

            // Tepeciklerin ışık alan yüzü ve yanındaki gölge
            var p = 8
            while p + 8 < count {
                defer { p += 3 }
                guard n + 12 < capacity else { return }
                let top = d[p]
                guard top > 3, top > d[p - 6] + 0.5, top >= d[p + 6] + 0.5, top >= d[p - 2], top >= d[p + 2] else { continue }
                if let covered, covered[p] { continue }
                let x = originX + Float(p), y = baseY + (drop?[p] ?? 0) - top
                let size = min(top * 0.55, 9)
                soft(x + size * 0.9, y + size * 0.85, size, (0.68, 0.77, 0.93), 0.26 * alpha)
                soft(x - size * 0.2, y + size * 0.55, size * 0.95, (1, 1, 1), 0.72 * alpha)
            }

            // Buz kristallerinin küçük parıltıları
            for i in stride(from: 0, to: bed.grains.count, by: 9) {
                guard n + 6 < capacity else { return }
                let g = bed.grains[i]
                let k = max(0, min(count - 1, Int(max(g.x, 0))))
                let top = d[k]
                guard top > 1.5, g.y > top - 7 else { continue }
                if let covered, covered[k] { continue }
                let twinkle = sin(time * (1.1 + g.tone * 1.7) + g.x * 2.3)
                guard twinkle > 0.8 else { continue }
                soft(originX + g.x, baseY + (drop?[k] ?? 0) - min(g.y, top - 1), 1.1, (1, 1, 1), (twinkle - 0.8) * 5 * alpha, 0.1)
            }
        }

        for id in order.reversed() {
            if let l = ledges[id] { draw(l.bed, originX: l.left, baseY: l.top, drop: l.drop, covered: l.covered, onWindow: true) }
        }
        draw(groundBed, originX: 0, baseY: height, drop: nil, covered: nil, onWindow: false)

        // Küreme aracı (dx ileri, dy yerden yukarı)
        if let p = plow, n + 900 < capacity {
            let bounce = sin(p.clock * 19) * 0.6
            let X = { (dx: Float) in p.x + p.dir * dx }
            let Y = { (dy: Float) in self.height - dy - bounce }
            func poly(_ a: (Float, Float), _ b: (Float, Float), _ c: (Float, Float), _ d: (Float, Float), _ col: (Float, Float, Float)) {
                let pts = [a, b, c, a, c, d]
                for q in pts { vc(X(q.0), Y(q.1), 0, 0, col.0, col.1, col.2, alpha, -1) }
            }
            func rect(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ col: (Float, Float, Float)) {
                poly((x0, y0), (x1, y0), (x1, y1), (x0, y1), col)
            }
            func disc(_ dx: Float, _ dy: Float, _ s: Float, _ col: (Float, Float, Float), _ a: Float = 1, _ soft: Float = 0.86) {
                let x = X(dx), y = Y(dy), A = a * alpha
                let x0 = x - s, x1 = x + s, y0 = y - s, y1 = y + s
                vc(x0, y0, 0, 0, col.0, col.1, col.2, A, soft); vc(x1, y0, 1, 0, col.0, col.1, col.2, A, soft); vc(x0, y1, 0, 1, col.0, col.1, col.2, A, soft)
                vc(x1, y0, 1, 0, col.0, col.1, col.2, A, soft); vc(x1, y1, 1, 1, col.0, col.1, col.2, A, soft); vc(x0, y1, 0, 1, col.0, col.1, col.2, A, soft)
            }
            let orange: (Float, Float, Float) = (0.95, 0.47, 0.13), deep: (Float, Float, Float) = (0.78, 0.33, 0.08)
            let dark: (Float, Float, Float) = (0.15, 0.16, 0.19), yellow: (Float, Float, Float) = (0.99, 0.78, 0.13)
            let white: (Float, Float, Float) = (0.97, 0.97, 0.96), glass: (Float, Float, Float) = (0.60, 0.85, 0.96)

            disc(-4, -1, 62, (0, 0, 0), 0.16, 0.2)                       // yerdeki gölge
            rect(-54, 10, 46, 18, dark)                                  // şasi
            rect(-54, 18, -8, 40, orange)                                // arka kasa
            rect(-56, 39, -6, 43, deep)
            rect(-54, 25, -8, 30, white)
            for s in stride(from: Float(-50), to: -10, by: 14) { rect(s, 25, s + 7, 30, deep) }
            rect(-4, 18, 36, 47, orange)                                 // kabin
            disc(1, 46, 5, orange); disc(31, 46, 5, orange)
            rect(1, 46, 31, 51, orange)
            rect(8, 29, 32, 44, glass)                                   // cam
            disc(17, 34, 5.5, (0.98, 0.78, 0.62))                        // sürücü
            disc(19, 35, 0.9, dark)
            rect(11.5, 38, 22.5, 40, white)
            poly((12.5, 40), (21.5, 40), (15, 47), (15, 47), (0.86, 0.13, 0.15))   // bere
            disc(14.5, 47, 2, white)
            rect(8, 41, 32, 44, (0.74, 0.92, 0.99))
            rect(36, 18, 47, 33, deep)                                   // kaput
            disc(46, 26, 3, (1, 0.96, 0.7))
            disc(50, 26, 11, (1, 0.93, 0.6), 0.3, 0)                     // far ışığı
            rect(13, 51, 19, 54, dark)                                   // tepe lambası
            let blink = sin(p.clock * 11) > 0
            disc(16, 57, 3.6, blink ? (1, 0.72, 0.12) : (0.72, 0.42, 0.08))
            if blink { disc(16, 57, 14, (1, 0.7, 0.1), 0.42, 0) }

            for wx in [Float(-33), 24] {                                 // tekerlekler
                disc(wx, 11, 11.5, dark)
                disc(wx, 11, 5.6, (0.72, 0.74, 0.78))
                for k in 0..<3 {
                    let a = p.wheel + Float(k) * 2.094
                    disc(wx + cos(a) * 3.3, 11 + sin(a) * 3.3, 1.2, dark)
                }
            }

            rect(44, 11, 57, 16, dark)                                   // bıçak kolu
            poly((56, 1), (68, 0), (73, 38), (60, 39), yellow)           // bıçak
            for s in 0..<4 {
                let y0 = Float(s) * 10 + 3
                poly((57.5, y0), (69.5, y0 - 1), (70.5, y0 + 4), (58.2, y0 + 5), dark)
            }
            poly((55.5, 0), (69, 0), (69, 3), (55.5, 3), (0.62, 0.64, 0.68))

            // Bıçağın önünde sürüklenen kar yığını
            let pile = min(1, p.pushed / 420)
            if pile > 0.02 {
                let R = 7 + pile * 16
                for k in 0..<9 {
                    let t = Float(k) / 8
                    let wobble = sin(p.clock * 9 + Float(k) * 1.7) * 1.4
                    let dx = 72 + t * R * 1.5 + wobble, dy = R * (0.72 - t * 0.52) * (k % 2 == 0 ? 1 : 0.62)
                    disc(dx, dy + 1, R * (0.52 - t * 0.2), (0.85, 0.90, 0.97), 1, 0.4)
                    disc(dx - 0.5, dy + 2, R * (0.44 - t * 0.18), white, 1, 0.35)
                }
            }
        }

        for p in particles {
            guard n + 42 < capacity else { break }
            switch p.kind {
            case .flake:
                let a = (0.6 + 0.4 * p.depth) * alpha
                if p.lobes <= 1 {
                    ball(p.x, p.y, p.r * 1.5, 1, 1, a, 0.3)
                } else {
                    // Birleşmiş tane: birbirine yapışık küçük yuvarlaklar
                    let parts = Int(p.lobes)
                    let lobe = p.r * 0.72
                    for k in 0..<parts {
                        let t = p.phase + Float(k) * 2.4
                        ball(p.x + cos(t) * p.r * 0.55, p.y + sin(t) * p.r * 0.55, lobe * 1.25, 1, 1, a, 0.42)
                    }
                }
            case .backdrop:
                ball(p.x, p.y, p.r * 1.5, 1, 1, (0.2 + 0.4 * p.depth) * alpha, 0)
            case .clump:
                let parts = max(5, Int(p.lobes) + 2)
                ball(p.x + p.r * 0.1, p.y + p.r * 0.2, p.r * 1.02, 0.84, 0.95, alpha, 0.45)
                for k in 0..<parts {
                    let t = p.phase + Float(k) * 2.4
                    let d = p.r * (0.3 + 0.17 * Float(k % 3))
                    let size = p.r * (0.42 + 0.12 * Float((k * 2) % 3))
                    ball(p.x + cos(t) * d, p.y + sin(t) * d, size, 1, 1, alpha, 0.42)
                }
            case .powder:
                ball(p.x, p.y, p.r * 1.3, 1, 1, max(0, p.life) * 0.8 * alpha, 0.2)
            }
        }
        return n
    }
}
