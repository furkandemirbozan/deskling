import AppKit

/// Kar topu ve kardan adam davranışını ekran açmadan, fare komutlarıyla dener.
enum SculptCheck {
    private static var failures = 0
    private static let dt: Float = 1.0 / 60

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    private static func f(_ v: Float) -> String { String(format: "%.0f", v) }

    private static func run(_ e: SnowEngine, _ seconds: Float, windows: [SnowWindow]? = nil) {
        for i in 0..<Int(seconds * 60) {
            if let windows, i % 8 == 0 { e.apply(windows: windows, dt: 8 * dt) }
            e.step(dt)
        }
    }

    /// Zemini sınırına yakın karla doldurur.
    private static func fill(_ e: SnowEngine) {
        for pass in 0..<16 {
            var x: Float = Float(pass % 3)
            while x < e.width { e.groundBed.add(x: x, r: 2.2, tone: 1, fuse: false); x += 3.1 }
        }
    }

    private static func top(_ e: SnowEngine, _ x: Float) -> Float { e.height - e.ground[Int(x)] }

    /// İmleci adım adım taşır; her karede motor bir kez ilerler.
    private static func drag(_ e: SnowEngine, to p: CGPoint, steps: Int, windows: [SnowWindow]? = nil) {
        let start = e.sculpture.target
        for k in 1...steps {
            let t = CGFloat(k) / CGFloat(steps)
            e.handle(.move(CGPoint(x: start.x + (p.x - start.x) * t, y: start.y + (p.y - start.y) * t)))
            if let windows, k % 8 == 0 { e.apply(windows: windows, dt: 8 * dt) }
            e.step(dt)
        }
    }

    private static func ball(_ e: SnowEngine, _ id: Int) -> SnowBall? { e.sculpture.balls.first { $0.id == id } }

    /// Kardan bir top yapıp istenen yere götürür, bırakır.
    @discardableResult
    private static func make(_ e: SnowEngine, at x: Float, roll: Float, dropAt p: CGPoint, windows: [SnowWindow]? = nil) -> Int {
        e.handle(.grab(CGPoint(x: CGFloat(x), y: CGFloat(top(e, x) + 2))))
        let id = e.sculpture.heldId ?? -1
        drag(e, to: CGPoint(x: CGFloat(x + roll), y: CGFloat(top(e, x + roll) + 2)), steps: Int(abs(roll) / 4), windows: windows)
        drag(e, to: CGPoint(x: e.sculpture.target.x, y: p.y), steps: 40, windows: windows)
        drag(e, to: p, steps: 40, windows: windows)
        e.handle(.release(.zero))
        return id
    }

    /// Topu istenen yüksekliğe taşıyıp bırakır; düştüğü andaki hızını döndürür.
    private static func lift(_ e: SnowEngine, _ id: Int, toY y: CGFloat, release v: CGVector = .zero) {
        guard let b = ball(e, id) else { return }
        e.handle(.grab(CGPoint(x: CGFloat(b.x), y: CGFloat(b.y))))
        drag(e, to: CGPoint(x: CGFloat(b.x), y: y), steps: 60)
        e.handle(.release(v))
    }

    private static func snowman(_ e: SnowEngine, at x: Float) -> (Int, Int, Int) {
        let base = make(e, at: x - 120, roll: 150, dropAt: CGPoint(x: CGFloat(x), y: CGFloat(top(e, x) - 90)))
        run(e, 1.2)
        let b = ball(e, base)!
        let mid = make(e, at: x + 160, roll: 70, dropAt: CGPoint(x: CGFloat(b.x), y: CGFloat(b.y - b.r - 110)))
        run(e, 1.2)
        let m = ball(e, mid)!
        let head = make(e, at: x + 260, roll: 30, dropAt: CGPoint(x: CGFloat(m.x), y: CGFloat(m.y - m.r - 90)))
        run(e, 1.2)
        return (base, mid, head)
    }

    /// Yer çekimi: düşme yüksekliğine göre ezilme, yığına dönme ve birleşme.
    private static func gravity(_ output: URL?) {
        let g = SnowEngine(width: 1470, height: 956)
        g.intensity = -0.12
        fill(g)

        // Alçaktan bırakılan top sağlam kalır
        let low = make(g, at: 60, roll: 190, dropAt: CGPoint(x: 200, y: CGFloat(top(g, 200) - 40)))
        run(g, 1)
        let lb = ball(g, low)
        lift(g, low, toY: CGFloat((lb?.y ?? 800) - 110))
        run(g, 1.5)
        check("alçaktan bırakılan top sağlam kalır", ball(g, low).map { $0.flat == 0 && $0.support == .ground } ?? false)

        // Orta yükseklikten düşen top basıklaşır
        lift(g, low, toY: CGFloat((ball(g, low)?.y ?? 800) - 300))
        run(g, 1.5)
        let dented = ball(g, low)
        check("orta yükseklikten düşen top basıklaşır ama dağılmaz", (dented?.flat ?? 0) > 0.05, "basıklık \(String(format: "%.2f", dented?.flat ?? 0))")

        // Yüksekten düşen top yığına döner
        let area = Float.pi * (dented?.r ?? 0) * (dented?.r ?? 0)
        lift(g, low, toY: 60)
        run(g, 0.25)
        SnowCheck.render(g, [], output, "kar-yigin-1-carpma.png")
        run(g, 1.5)
        let heap = g.sculpture.heaps.first
        check("yüksekten düşen top yere çarpıp kar yığınına döner", ball(g, low) == nil && heap != nil)
        let kept = (heap?.area ?? 0) / max(area, 1)
        check("yığın topun karının çoğunu taşır", kept > 0.7 && kept < 0.95, String(format: "%%%.0f", kept * 100))
        check("yığın yayılınca basık ve geniş olur", (heap?.shape.w ?? 0) > (heap?.shape.h ?? 0) * 2)

        // Yığından top yapmak ve yığının üstünde yuvarlamak
        if let h = heap {
            let before = h.area
            g.handle(.grab(CGPoint(x: CGFloat(h.x), y: CGFloat(g.heapTop(h, h.x) + 2))))
            let fromHeap = g.sculpture.heldId
            check("yığına tıklayınca kardan top alınır", fromHeap != nil && (g.sculpture.heaps.first?.area ?? 0) < before)
            let mid = g.sculpture.heaps.first?.area ?? 0
            let r0 = fromHeap.flatMap { ball(g, $0)?.r } ?? 0
            for k in 0..<40 {
                let x = CGFloat(h.x) + CGFloat(sin(Float(k) * 0.3)) * CGFloat(h.shape.w * 0.6)
                g.handle(.move(CGPoint(x: x, y: CGFloat(g.heapTop(h, Float(x))))))
                g.step(dt)
            }
            let r1 = fromHeap.flatMap { ball(g, $0)?.r } ?? 0
            check("yığının üstünde yuvarlanan top yığını toplayarak büyür", r1 > r0 && (g.sculpture.heaps.first?.area ?? 0) < mid)
            g.handle(.release(.zero))
            run(g, 1.5)
            check("yığının üstüne bırakılan top yığının üstünde durur",
                  fromHeap.flatMap { ball(g, $0) }.map { abs($0.y + $0.r * 0.88 - g.surface(below: $0.x, from: $0.y, reach: $0.r * 0.35, groundOnly: true).y) < 3 } ?? false)
            if let id = fromHeap { g.handle(.shatter(id)) }
            run(g, 1)
        }

        // Kardan adam tabanından tutulunca bütün olarak taşınır
        fill(g)
        let (base, mid, head) = snowman(g, at: 760)
        check("test kardan adamı kurulur", { if case .ball(mid, _) = ball(g, head)?.support { return true }; return false }())
        let gapBefore = (ball(g, base)?.y ?? 0) - (ball(g, head)?.y ?? 0)
        guard let b0 = ball(g, base) else { return }
        g.handle(.grab(CGPoint(x: CGFloat(b0.x), y: CGFloat(b0.y))))
        drag(g, to: CGPoint(x: CGFloat(b0.x + 40), y: CGFloat(b0.y - 260)), steps: 90)
        let carriedGap = (ball(g, base)?.y ?? 0) - (ball(g, head)?.y ?? 0)
        check("kardan adam tabanından tutulunca bütün olarak taşınır", abs(carriedGap - gapBefore) < 2 && abs((ball(g, head)?.x ?? 0) - (ball(g, base)?.x ?? 0)) < 8)
        SnowCheck.render(g, [], output, "kar-yigin-2-tasima.png")

        // Yukarıdan bırakılan kardan adam yığına döner, süsleri yığının üstüne düşer
        drag(g, to: CGPoint(x: CGFloat(b0.x + 40), y: 70), steps: 60)
        let collapsesBefore = g.sculpture.collapses
        g.handle(.release(.zero))
        run(g, 0.3)
        SnowCheck.render(g, [], output, "kar-yigin-3-dusus.png")
        run(g, 1.6)
        check("yukarıdan bırakılan kardan adam tek bir yığına döner", [base, mid, head].allSatisfy { ball(g, $0) == nil } && g.sculpture.collapses == collapsesBefore + 1)
        let pile = g.sculpture.heaps.min { abs($0.x - b0.x - 40) < abs($1.x - b0.x - 40) }
        check("şapka, burun ve kollar yığının üstüne düşer", pile?.decor.isSuperset(of: [.hat, .nose, .arms]) == true)
        SnowCheck.render(g, [], output, "kar-yigin-4-kardan-adam-yigini.png")

        // Sertçe sallanan kardan adamın kafası düşer
        fill(g)
        let (sb, _, sh) = snowman(g, at: 400)
        if let s0 = ball(g, sb) {
            g.handle(.grab(CGPoint(x: CGFloat(s0.x), y: CGFloat(s0.y))))
            drag(g, to: CGPoint(x: CGFloat(s0.x), y: CGFloat(s0.y - 120)), steps: 30)
            for k in 0..<12 {
                g.handle(.move(CGPoint(x: CGFloat(s0.x + (k % 2 == 0 ? 70 : -70)), y: CGFloat(s0.y - 120))))
                g.step(dt)
            }
            check("sertçe sallanan kardan adamın kafası düşer", { if case .ball = ball(g, sh)?.support { return false }; return true }())
            g.handle(.release(.zero))
            run(g, 2)
        }

        // Yukarıdan atılan top alttaki topla birleşip yığın olur
        let t = SnowEngine(width: 1470, height: 956)
        t.intensity = -0.12
        fill(t)
        let lower = make(t, at: 900, roll: 110, dropAt: CGPoint(x: 1100, y: CGFloat(top(t, 1100) - 60)))
        run(t, 1)
        let upper = make(t, at: 200, roll: 90, dropAt: CGPoint(x: 600, y: 300))
        run(t, 1)
        let lb2 = ball(t, lower)!
        if let u = ball(t, upper) {
            t.handle(.grab(CGPoint(x: CGFloat(u.x), y: CGFloat(u.y))))
            drag(t, to: CGPoint(x: CGFloat(lb2.x), y: 90), steps: 60)
            t.handle(.release(CGVector(dx: 0, dy: 700)))
        }
        run(t, 2)
        check("yukarıdan atılan top alttakiyle birleşip yığın olur", ball(t, lower) == nil && ball(t, upper) == nil && t.sculpture.heaps.count == 1)
        check("birleşen yığın alttaki topun yerinde oluşur", abs((t.sculpture.heaps.first?.x ?? 0) - lb2.x) < 30)

        // Yağan kar yığına yapışır
        let size = t.sculpture.heaps.first?.area ?? 0
        t.intensity = 1
        run(t, 18)     // taneler ekranın tepesinden yere yaklaşık 12 saniyede iner
        let after = t.sculpture.heaps.first?.area ?? 0
        check("yağan kar yığına yapışır", after > size, "\(f(size)) → \(f(after)), yığın \(t.sculpture.heaps.count)")
    }

    static func run(output: URL?) -> Int32 {
        if let output { try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let e = SnowEngine(width: 1470, height: 956)
        e.intensity = -0.12        // test sırasında yeni kar yağmasın
        fill(e)
        let before = e.groundMass
        let fullDepth = e.ground[1200]
        check("zemin karla dolar", fullDepth > 25, "derinlik \(f(fullDepth))")

        // 1. Avuçlama
        e.handle(.grab(CGPoint(x: 400, y: CGFloat(top(e, 400) + 2))))
        let first = e.sculpture.heldId ?? -1
        let r0 = ball(e, first)?.r ?? 0
        check("sol tıkla kardan top avuçlanır", e.sculpture.balls.count == 1 && r0 >= SnowSculpture.minRadius, "r \(f(r0))")
        check("avuçlanan kar zeminden eksilir", e.groundMass < before)

        // 2. Yuvarlama
        var worstGap: Float = 0
        for k in 1...125 {
            let x = 400 + CGFloat(k) * 4
            e.handle(.move(CGPoint(x: x, y: CGFloat(top(e, Float(x)) + 2))))
            e.step(dt)
            if let b = ball(e, first) {
                let s = e.surface(below: b.x, from: b.y, reach: b.r * 0.35).y
                worstGap = max(worstGap, abs(b.y + b.r * 0.88 - s))
            }
            if k == 60 { SnowCheck.render(e, [], output, "kar-topu-1-yuvarlama.png") }
        }
        let rolled = ball(e, first)
        check("top karda yuvarlandıkça büyür", (rolled?.r ?? 0) > 34, "r \(f(rolled?.r ?? 0))")
        check("top yuvarlanırken döner", abs(rolled?.spin ?? 0) > 3)
        check("top karın üstünde yuvarlanır, gömülmez ve havada kalmaz", worstGap < 3, "sapma \(String(format: "%.1f", worstGap))")
        check("topun geçtiği yerde iz kalır", e.ground[640] < fullDepth * 0.3, "iz \(f(e.ground[640])) / \(f(fullDepth))")
        check("topun geçmediği yerdeki kar durur", e.ground[1300] > fullDepth * 0.85)
        e.handle(.release(.zero))
        run(e, 1)
        if let b = ball(e, first) {
            let s = e.surface(below: b.x, from: b.y, reach: b.r * 0.35).y
            check("bırakılan top zemine oturur", b.support == .ground && abs(b.y + b.r * 0.88 - s) < 2)
        }

        // 3. Kardan adam
        guard let base = ball(e, first) else { check("ilk top kayboldu", false); return 1 }
        let second = make(e, at: 1150, roll: 150, dropAt: CGPoint(x: CGFloat(base.x + 6), y: CGFloat(base.y - base.r - 140)))
        run(e, 2)
        let mid = ball(e, second)
        check("üste bırakılan top diğerinin üstüne oturur", mid?.support == .ball(first, mid.map { if case .ball(_, let d) = $0.support { return d }; return 0 } ?? 0))
        check("üst üste toplar hizalanır", abs((mid?.x ?? 0) - (ball(e, first)?.x ?? 0)) < 3)
        let third = make(e, at: 150, roll: 70, dropAt: CGPoint(x: CGFloat(base.x - 4), y: CGFloat((mid?.y ?? 0) - (mid?.r ?? 0) - 150)))
        run(e, 2)
        let head = ball(e, third)
        check("üç top kardan adam olur", { if case .ball(second, _) = head?.support { return true }; return false }())
        check("kafaya göz, burun ve şapka takılır", head?.decor.isSuperset(of: [.face, .nose, .hat]) == true)
        check("gövdeye kollar ve düğmeler takılır", ball(e, second)?.decor.isSuperset(of: [.arms, .buttons]) == true)
        check("kardan adam sayılır", e.sculpture.snowmen == 1)
        SnowCheck.render(e, [], output, "kar-topu-2-kardan-adam.png")

        // 4. Süsleme menüsü
        e.handle(.decorate(first, .scarf))
        check("sağ tık menüsüyle süs eklenir", ball(e, first)?.decor.contains(.scarf) == true)
        e.handle(.decorate(first, .scarf))
        check("aynı süs yeniden seçilince çıkarılır", ball(e, first)?.decor.contains(.scarf) == false)

        // 5. Tutma haritası
        let map = e.grabMap()
        if let h = head { check("imleç topun üstündeyken top tutulabilir", map.hit(CGPoint(x: CGFloat(h.x), y: CGFloat(h.y))) == .ball(third, h.decor)) }
        check("imleç karın üstündeyken kar tutulabilir", map.hit(CGPoint(x: 1320, y: CGFloat(top(e, 1320) + 3))) == .snow)
        check("boş yere tıklama alttaki pencereye geçer", map.hit(CGPoint(x: 700, y: 300)) == nil)
        check("kazınmış ince karda tıklama alttakine geçer", map.hit(CGPoint(x: 640, y: CGFloat(e.height - 1))) == nil)

        // 6. Tutulan top diğerlerinin içinden geçmez
        e.handle(.grab(CGPoint(x: 1330, y: CGFloat(top(e, 1330) + 2))))
        let pusher = e.sculpture.heldId ?? -1
        var overlap = false
        for k in 0...90 {
            e.handle(.move(CGPoint(x: CGFloat(1330 - Float(k) * 9), y: CGFloat((ball(e, first)?.y ?? 800)))))
            e.step(dt)
            if let p = ball(e, pusher) {
                for o in e.sculpture.balls where o.id != p.id && hypot(o.x - p.x, o.y - p.y) < (o.r + p.r) * 0.88 { overlap = true }
            }
        }
        check("tutulan top diğer topların içinden geçmez", !overlap)

        // 7. Fırlatınca dağılma
        drag(e, to: CGPoint(x: 1100, y: 80), steps: 30)
        let kept = e.sculpture.balls.count
        e.handle(.release(CGVector(dx: 0, dy: 1700)))
        run(e, 0.3)
        SnowCheck.render(e, [], output, "kar-topu-3-dagilma.png")
        run(e, 1.5)
        check("hızla fırlatılan top yere çarpıp yığına döner", e.sculpture.collapses == 1 && e.sculpture.balls.count == kept - 1 && !e.sculpture.heaps.isEmpty)
        check("dağılan topun bir kısmı etrafa sıçrar", e.groundMass > 0)

        // 8. Pencerenin üstündeki top
        let w = SnowEngine(width: 1470, height: 956)
        w.intensity = -0.12
        fill(w)
        var frame = CGRect(x: 500, y: 420, width: 600, height: 400)
        var wins = [SnowWindow(id: 9, frame: frame)]
        w.apply(windows: wins, dt: 0.1); w.apply(windows: wins, dt: 0.1)
        let onWin = make(w, at: 200, roll: 90, dropAt: CGPoint(x: 800, y: 300), windows: wins)
        run(w, 1.5, windows: wins)
        let sitting = ball(w, onWin)
        check("pencerenin üstüne bırakılan top orada durur", { if case .ledge(9, _) = sitting?.support { return true }; return false }())
        SnowCheck.render(w, wins, output, "kar-topu-4-pencere.png")
        let startX = sitting?.x ?? 0
        for _ in 0..<60 {               // yavaş taşıma: 120 nk/sn
            frame.origin.x += 2
            wins = [SnowWindow(id: 9, frame: frame)]
            w.apply(windows: wins, dt: dt)
            w.step(dt)
        }
        check("pencere yavaş taşınınca top onunla gider", abs((ball(w, onWin)?.x ?? 0) - startX - 120) < 3)
        for _ in 0..<22 {               // sert çekiş: pencere topun altından kayar
            frame.origin.x += 40
            wins = [SnowWindow(id: 9, frame: frame)]
            w.apply(windows: wins, dt: dt)
            w.step(dt)
        }
        check("pencere sertçe çekilince top düşer", ball(w, onWin)?.support != nil && ball(w, onWin)?.support != .ledge(9, 0)
              && { if case .ledge = ball(w, onWin)?.support { return false }; return true }())
        run(w, 2, windows: wins)
        check("düşen top zemine iner ya da yığına döner", ball(w, onWin)?.support == .ground || (ball(w, onWin) == nil && !w.sculpture.heaps.isEmpty))

        frame.origin.x = 500
        wins = [SnowWindow(id: 9, frame: frame)]
        run(w, 0.5, windows: wins)
        let onWin2 = make(w, at: 1300, roll: -60, dropAt: CGPoint(x: frame.midX, y: 300), windows: wins)
        run(w, 1.5, windows: wins)
        run(w, 2, windows: [])          // pencere kapandı
        check("pencere kapanınca üstündeki top düşer", ball(w, onWin2).map { $0.support == .ground } ?? (w.sculpture.collapses >= 1))

        // 9. Kar yağarken top beyazlanıp büyür
        let size = ball(e, first)?.r ?? 0
        e.intensity = 1
        run(e, 12)
        let grown = (ball(e, first)?.r ?? 0) - size
        check("yağan kar topa yapışır", grown > 0.02, "+\(String(format: "%.2f", grown))")
        let inside = e.particles.filter { p in
            p.kind == .flake && e.sculpture.balls.contains { hypot(p.x - $0.x, p.y - $0.y) < $0.r - 1 }
        }.count
        check("kar taneleri topun içinden geçmez", inside == 0, "\(inside) tane")
        e.intensity = -0.12

        // 10. Küreme aracı topları, kardan adamı ve yığınları kürer
        let q = SnowEngine(width: 1470, height: 956)
        q.intensity = -0.12
        fill(q)
        let small = make(q, at: 240, roll: 24, dropAt: CGPoint(x: 300, y: CGFloat(top(q, 300) - 30)))
        run(q, 1)
        let (qb, qm, qh) = snowman(q, at: 760)
        let loose = make(q, at: 1300, roll: -90, dropAt: CGPoint(x: 1150, y: 300))
        lift(q, loose, toY: 40)
        run(q, 2)
        let heapsBefore = q.sculpture.heaps.reduce(0) { $0 + $1.area }
        let smallStart = ball(q, small)?.x ?? 0
        let smallR = ball(q, small)?.r ?? 0
        check("küreme testi için top, kardan adam ve yığın hazır",
              smallR > 0 && smallR <= 32 && ball(q, qh) != nil && heapsBefore > 0, "küçük top r \(f(smallR))")
        fill(q)
        q.plowEnabled = true
        var pushed: Float = 0, smallMax: Float = smallR, shot = false
        for _ in 0..<(22 * 60) {
            q.step(dt)
            if let sb = ball(q, small) { pushed = max(pushed, sb.x - smallStart); smallMax = max(smallMax, sb.r) }
            if !shot, let p = q.plow, p.x > 640 { shot = true; SnowCheck.render(q, [], output, "kar-topu-5-kureme.png") }
        }
        check("küreme aracı geçer", q.plowTrips >= 1)
        check("küçük top bıçağın önünde yuvarlanır", pushed > 80, "\(f(pushed)) nk itildi")
        check("önünde yuvarlanan top karı toplayıp büyür", smallMax > smallR + 2, "r \(f(smallR)) → \(f(smallMax))")
        check("küreme aracı kardan adamı yıkar", [qb, qm, qh].allSatisfy { ball(q, $0) == nil })
        check("küreme aracı yerdeki yığını kürer", q.sculpture.heaps.reduce(0) { $0 + $1.area } < heapsBefore * 0.2,
              "önce \(f(heapsBefore)), sonra " + q.sculpture.heaps.map { "x \(f($0.x)) alan \(f($0.area)) taban \(f($0.base))" }.joined(separator: "; "))
        check("yerde top kalmaz", q.sculpture.balls.isEmpty, "\(q.sculpture.balls.count) top")

        // 11. Sınır ve çizim yükü
        let many = SnowEngine(width: 1470, height: 956)
        many.intensity = -0.12
        fill(many)
        for k in 0..<40 {
            let x = Float(40 + k * 34)
            many.handle(.grab(CGPoint(x: CGFloat(x), y: CGFloat(top(many, x) + 2))))
            many.handle(.release(.zero))
        }
        check("en fazla \(SnowSculpture.maxBalls) top olur", many.sculpture.balls.count == SnowSculpture.maxBalls)
        for b in many.sculpture.balls { many.handle(.decorate(b.id, [.face, .nose, .arms, .hat, .scarf, .buttons])) }
        run(many, 1)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 180_000 * 9)
        defer { buffer.deallocate() }
        let t0 = CFAbsoluteTimeGetCurrent()
        var count = 0
        for _ in 0..<20 { many.step(dt); count = many.buildVertices(into: buffer, capacity: 180_000) }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) / 20 * 1000
        check("30 süslü top çizim sınırına sığar", count < 180_000 - 1000, "\(count) köşe")
        check("30 topla kare süresi kısa kalır", ms < 4, String(format: "%.2f ms", ms))

        // 12. Kar kapanınca toplar erir
        e.setMelting(true)
        run(e, 12)
        check("kar kapanınca toplar ve yığınlar da erir", e.sculpture.balls.isEmpty && e.sculpture.heaps.isEmpty)

        gravity(output)

        print(failures == 0 ? "KARTOPU_GECTI" : "KARTOPU_KALDI \(failures)")
        return failures == 0 ? 0 : 1
    }
}
