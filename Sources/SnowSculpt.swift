import CoreGraphics
import Foundation

// MARK: - Modeller

/// Kardan adamın süsleri.
struct SnowDecor: OptionSet, Hashable {
    let rawValue: UInt8
    static let face = SnowDecor(rawValue: 1)
    static let nose = SnowDecor(rawValue: 2)
    static let arms = SnowDecor(rawValue: 4)
    static let hat = SnowDecor(rawValue: 8)
    static let scarf = SnowDecor(rawValue: 16)
    static let buttons = SnowDecor(rawValue: 32)

    static let menu: [(SnowDecor, String)] = [
        (.face, "Gözler ve gülümseme"), (.nose, "Havuç burun"), (.arms, "Dal kollar"),
        (.buttons, "Kömür düğmeler"), (.hat, "Şapka"), (.scarf, "Atkı"),
    ]
}

struct SnowBall {
    enum Support: Equatable {
        case none
        case ground
        case ledge(UInt32, Float)    // pencere kimliği, pencerenin solundan uzaklık
        case ball(Int, Float)        // alttaki top, ona göre yatay kayma
    }

    let id: Int
    var x: Float, y: Float, r: Float
    var vx: Float = 0, vy: Float = 0
    var spin: Float = 0
    var squash: Float = 0       // çarpınca anlık ezilme
    var flat: Float = 0         // kalıcı ezilme: orta yükseklikten düşen top basıklaşır
    var held = false
    var hidden = false
    var custom = false          // kullanıcı süslerini kendisi seçti: otomatik süsleme dokunmaz
    var support: Support = .none
    var decor: SnowDecor = []
    let seed: Float
}

/// Yüksekten düşüp dağılan topların bıraktığı, yer çekimiyle yayılan kar yığını.
struct SnowHeap {
    static let aspect: Float = 0.42     // yayılmış yığının yüksekliği / yarı genişliği

    let id: Int
    var x: Float
    var base: Float                     // oturduğu yüzey
    var area: Float
    var settle: Float = 0               // 0: yeni çöktü, 1: yayıldı
    var startW: Float, startH: Float
    var decor: SnowDecor
    let seed: Float

    var restW: Float { (area / (1.57 * Self.aspect)).squareRoot() }

    var shape: (w: Float, h: Float) {
        let t = min(1, settle), e = 1 - (1 - t) * (1 - t) * (1 - t)
        let W = restW, H = W * Self.aspect
        return (startW + (W - startW) * e, startH + (H - startH) * e)
    }

    /// Yığının altındaki zemin: yığın çukura ve kazınmış ize dökülür, tek bir sütuna takılmaz.
    static func floor(at px: Float, ground: [Float], screenHeight: Float) -> Float {
        let c = Int(px)
        let a = max(0, c - 8), b = min(ground.count - 1, c + 8)
        guard a <= b else { return screenHeight }
        var sum: Float = 0
        for i in a...b { sum += ground[i] }
        return screenHeight - sum / Float(b - a + 1)
    }

    func top(at px: Float, ground: [Float], screenHeight: Float) -> Float {
        Self.floor(at: px, ground: ground, screenHeight: screenHeight) - height(at: px)
    }

    func height(at px: Float) -> Float {
        let (w, h) = shape
        let d = (px - x) / max(w, 1)
        guard abs(d) < 1 else { return 0 }
        let k = 1 - d * d
        return max(0, h * pow(k, 0.7) * (1 + 0.08 * sin(d * 9 + seed) + 0.05 * sin(d * 23 + seed * 1.7)))
    }
}

/// Fareden kar motoruna giden komutlar (motor koordinatları: sol üst köşe, y aşağı).
enum SnowInput {
    case grab(CGPoint)
    case move(CGPoint)
    case release(CGVector)
    case decorate(Int, SnowDecor)
    case shatter(Int)
}

/// Fare imlecinin karın üstünde olup olmadığını ana iş parçacığında sormak için motorun özeti.
struct SnowGrabMap {
    enum Hit: Equatable {
        case ball(Int, SnowDecor)
        case snow
    }
    struct Ledge {
        let left: Float, top: Float
        let h: [Float], drop: [Float]
        let covered: [Bool]
    }

    static let minDepth: Float = 4      // ince kar tozu tıklamaları engellemesin
    var height: Float = 0
    var ground: [Float] = []
    var ledges: [Ledge] = []
    var heaps: [SnowHeap] = []
    var balls: [(id: Int, x: Float, y: Float, r: Float, decor: SnowDecor)] = []

    func hit(_ p: CGPoint) -> Hit? {
        let x = Float(p.x), y = Float(p.y)
        for b in balls.reversed() where hypot(b.x - x, b.y - y) <= b.r + 4 { return .ball(b.id, b.decor) }
        for h in heaps {
            let t = h.height(at: x)
            let top = h.top(at: x, ground: ground, screenHeight: height)
            if t > 3, y >= top - 3, y <= top + t + 2 { return .snow }
        }
        let c = Int(x)
        guard x >= 0 else { return nil }
        if c < ground.count, ground[c] >= Self.minDepth, y >= height - ground[c] - 3 { return .snow }
        for l in ledges {
            let o = Int(x - l.left)
            guard x >= l.left, o < l.h.count, !l.covered[o], l.h[o] >= Self.minDepth else { continue }
            let base = l.top + l.drop[o]
            if y >= base - l.h[o] - 3, y <= base + 1 { return .snow }
        }
        return nil
    }
}

final class SnowSculpture {
    static let maxBalls = 30
    static let maxHeaps = 12
    static let maxRadius: Float = 95
    static let minRadius: Float = 8
    static let sink: Float = 0.12          // top karın içine hafifçe oturur
    static let dentSpeed: Float = 560      // bundan hızlı düşen top basıklaşır
    static let crushSpeed: Float = 900     // bundan hızlı düşen top yığına döner (yaklaşık 410 nk yükseklik)

    var balls: [SnowBall] = []
    var heaps: [SnowHeap] = []
    var heldId: Int?
    var target = CGPoint.zero
    var offset = CGPoint.zero
    var lastTarget: (Float, Float) = (0, 0)
    var nextId = 1
    private(set) var snowmen = 0
    private(set) var collapses = 0

    func index(_ id: Int) -> Int? { balls.firstIndex { $0.id == id } }
    func heapIndex(_ id: Int) -> Int? { heaps.firstIndex { $0.id == id } }
    func noteSnowman() { snowmen += 1 }
    func noteCollapse() { collapses += 1 }

    func makeId() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    /// Bu topun üstünde oturan bütün toplar (kafa, gövde...).
    func riders(of id: Int) -> [Int] {
        var out: [Int] = [], frontier = [id]
        while let cur = frontier.popLast() {
            for b in balls where !out.contains(b.id) {
                if case .ball(cur, _) = b.support { out.append(b.id); frontier.append(b.id) }
            }
        }
        return out
    }

    /// Topun bulunduğu kulenin en alttaki topu.
    func root(of id: Int) -> Int {
        var cur = id, seen: Set<Int> = []
        while seen.insert(cur).inserted, let i = index(cur), case .ball(let below, _) = balls[i].support { cur = below }
        return cur
    }
}

// MARK: - Fizik

extension SnowEngine {
    struct Surface {
        let y: Float
        let bed: SnowBed
        let originX: Float
        let ledge: SnowLedge?
        var heap: Int? = nil
    }

    private var lift: Float { 1 - SnowSculpture.sink }

    /// Verilen yüksekliğin altındaki ilk yüzey: kar yığını, bir pencerenin üst kenarı ya da zemin.
    func surface(below x: Float, from y: Float, reach: Float, groundOnly: Bool = false) -> Surface {
        let a = max(0, Int(x - reach)), b = min(groundBed.h.count - 1, Int(x + reach))
        var top: Float = 0
        if a <= b { for c in a...b { top = max(top, groundBed.h[c]) } }
        var best = Surface(y: height - top, bed: groundBed, originX: 0, ledge: nil)
        for h in sculpture.heaps {
            let t = max(h.height(at: x), h.height(at: x - reach), h.height(at: x + reach))
            let s = min(heapTop(h, x), heapTop(h, x - reach), heapTop(h, x + reach))
            if t > 0.5, groundOnly || s >= y - 1, s < best.y {
                best = Surface(y: s, bed: groundBed, originX: 0, ledge: nil, heap: h.id)
            }
        }
        guard !groundOnly else { return best }
        for id in order {
            guard let l = ledges[id] else { continue }
            let off = x - l.left, c = Int(off)
            guard off >= 0, c < l.bed.h.count, l.bed.caps[c] > 0, !l.covered[c] else { continue }
            let s = l.top + l.drop[c] - l.bed.h[c]
            if s >= y - 1, s < best.y { best = Surface(y: s, bed: l.bed, originX: l.left, ledge: l) }
        }
        return best
    }

    private func groundTop(_ x: Float, reach: Float) -> Float {
        let a = max(0, Int(x - reach)), b = min(groundBed.h.count - 1, Int(x + reach))
        var top: Float = 0
        if a <= b { for c in a...b { top = max(top, groundBed.h[c]) } }
        return height - top
    }

    func heapTop(_ h: SnowHeap, _ x: Float) -> Float { h.top(at: x, ground: groundBed.h, screenHeight: height) }

    /// Yığının oturduğu ortalama zemin: tek bir yüksek kar sütunu yığını havaya kaldırmasın.
    private func groundLevel(_ x: Float, reach: Float) -> Float {
        let a = max(0, Int(x - reach)), b = min(groundBed.h.count - 1, Int(x + reach))
        guard a <= b else { return height }
        var sum: Float = 0
        for c in a...b { sum += groundBed.h[c] }
        return height - sum / Float(b - a + 1)
    }

    /// İmlecin altında avuçlanabilecek kadar kar varsa onun yüzeyi.
    private func snowUnder(_ x: Float, _ y: Float) -> Surface? {
        for h in sculpture.heaps {
            let t = h.height(at: x)
            let top = heapTop(h, x)
            if t > 3, y >= top - 3, y <= top + t + 2 {
                return Surface(y: top, bed: groundBed, originX: 0, ledge: nil, heap: h.id)
            }
        }
        let c = Int(x)
        guard x >= 0, c < groundBed.h.count else { return nil }
        for id in order {
            guard let l = ledges[id] else { continue }
            let o = Int(x - l.left)
            guard x >= l.left, o < l.bed.h.count, !l.covered[o], l.bed.h[o] >= SnowGrabMap.minDepth else { continue }
            let base = l.top + l.drop[o]
            if y >= base - l.bed.h[o] - 3, y <= base + 1 { return Surface(y: base - l.bed.h[o], bed: l.bed, originX: l.left, ledge: l) }
        }
        if groundBed.h[c] >= SnowGrabMap.minDepth, y >= height - groundBed.h[c] - 3 {
            return Surface(y: height - groundBed.h[c], bed: groundBed, originX: 0, ledge: nil)
        }
        return nil
    }

    /// Yığından kar alır; yığın küçülür, çok azalınca zemine karışır.
    private func take(from heapId: Int, upTo want: Float) -> Float {
        let s = sculpture
        guard let i = s.heapIndex(heapId), want > 0 else { return 0 }
        let got = min(s.heaps[i].area, want)
        s.heaps[i].area -= got
        if s.heaps[i].area < 150 {
            let h = s.heaps.remove(at: i)
            if h.area > 1 { _ = scatterLeftover(h) }
        }
        return got
    }

    private func scatterLeftover(_ h: SnowHeap) -> Float {
        let pieces = max(1, Int(h.area / 40))
        for _ in 0..<min(pieces, 30) {
            emitClump(area: h.area / Float(min(pieces, 30)), x: h.x + random(-h.shape.w * 0.6, h.shape.w * 0.6),
                      y: h.base - random(2, 8), vx: random(-20, 20), vy: random(-30, 0))
        }
        return h.area
    }

    func handle(_ input: SnowInput) {
        let s = sculpture
        switch input {
        case .grab(let p):
            let x = Float(p.x), y = Float(p.y)
            s.target = p
            let hit = s.balls.indices.filter { !s.balls[$0].hidden && hypot(s.balls[$0].x - x, s.balls[$0].y - y) <= s.balls[$0].r + 4 }
                .min { hypot(s.balls[$0].x - x, s.balls[$0].y - y) / s.balls[$0].r < hypot(s.balls[$1].x - x, s.balls[$1].y - y) / s.balls[$1].r }
            if let i = hit {
                s.balls[i].held = true          // üstündeki toplar da onunla gelir
                s.balls[i].support = .none
                s.balls[i].vx = 0; s.balls[i].vy = 0
                s.lastTarget = (x, y)
                s.heldId = s.balls[i].id
                s.offset = CGPoint(x: CGFloat(s.balls[i].x - x), y: CGFloat(s.balls[i].y - y))
                return
            }
            guard !melting, s.balls.count < SnowSculpture.maxBalls, let under = snowUnder(x, y) else { return }
            let area: Float
            if let hid = under.heap {
                area = take(from: hid, upTo: 1400)
            } else {
                area = under.bed.scrape(from: x - under.originX - 9, to: x - under.originX + 9)
            }
            guard area > 20 else { return }
            let r = max(SnowSculpture.minRadius, (area / .pi).squareRoot())
            let ball = SnowBall(id: s.makeId(), x: x, y: under.y - r * lift, r: r, held: true, seed: random(0, 100))
            s.balls.append(ball)
            s.lastTarget = (x, y)
            s.heldId = ball.id
            s.offset = CGPoint(x: 0, y: CGFloat(ball.y - y))
            puff(x: x, y: under.y, count: 6, speed: 60)
        case .move(let p):
            s.target = p
        case .release(let v):
            guard let id = s.heldId, let i = s.index(id) else { s.heldId = nil; return }
            s.heldId = nil
            s.balls[i].held = false
            let speed = hypot(Float(v.dx), Float(v.dy)), cap: Float = 1700
            let k = speed > cap ? cap / speed : 1
            s.balls[i].vx = Float(v.dx) * k
            s.balls[i].vy = Float(v.dy) * k
        case .decorate(let id, let d):
            guard let i = s.index(id) else { return }
            s.balls[i].custom = true
            if s.balls[i].decor.contains(d) { s.balls[i].decor.remove(d) } else { s.balls[i].decor.insert(d) }
        case .shatter(let id):
            guard let i = s.index(id) else { return }
            let b = s.balls.remove(at: i)
            burst(b)
            if s.heldId == id { s.heldId = nil }
        }
    }

    func stepSculpture(_ dt: Float) {
        let s = sculpture
        stepHeaps(dt)
        guard !s.balls.isEmpty else { return }
        if melting {
            let k = exp(-dt * 1.3)
            for i in s.balls.indices { s.balls[i].r *= k }
            s.balls.removeAll { $0.r < 2.5 }
            if let id = s.heldId, s.index(id) == nil { s.heldId = nil }
        }
        var gone = Set<Int>()
        // Önce alttaki toplar, böylece üsttekiler güncel yerlerine oturur.
        for id in s.balls.sorted(by: { $0.y > $1.y }).map(\.id) {
            guard !gone.contains(id), let i = s.index(id) else { continue }
            var b = s.balls[i]
            b.squash *= exp(-dt * 9)
            if b.held {
                carry(&b, dt)
            } else {
                switch b.support {
                case .ground: rollOnGround(&b, dt)
                case .ledge(let lid, let off): sitOnLedge(&b, lid, off, dt)
                case .ball(let base, let dx): sitOnBall(&b, base, dx, dt)
                case .none: fall(&b, dt, gone: &gone)
                }
            }
            if b.y > height + b.r + 60 { gone.insert(b.id) }
            if let j = s.index(id) { s.balls[j] = b }
        }
        if !gone.isEmpty {
            s.balls.removeAll { gone.contains($0.id) }
            if let id = s.heldId, gone.contains(id) { s.heldId = nil }
        }
    }

    private func stepHeaps(_ dt: Float) {
        let s = sculpture
        guard !s.heaps.isEmpty else { return }
        for i in s.heaps.indices {
            s.heaps[i].settle = min(1, s.heaps[i].settle + dt / 0.5)
            s.heaps[i].base = groundLevel(s.heaps[i].x, reach: s.heaps[i].shape.w * 0.5)
            if melting { s.heaps[i].area *= exp(-dt * 1.3) }
        }
        s.heaps.removeAll { $0.area < (melting ? 40 : 1) }
        // Avuç kadar kalan yığın ayrı bir yığın gibi durmaz, zemindeki kara karışır.
        if !melting {
            for h in s.heaps where h.area < 400 && h.settle >= 1 { _ = scatterLeftover(h) }
            s.heaps.removeAll { $0.area < 400 && $0.settle >= 1 }
        }
        // Üst üste binen yığınlar birleşir.
        var i = 0
        while i < s.heaps.count {
            var j = i + 1
            while j < s.heaps.count {
                let a = s.heaps[i], b = s.heaps[j]
                if abs(a.x - b.x) < (a.shape.w + b.shape.w) * 0.45 {
                    let total = a.area + b.area
                    s.heaps[i].x = (a.x * a.area + b.x * b.area) / total
                    s.heaps[i].area = total
                    s.heaps[i].decor.formUnion(b.decor)
                    s.heaps.remove(at: j)
                } else {
                    j += 1
                }
            }
            i += 1
        }
    }

    /// Fareyle tutulan top imleci izler; kara değdikçe yuvarlanır ve karı üstüne toplayarak büyür.
    private func carry(_ b: inout SnowBall, _ dt: Float) {
        let s = sculpture
        let prevX = b.x, prevY = b.y
        b.x = min(max(Float(s.target.x + s.offset.x), b.r), width - b.r)
        b.y = min(Float(s.target.y + s.offset.y), height + b.r)
        b.hidden = false
        let riding = Set(s.riders(of: b.id))
        let others = s.balls.filter { $0.id != b.id && !$0.hidden && !riding.contains($0.id) }
        func overlaps(_ slack: Float) -> Bool {
            others.contains { hypot(b.x - $0.x, b.y - $0.y) < ($0.r + b.r) * slack }
        }
        for _ in 0..<4 where overlaps(0.9) {
            for o in others {
                let dx = b.x - o.x, dy = b.y - o.y
                let d = hypot(dx, dy), m = (b.r + o.r) * 0.9
                if d < m, d > 0.01 { b.x = o.x + dx / d * m; b.y = o.y + dy / d * m }
            }
        }
        let surf = surface(below: b.x, from: b.y, reach: b.r * 0.35)
        let rest = surf.y - b.r * lift
        // Yere yakın tutulan top karın üstünde kalır, kar kazındıkça onunla birlikte iner.
        if b.y > rest || rest - b.y < max(b.r * 0.5, 50) { b.y = rest }
        if overlaps(0.89) { b.x = prevX; b.y = prevY }   // iki topun arasına sıkışmasın

        // Sertçe sallanan kardan adamın üstündeki toplar düşer. İmlecin yumuşatılmış hızına bakılır,
        // böylece topun yerden kalkarken yaptığı küçük sıçrama sallama sayılmaz.
        let step = max(dt, 1.0 / 240)
        let tx = Float(s.target.x), ty = Float(s.target.y)
        let cvx = (tx - s.lastTarget.0) / step, cvy = (ty - s.lastTarget.1) / step
        s.lastTarget = (tx, ty)
        let jerk = hypot(cvx - b.vx, cvy - b.vy) / step
        b.vx += (cvx - b.vx) * 0.5
        b.vy += (cvy - b.vy) * 0.5
        if jerk > 30000, !riding.isEmpty { knockOff(above: b.id, push: b.vx) }

        guard b.y >= rest - 2 else { return }
        let moved = b.x - prevX
        b.spin += moved / b.r
        guard abs(moved) > 0.3 else { return }
        let area: Float
        if let hid = surf.heap, let h = s.heapIndex(hid).map({ s.heaps[$0] }) {
            area = take(from: hid, upTo: abs(moved) * h.height(at: b.x) * 0.8)
        } else {
            let band = b.r * 0.3
            area = surf.bed.scrape(from: min(prevX, b.x) - surf.originX - band, to: max(prevX, b.x) - surf.originX + band)
        }
        if area > 0 {
            grow(&b, area: area * 0.85, grounded: true)
            if random() < 0.35 { puff(x: b.x - (moved > 0 ? b.r * 0.6 : -b.r * 0.6), y: surf.y, count: 2, speed: 40) }
            // Kazınan karın yerine oturur, büyüyen top kendi izinde kalır.
            b.y = surface(below: b.x, from: b.y, reach: b.r * 0.35).y - b.r * lift
        }
    }

    /// Üstteki bütün toplar birbirinden ayrılıp ayrı ayrı yuvarlanır.
    private func knockOff(above id: Int, push: Float) {
        let s = sculpture
        let all = Set(s.riders(of: id))
        for i in s.balls.indices where all.contains(s.balls[i].id) {
            s.balls[i].support = .none
            s.balls[i].vx = push * 0.7 + random(-90, 90)
            s.balls[i].vy = random(-180, -50)
        }
    }

    private func grow(_ b: inout SnowBall, area: Float, grounded: Bool) {
        let old = b.r
        b.r = min(SnowSculpture.maxRadius, (b.r * b.r + area / .pi).squareRoot())
        if grounded { b.y -= (b.r - old) * lift }
    }

    private func rollOnGround(_ b: inout SnowBall, _ dt: Float) {
        if abs(b.vx) > 4 {
            let prevX = b.x
            b.x += b.vx * dt
            if b.x < b.r || b.x > width - b.r { b.x = min(max(b.x, b.r), width - b.r); b.vx = -b.vx * 0.3 }
            b.vx -= (b.vx > 0 ? 1 : -1) * min(abs(b.vx), 520 * dt)
            b.spin += (b.x - prevX) / b.r
            let band = b.r * 0.3
            let area = groundBed.scrape(from: min(prevX, b.x) - band, to: max(prevX, b.x) + band)
            if area > 0 { grow(&b, area: area * 0.85, grounded: true) }
        } else {
            b.vx = 0
        }
        b.vy = 0
        let rest = surface(below: b.x, from: height, reach: b.r * 0.35, groundOnly: true).y - b.r * lift
        if b.y < rest - 3 { b.support = .none; return }   // altındaki kar gitti: aşağı iner
        b.y = rest
        b.hidden = false
    }

    private func sitOnLedge(_ b: inout SnowBall, _ lid: UInt32, _ off: Float, _ dt: Float) {
        guard let l = ledges[lid] else {
            if dormant[lid] != nil { b.hidden = true } else { b.support = .none; b.hidden = false }
            return
        }
        if hypot(l.vx, l.vy) > 900 {   // pencere sertçe çekildi: top düşer
            b.support = .none
            b.hidden = false
            b.vx = l.vx * 0.25           // eylemsizlik: top büyük ölçüde yerinde kalır
            b.vy = min(l.vy * 0.25, 0) - 60
            return
        }
        var o = off
        if abs(b.vx) > 4 {
            o += b.vx * dt
            b.spin += b.vx * dt / b.r
            b.vx -= (b.vx > 0 ? 1 : -1) * min(abs(b.vx), 520 * dt)
        } else {
            b.vx = 0
        }
        let c = Int(o)
        guard o >= 0, c < l.bed.h.count, l.bed.caps[c] > 0 else {   // kenardan taştı
            b.support = .none
            b.hidden = false
            return
        }
        b.support = .ledge(lid, o)
        b.x = l.left + o
        b.y = l.top + l.drop[c] - l.bed.h[c] - b.r * lift
        b.vy = 0
        b.hidden = l.covered[c]
    }

    private func sitOnBall(_ b: inout SnowBall, _ base: Int, _ dx: Float, _ dt: Float) {
        guard let i = sculpture.index(base) else { b.support = .none; return }
        let o = sculpture.balls[i]
        let aligned = dx * exp(-dt * 2.5)          // kardan adam kendiliğinden hizalanır
        b.support = .ball(base, aligned)
        b.x = o.x + aligned
        b.y = o.y - (o.r * (1 - 2 * o.flat) + b.r) * 0.86
        b.vx = o.vx; b.vy = o.vy                   // alttaki topla birlikte hareket eder
        b.hidden = o.hidden
    }

    private func fall(_ b: inout SnowBall, _ dt: Float, gone: inout Set<Int>) {
        let s = sculpture
        b.hidden = false
        b.vy += 980 * dt
        let drag = max(0, 1 - 0.25 * dt)
        b.vx *= drag; b.vy *= drag
        let prevY = b.y
        b.x += b.vx * dt
        b.y += b.vy * dt
        b.spin += b.vx * dt / b.r * 0.5
        if b.x < b.r || b.x > width - b.r { b.x = min(max(b.x, b.r), width - b.r); b.vx = -b.vx * 0.35 }

        let riding = Set(s.riders(of: b.id))
        for o in s.balls where o.id != b.id && !o.hidden && !o.held && !gone.contains(o.id) && !riding.contains(o.id) {
            let dx = b.x - o.x, dy = b.y - o.y
            let d = hypot(dx, dy), m = (b.r + o.r) * 0.9
            guard d < m, d > 0.01 else { continue }
            if b.vy >= 0, b.y < o.y - o.r * 0.3, abs(dx) < o.r * 0.8 {
                let impact = b.vy - o.vy
                if impact >= SnowSculpture.crushSpeed {
                    // İki top birbirine gömülür, altındaki kuleyle birlikte yığına döner.
                    let root = s.root(of: o.id)
                    var ids = [b.id] + Array(riding) + [root] + s.riders(of: root)
                    ids = Array(Set(ids))
                    let r = s.index(root).map { s.balls[$0] } ?? o
                    collapse(ids, current: b, at: r.x, surface: surface(below: r.x, from: r.y, reach: r.r * 0.35), impact: impact, gone: &gone)
                    return
                }
                b.support = .ball(o.id, dx)
                b.y = o.y - (o.r * (1 - 2 * o.flat) + b.r) * 0.86
                b.vx = 0; b.vy = 0
                b.squash = min(0.22, impact / 3200)
                puff(x: b.x, y: b.y + b.r * 0.8, count: 4, speed: 50)
                dress(b.id, stackTop: &b)
                return
            }
            b.x = o.x + dx / d * m       // yanına çarptı: kayıp düşmeye devam eder
            b.y = o.y + dy / d * m
            b.vx = (dx >= 0 ? 1 : -1) * max(abs(b.vx), 70) * 0.6
        }

        let surf = surface(below: b.x, from: prevY, reach: b.r * 0.35)
        let rest = surf.y - b.r * lift
        guard b.vy >= 0, b.y >= rest else { return }
        let impact = b.vy
        if impact >= SnowSculpture.crushSpeed {
            collapse([b.id] + Array(riding), current: b, at: b.x, surface: surf, impact: impact, gone: &gone)
            return
        }
        b.y = rest
        b.vy = 0
        b.vx *= 0.6
        b.squash = min(0.25, impact / 3000)
        if impact >= SnowSculpture.dentSpeed {
            // Yer çekimi topu basıklaştırır; üstündekiler sarsıntıyla düşebilir.
            let k = (impact - SnowSculpture.dentSpeed) / (SnowSculpture.crushSpeed - SnowSculpture.dentSpeed)
            b.flat = min(0.3, b.flat + 0.06 + 0.2 * k)
            if k > 0.45, !riding.isEmpty { knockOff(above: b.id, push: random(-1, 1) * 160) }
            puff(x: b.x, y: surf.y, count: 6, speed: impact * 0.15)
        }
        b.support = surf.ledge.map { .ledge($0.id, b.x - $0.left) } ?? .ground
        if impact > 200 { puff(x: b.x, y: surf.y, count: min(10, Int(impact / 120)), speed: impact * 0.12) }
    }

    /// Toplar çarpmanın etkisiyle dağılır: bir kısmı sıçrar, kalanı yerde yayılan bir yığın olur.
    private func collapse(_ ids: [Int], current: SnowBall, at x: Float, surface surf: Surface, impact: Float, gone: inout Set<Int>) {
        let s = sculpture
        var area: Float = 0, maxR: Float = 0, tall: Float = 0
        var decor: SnowDecor = []
        for id in Set(ids) {
            guard let ball = id == current.id ? current : s.index(id).map({ s.balls[$0] }) else { continue }
            area += .pi * ball.r * ball.r
            maxR = max(maxR, ball.r)
            tall += ball.r * 1.72
            decor.formUnion(ball.decor)
            gone.insert(id)
        }
        guard area > 0 else { return }
        s.noteCollapse()
        let spray = area * 0.18
        let pieces = 14
        for _ in 0..<pieces {
            emitClump(area: spray / Float(pieces), x: x + random(-maxR * 0.6, maxR * 0.6), y: surf.y - random(4, max(6, tall * 0.4)),
                      vx: random(-1, 1) * (120 + impact * 0.22), vy: -random(0.12, 0.38) * impact)
        }
        puff(x: x, y: surf.y, count: 16, speed: 90 + impact * 0.12)
        let rest = area - spray

        guard surf.ledge == nil else {   // pencerenin üstünde yığın kalmaz: kar kenara dökülür
            for _ in 0..<12 {
                emitClump(area: rest / 12, x: x + random(-maxR, maxR), y: surf.y - random(2, 10), vx: random(-50, 50), vy: random(-40, 0))
            }
            return
        }
        if let hid = surf.heap ?? s.heaps.first(where: { abs($0.x - x) < $0.shape.w * 0.7 })?.id, let i = s.heapIndex(hid) {
            let h = s.heaps[i]
            s.heaps[i].startW = h.shape.w
            s.heaps[i].startH = h.shape.h * 1.2 + maxR * 0.4
            s.heaps[i].settle = 0
            s.heaps[i].x = (h.x * h.area + x * rest) / (h.area + rest)
            s.heaps[i].area += rest
            s.heaps[i].decor.formUnion(decor)
            return
        }
        if s.heaps.count >= SnowSculpture.maxHeaps { _ = scatterLeftover(s.heaps.removeFirst()) }
        s.heaps.append(SnowHeap(id: s.makeId(), x: x, base: groundLevel(x, reach: maxR * 0.5), area: rest,
                                startW: maxR * 1.05, startH: min(tall * 0.75, maxR * 1.8), decor: decor, seed: random(0, 100)))
    }

    /// Küreme aracının bıçağı yerdeki yığınları kürer, küçük topları önüne katıp yuvarlar,
    /// büyük topları ve kardan adamları parçalayıp önündeki kar yığınına katar. Bıçağa eklenen karı döndürür.
    func plowThroughSculpture(from a: Float, to b: Float, dir: Float, speed: Float) -> Float {
        let s = sculpture
        guard !s.balls.isEmpty || !s.heaps.isEmpty else { return 0 }
        var pile: Float = 0
        let lo = min(a, b), hi = max(a, b)

        // Yığınlar: bıçağın geçtiği şerit kadar kürenir.
        for h in s.heaps {
            let (w, _) = h.shape
            guard hi >= h.x - w, lo <= h.x + w else { continue }
            var want: Float = 0
            var x = max(lo, h.x - w)
            while x < min(hi, h.x + w) { want += h.height(at: x); x += 1 }
            if hi - lo < 1 { want = h.height(at: b) * (hi - lo) }
            pile += take(from: h.id, upTo: want * 1.6)
        }

        // Toplar: yalnızca yerde duranlar (pencerenin üstündekilere bıçak yetişmez).
        var gone = Set<Int>()
        for i in s.balls.indices {
            let ball = s.balls[i]
            guard ball.support == .ground, !ball.held, !ball.hidden, !gone.contains(ball.id) else { continue }
            let ahead = dir * (ball.x - b)
            guard ahead < ball.r * 0.9, ahead > -ball.r * 1.2 else { continue }
            let riders = s.riders(of: ball.id)
            let edge = ball.x - ball.r < 2 || ball.x + ball.r > width - 2
            if riders.isEmpty, ball.r <= 32, !edge {
                // Küçük top bıçağın önünde yuvarlanır; yolundaki karı toplayıp büyür.
                let nx = b + dir * ball.r * 0.9
                s.balls[i].spin += (nx - ball.x) / ball.r
                s.balls[i].x = nx
                s.balls[i].vx = dir * speed
                continue
            }
            // Kardan adam ya da büyük top: bıçağa çarpınca parçalanır.
            var area: Float = 0
            for id in [ball.id] + riders {
                guard let j = s.index(id) else { continue }
                area += .pi * s.balls[j].r * s.balls[j].r
                gone.insert(id)
            }
            s.noteCollapse()
            let spray = area * 0.3
            for _ in 0..<12 {
                emitClump(area: spray / 12, x: ball.x + random(-ball.r * 0.5, ball.r * 0.5), y: ball.y - random(0, ball.r),
                          vx: dir * random(140, 360), vy: -random(220, 520))
            }
            puff(x: ball.x, y: ball.y + ball.r * 0.6, count: 14, speed: 180)
            pile += area - spray
        }
        if !gone.isEmpty { s.balls.removeAll { gone.contains($0.id) } }
        return pile
    }

    /// Üst üste ilk kez oturan toplar kendiliğinden kardan adama dönüşür.
    private func dress(_ topId: Int, stackTop b: inout SnowBall) {
        let s = sculpture
        var chain: [Int] = []
        var support = b.support
        while case .ball(let below, _) = support, let i = s.index(below), !chain.contains(below) {
            chain.append(below)
            support = s.balls[i].support
        }
        guard !chain.isEmpty, !b.custom, !chain.contains(where: { s.index($0).map { s.balls[$0].custom } ?? true }) else { return }
        // Yüz her zaman en üstteki topa geçer, hemen altındaki gövde olur.
        b.decor = chain.count >= 2 ? [.face, .nose, .hat, .scarf] : [.face, .nose]
        for (k, id) in chain.enumerated() {
            if let i = s.index(id) { s.balls[i].decor = k == 0 ? [.arms, .buttons] : [] }
        }
        if chain.count == 1 { s.noteSnowman() }
    }

    /// Menüden dağıtılan top topaklara ayrılır; topaklar yüzeylere kar olarak tutunur.
    private func burst(_ b: SnowBall) {
        let area = Float.pi * b.r * b.r
        let pieces = max(6, min(22, Int(b.r / 3)))
        for k in 0..<pieces {
            let a = random(0, 6.283), d = random(0, b.r * 0.7)
            let out = random(70, 260)
            emitClump(area: area / Float(pieces), x: b.x + cos(a) * d, y: b.y + sin(a) * d,
                      vx: cos(a) * out + b.vx * 0.3, vy: min(0, sin(a) * out) - random(60, 220) + Float(k % 2) * 40)
        }
        puff(x: b.x, y: b.y + b.r * 0.5, count: 12, speed: 160)
    }

    private func puff(x: Float, y: Float, count: Int, speed: Float) {
        for _ in 0..<count where particles.count < Self.maxParticles {
            let a = random(-2.8, -0.35), v = random(speed * 0.4, speed)
            particles.append(Particle(kind: .powder, x: x + random(-6, 6), y: y - 1, vx: cos(a) * v, vy: sin(a) * v,
                                      r: random(0.5, 1.2), mass: 0, phase: 0, depth: 1, life: random(0.5, 1)))
        }
    }

    /// Topa ya da yığına değen kar tanesi ona yapışır ve onu biraz büyütür.
    func absorbIntoBall(_ p: Particle) -> Bool {
        let s = sculpture
        guard !s.balls.isEmpty || !s.heaps.isEmpty, p.kind == .flake || p.kind == .clump else { return false }
        for i in s.balls.indices where !s.balls[i].hidden {
            let b = s.balls[i]
            let dx = p.x - b.x, dy = p.y - b.y
            guard dx * dx + dy * dy < b.r * b.r else { continue }
            if !melting {
                s.balls[i].r = min(SnowSculpture.maxRadius, (b.r * b.r + p.mass * 0.9 / .pi).squareRoot())
            }
            return true
        }
        for i in s.heaps.indices {
            let t = s.heaps[i].height(at: p.x)
            guard t > 0.5, p.y >= heapTop(s.heaps[i], p.x) else { continue }
            if !melting { s.heaps[i].area += p.mass * 0.9 }
            return true
        }
        return false
    }

    func grabMap() -> SnowGrabMap {
        var m = SnowGrabMap()
        m.height = height
        m.ground = groundBed.h
        m.ledges = order.compactMap { ledges[$0] }.map {
            SnowGrabMap.Ledge(left: $0.left, top: $0.top, h: $0.bed.h, drop: $0.drop, covered: $0.covered)
        }
        m.heaps = sculpture.heaps
        m.balls = sculpture.balls.filter { !$0.hidden }.map { ($0.id, $0.x, $0.y, $0.r, $0.decor) }
        return m
    }

    // MARK: - Çizim

    func drawSculpture(into out: UnsafeMutablePointer<Float>, count n: inout Int, capacity: Int, alpha: Float) {
        let balls = sculpture.balls.filter { !$0.hidden }.sorted { $0.y > $1.y }
        let heaps = sculpture.heaps
        guard !balls.isEmpty || !heaps.isEmpty else { return }
        typealias RGB = (Float, Float, Float)
        var written = n
        defer { n = written }

        func vc(_ x: Float, _ y: Float, _ u: Float, _ w: Float, _ c: RGB, _ a: Float, _ soft: Float) {
            let p = out + written * 9
            p[0] = x; p[1] = y; p[2] = u; p[3] = w
            p[4] = c.0 * a; p[5] = c.1 * a; p[6] = c.2 * a; p[7] = a; p[8] = soft
            written += 1
        }
        func oval(_ x: Float, _ y: Float, _ rx: Float, _ ry: Float, _ c: RGB, _ a: Float, _ soft: Float) {
            let x0 = x - rx, x1 = x + rx, y0 = y - ry, y1 = y + ry
            vc(x0, y0, 0, 0, c, a, soft); vc(x1, y0, 1, 0, c, a, soft); vc(x0, y1, 0, 1, c, a, soft)
            vc(x1, y0, 1, 0, c, a, soft); vc(x1, y1, 1, 1, c, a, soft); vc(x0, y1, 0, 1, c, a, soft)
        }
        func tri(_ a: (Float, Float), _ b: (Float, Float), _ c: (Float, Float), _ col: RGB, _ al: Float) {
            vc(a.0, a.1, 0, 0, col, al, -1); vc(b.0, b.1, 0, 0, col, al, -1); vc(c.0, c.1, 0, 0, col, al, -1)
        }
        func line(_ a: (Float, Float), _ b: (Float, Float), _ w: Float, _ col: RGB, _ al: Float) {
            let dx = b.0 - a.0, dy = b.1 - a.1, l = max(hypot(dx, dy), 0.01)
            let nx = -dy / l * w / 2, ny = dx / l * w / 2
            tri((a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), (b.0 - nx, b.1 - ny), col, al)
            tri((a.0 + nx, a.1 + ny), (b.0 - nx, b.1 - ny), (a.0 - nx, a.1 - ny), col, al)
        }
        /// Döndürülmüş dikdörtgen (yığının üstüne düşmüş şapka gibi).
        func box(_ cx: Float, _ cy: Float, _ w: Float, _ h: Float, _ ang: Float, _ col: RGB, _ al: Float) {
            let c = cos(ang), s = sin(ang)
            func p(_ x: Float, _ y: Float) -> (Float, Float) { (cx + x * c - y * s, cy + x * s + y * c) }
            let a = p(-w / 2, -h / 2), b = p(w / 2, -h / 2), d = p(w / 2, h / 2), e = p(-w / 2, h / 2)
            tri(a, b, d, col, al); tri(a, d, e, col, al)
        }
        func quad(_ x0: Float, _ x1: Float, _ t0: Float, _ t1: Float, _ b0: Float, _ b1: Float, _ top: RGB, _ bottom: RGB, _ al: Float) {
            vc(x0, t0, 0, 0, top, al, -1); vc(x1, t1, 0, 0, top, al, -1); vc(x0, b0, 0, 0, bottom, al, -1)
            vc(x1, t1, 0, 0, top, al, -1); vc(x1, b1, 0, 0, bottom, al, -1); vc(x0, b0, 0, 0, bottom, al, -1)
        }

        let coal: RGB = (0.11, 0.11, 0.13), white: RGB = (0.985, 0.99, 1)
        let brown: RGB = (0.36, 0.23, 0.13), red: RGB = (0.80, 0.14, 0.16), orange: RGB = (0.97, 0.52, 0.12)

        // Kar yığınları
        for h in heaps {
            let (w, H) = h.shape
            guard written + Int(w) * 6 + 900 < capacity, w > 2 else { continue }
            let A = alpha
            func topAt(_ fx: Float) -> Float { heapTop(h, fx) }
            var px = h.x - w
            while px < h.x + w {
                let qx = min(px + 2, h.x + w)
                let t0 = h.height(at: px), t1 = h.height(at: qx)
                if t0 > 0.2 || t1 > 0.2 {
                    let slope = (h.height(at: px + 6) - h.height(at: px - 6)) / 12
                    let lit = max(0, min(1, 0.6 + slope * 0.9))
                    let top: RGB = (0.86 + 0.13 * lit, 0.91 + 0.085 * lit, 0.985 + 0.015 * lit)
                    // Yığın altındaki zemine kadar iner, kazınmış izin üstünde havada durmaz.
                    func floor(_ fx: Float) -> Float {
                        let c = max(0, min(groundBed.h.count - 1, Int(fx)))
                        return height - groundBed.h[c] + 0.5
                    }
                    quad(px, qx, topAt(px), topAt(qx), max(topAt(px) + t0, floor(px)), max(topAt(qx) + t1, floor(qx)), top, (0.76, 0.83, 0.95), A)
                }
                px = qx
            }
            // Kırık kar parçaları ve topaklar: yığına dağınık, iri taneli bir doku verir
            let chunks = max(6, Int(w / 7))
            for k in 0..<chunks {
                let fk = Float(k)
                let jitter = sin(h.seed * 3.1 + fk * 7.7) * w * 0.05
                let cx = h.x - w * 0.86 + fk / Float(max(chunks - 1, 1)) * w * 1.72 + jitter
                let top = h.height(at: cx)
                guard top > 2 else { continue }
                let size = min(top * 0.5, 2.5 + abs(sin(h.seed + fk * 2.3)) * (4 + w * 0.035))
                let cy = topAt(cx) + size * (0.35 + 0.5 * abs(sin(fk * 1.9 + h.seed)))
                oval(cx + size * 0.3, cy + size * 0.35, size, size * 0.9, (0.68, 0.76, 0.92), 0.35 * A, 0.3)
                oval(cx, cy, size * 0.92, size * 0.85, white, 0.85 * A, 0.35)
            }
            // Dağılan topların yarısı gömülü iri parçaları
            for k in 0..<3 {
                let fk = Float(k)
                let cx = h.x + (fk - 1) * w * 0.42 + sin(h.seed + fk) * w * 0.08
                let top = h.height(at: cx)
                guard top > 6 else { continue }
                let r = min(top * 0.55, w * 0.16)
                let cy = topAt(cx) + r * 0.45
                oval(cx, cy, r, r, (0.76, 0.83, 0.94), A, max(0.5, 1 - 1.6 / r))
                oval(cx - r * 0.15, cy - r * 0.18, r * 0.8, r * 0.8, (0.95, 0.965, 0.995), A, 0.4)
            }
            // Üstüne düşen süsler
            let d = h.decor, show = min(1, h.settle * 2)
            guard show > 0 else { continue }
            let S = A * show
            func on(_ fx: Float) -> (Float, Float) { let x = h.x + w * fx; return (x, topAt(x)) }
            if d.contains(.arms) {
                let a = on(-0.62), b = on(0.5)
                line((a.0 - w * 0.12, a.1 - 2), (a.0 + w * 0.22, a.1 + 3), max(2.2, w * 0.03), brown, S)
                line((a.0 + w * 0.05, a.1), (a.0 + w * 0.1, a.1 - w * 0.08), max(1.6, w * 0.02), brown, S)
                line((b.0 - w * 0.16, b.1 + 2), (b.0 + w * 0.2, b.1 - 6), max(2.2, w * 0.03), brown, S)
            }
            if d.contains(.scarf) {
                var prev = on(-0.3)
                for k in 1...8 {
                    let p = on(-0.3 + Float(k) * 0.07)
                    line((prev.0, prev.1 + 1.5), (p.0, p.1 + 1.5), max(4, w * 0.06), red, S)
                    prev = p
                }
                line((prev.0, prev.1 + 1), (prev.0 + w * 0.1, prev.1 + w * 0.12), max(4, w * 0.06), red, S)
            }
            if d.contains(.nose) {
                let p = on(-0.06)
                tri((p.0 - 3, p.1 + 2), (p.0 + 3, p.1 + 2), (p.0 + w * 0.06, p.1 - w * 0.2), orange, S)
            }
            if d.contains(.face) || d.contains(.buttons) {
                for k in 0..<6 {
                    let p = on(-0.7 + Float(k) * 0.27 + sin(h.seed + Float(k)) * 0.05)
                    let s = max(1.8, w * 0.022)
                    oval(p.0, p.1 + s * 0.6, s, s * 0.85, coal, S, 0.5)
                }
            }
            if d.contains(.hat) {
                let p = on(0.4), size = max(14, min(w * 0.22, 40))
                let ang: Float = 0.55
                box(p.0, p.1 - size * 0.25, size * 1.3, size * 0.14, ang, coal, S)
                box(p.0 - sin(ang) * size * 0.45, p.1 - size * 0.25 + cos(ang) * -size * 0.45, size * 0.8, size * 0.9, ang, coal, S)
                box(p.0 - sin(ang) * size * 0.2, p.1 - size * 0.25 - cos(ang) * size * 0.2, size * 0.8, size * 0.14, ang, red, S)
            }
            // Parıltı
            let twinkle = sin(time * 1.7 + h.seed)
            if twinkle > 0.5 { let p = on(-0.2); oval(p.0, p.1 + 2, 1.3, 1.3, white, (twinkle - 0.5) * 2 * A, 0.1) }
        }

        for b in balls {
            guard written + 420 < capacity else { return }
            let r = b.r, x = b.x, y = b.y, A = alpha
            let sx = 1 + b.squash + 0.8 * b.flat, sy = 1 - b.squash - b.flat
            let cy = y + r * (b.squash * 0.8 + b.flat)       // ezilince yere yaslanır
            let edge = max(0.5, 1 - 1.6 / r)

            if b.support == .ground || { if case .ledge = b.support { return true }; return false }() {
                oval(x + r * 0.1, y + r * lift, r * 1.08 * sx, r * 0.2, (0.05, 0.08, 0.16), 0.2 * A, 0)
            }
            oval(x, cy, r * sx, r * sy, (0.74, 0.81, 0.93), A, edge)                         // gölgeli gövde
            oval(x - r * 0.13, cy - r * 0.15 * sy, r * 0.86 * sx, r * 0.86 * sy, (0.93, 0.955, 0.99), A, 0.45)
            oval(x - r * 0.2, cy - r * 0.24 * sy, r * 0.6 * sx, r * 0.6 * sy, white, 0.85 * A, 0.3)
            oval(x - r * 0.36, cy - r * 0.4 * sy, r * 0.2, r * 0.17, white, 0.7 * A, 0)       // parlama
            if b.flat > 0.05 {   // basıklaşan topun ezik kenarı
                oval(x, cy + r * sy * 0.78, r * sx * 0.8, r * b.flat * 0.9, (0.7, 0.78, 0.92), 0.5 * A, 0.4)
            }

            // Dönen topaklar: yuvarlandığı göze böyle görünür
            for k in 0..<11 {
                let fk = Float(k)
                let ang = b.seed * 0.7 + fk * 2.399 + b.spin
                let frac = (sin(b.seed + fk * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                let d = r * (0.18 + 0.58 * abs(frac))
                let size = r * (0.09 + 0.07 * Float(k % 3))
                let px = x + cos(ang) * d * sx, py = cy + sin(ang) * d * sy
                if k % 3 == 0 {
                    oval(px + size * 0.25, py + size * 0.3, size, size, (0.66, 0.74, 0.9), 0.28 * A, 0.2)
                } else {
                    oval(px, py, size * 0.9, size * 0.9, white, 0.45 * A, 0.25)
                }
            }
            let twinkle = sin(time * 2.1 + b.seed)
            if twinkle > 0.6 { oval(x + r * 0.3, cy - r * 0.35, 1.3, 1.3, white, (twinkle - 0.6) * 2.5 * A, 0.1) }

            // Süsler
            let d = b.decor
            if d.contains(.arms) {
                for side in [Float(-1), 1] {
                    let a0 = (x + side * r * 0.82 * sx, cy - r * 0.1), a1 = (x + side * r * 1.6 * sx, cy - r * 0.66)
                    line(a0, a1, max(2.2, r * 0.07), brown, A)
                    let m = (a0.0 + (a1.0 - a0.0) * 0.7, a0.1 + (a1.1 - a0.1) * 0.7)
                    line(m, (m.0 + side * r * 0.2, m.1 - r * 0.3), max(1.6, r * 0.05), brown, A)
                    line(a1, (a1.0 + side * r * 0.16, a1.1 + r * 0.02), max(1.4, r * 0.045), brown, A)
                }
            }
            if d.contains(.buttons) {
                for k in -1...1 { oval(x, cy + Float(k) * r * 0.33 * sy, r * 0.075, r * 0.075, coal, A, 0.55) }
            }
            if d.contains(.scarf) {
                let dark: RGB = (0.62, 0.08, 0.11)
                let s0 = cy + r * 0.58 * sy, s1 = cy + r * 0.86 * sy
                tri((x - r * 0.74 * sx, s0), (x + r * 0.74 * sx, s0), (x + r * 0.7 * sx, s1), red, A)
                tri((x - r * 0.74 * sx, s0), (x + r * 0.7 * sx, s1), (x - r * 0.7 * sx, s1), red, A)
                line((x + r * 0.42, cy + r * 0.74 * sy), (x + r * 0.58, cy + r * 1.38 * sy), r * 0.24, red, A)
                line((x - r * 0.5, cy + r * 0.72 * sy), (x + r * 0.5, cy + r * 0.72 * sy), r * 0.05, dark, A)
            }
            if d.contains(.face) {
                for side in [Float(-1), 1] { oval(x + side * r * 0.3 * sx, cy - r * 0.22 * sy, r * 0.078, r * 0.085, coal, A, 0.55) }
                for k in 0..<5 {
                    let a = Float.pi * (0.28 + 0.11 * Float(k))
                    oval(x + cos(a) * r * 0.42 * sx, cy - r * 0.04 + sin(a) * r * 0.42 * sy, r * 0.045, r * 0.045, coal, A, 0.5)
                }
            }
            if d.contains(.nose) {
                let shade: RGB = (0.82, 0.38, 0.07)
                tri((x - r * 0.02, cy - r * 0.13), (x + r * 0.56, cy - r * 0.02), (x - r * 0.02, cy + r * 0.0), orange, A)
                tri((x - r * 0.02, cy - r * 0.02), (x + r * 0.56, cy - r * 0.02), (x - r * 0.02, cy + r * 0.0), shade, A)
            }
            if d.contains(.hat) {
                let brim = cy - r * 0.8 * sy
                tri((x - r * 0.66, brim - r * 0.11), (x + r * 0.66, brim - r * 0.11), (x + r * 0.66, brim), coal, A)
                tri((x - r * 0.66, brim - r * 0.11), (x + r * 0.66, brim), (x - r * 0.66, brim), coal, A)
                tri((x - r * 0.42, brim - r * 0.86), (x + r * 0.42, brim - r * 0.86), (x + r * 0.42, brim - r * 0.1), coal, A)
                tri((x - r * 0.42, brim - r * 0.86), (x + r * 0.42, brim - r * 0.1), (x - r * 0.42, brim - r * 0.1), coal, A)
                line((x - r * 0.42, brim - r * 0.2), (x + r * 0.42, brim - r * 0.2), r * 0.12, (0.78, 0.13, 0.15), A)
                oval(x - r * 0.2, brim - r * 0.88, r * 0.24, r * 0.06, white, 0.9 * A, 0.4)   // şapkadaki kar
            }
        }
    }
}
