import AppKit

/// Çekme, çarpma ve gezinti davranışını geçici klasörde ve sahte simgelerle dener.
/// Finder'a hiçbir şey göndermez, gerçek masaüstüne dokunmaz.
final class MotionCheck {
    private let fm = FileManager.default
    private let output: URL?
    private var failures = 0
    private var model: AppModel?
    private var overlay: OverlayController?

    init(output: URL?) {
        self.output = output
        if let output { try? fm.createDirectory(at: output, withIntermediateDirectories: true) }
    }

    private func check(_ name: String, _ ok: Bool) {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name)
        if !ok { failures += 1 }
    }

    func run() {
        routes()
        cruising()
        standoff()
        iconPhysics()
        suckShape()
        scripts()
        visuals { [self] in mission() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 150) { print("HAREKET_ZAMAN_ASIMI"); exit(2) }
    }

    // MARK: - Rotalar

    private func routes() {
        let area = CGRect(x: 120, y: 120, width: 1200, height: 660)
        var planner = PatrolPlanner()
        var list: [PatrolRoute] = []
        for _ in 0..<60 { list.append(planner.next(in: area)) }
        check("art arda iki gezinti aynı biçimde olmaz", zip(list, list.dropFirst()).allSatisfy { $0.style != $1.style })
        check("altı rota biçiminin hepsi kullanılır", Set(list.map(\.style)).count == PatrolStyle.allCases.count)
        check("hiçbir rota birebir tekrar etmez", Set(list.map { $0.points.map { "\($0.x),\($0.y)" }.joined(separator: ";") }).count == list.count)
        check("rota noktaları güvenli alanda kalır", list.allSatisfy { $0.points.allSatisfy { area.insetBy(dx: -0.01, dy: -0.01).contains($0) } })
        check("her rotada en az altı nokta olur", list.allSatisfy { $0.points.count >= 6 })
    }

    private func cruising() {
        let area = CGRect(x: 120, y: 120, width: 1200, height: 660)
        var planner = PatrolPlanner()
        var allFinished = true, inside = true, smooth = true, noPickup = true
        for _ in 0..<24 {
            let route = planner.next(in: area)
            let e = RobotEngine(base: CGPoint(x: 130, y: 84), trash: CGPoint(x: 222, y: 84))
            var ended = false
            e.onMissionEnd = { ended = true }
            e.onPickup = { _ in noPickup = false; return false }
            e.start(route.points.enumerated().map { Job(id: "patrol-\($0)", point: $1, shot: nil, thumb: nil, waypoint: true) })
            var t = 0.0, last = e.heading, wasCruising = false
            while !ended && t < 240 {
                e.tick(1.0 / 60); t += 1.0 / 60
                let cruising = e.current?.waypoint == true && e.phase == .driving
                if cruising, wasCruising {   // yola çıkmadan önceki yerinde dönüş sayılmaz
                    var d = abs(e.heading - last).truncatingRemainder(dividingBy: 2 * .pi)
                    if d > .pi { d = 2 * .pi - d }
                    if d > 0.06 { smooth = false }
                    if !CGRect(x: 0, y: 0, width: 1440, height: 900).contains(e.pos) { inside = false }
                }
                wasCruising = cruising
                last = e.heading
            }
            if !ended || e.pos != e.basePoint { allFinished = false }
        }
        check("her rota tamamlanır ve robot istasyona döner", allFinished)
        check("gezinti noktalarında dosya alınmaz", noPickup)
        check("robot gezerken ani dönmez, kavis çizer", smooth)
        check("robot gezerken ekrandan çıkmaz", inside)
    }

    // MARK: - Dosyanın önünde durma

    private func standoff() {
        let e = RobotEngine(base: CGPoint(x: 130, y: 84), trash: CGPoint(x: 222, y: 84))
        let job = CGPoint(x: 900, y: 600)
        var gap: CGFloat = -1, facing: CGFloat = 9
        e.onPickup = { j in
            gap = hypot(e.pos.x - j.point.x, e.pos.y - j.point.y)
            facing = abs(atan2(j.point.y - e.pos.y, j.point.x - e.pos.x) - e.heading)
            return true
        }
        var ended = false
        e.onMissionEnd = { ended = true }
        e.start([Job(id: "a", point: job, shot: nil, thumb: nil)])
        var t = 0.0
        while !ended && t < 60 { e.tick(1.0 / 60); t += 1.0 / 60 }
        check("robot dosyanın önünde durur, üstüne çıkmaz", abs(gap - RobotEngine.standoff) < 3)
        check("robot ağzını dosyaya çevirir", facing < 0.05)

        let near = RobotEngine(base: CGPoint(x: 500, y: 500), trash: CGPoint(x: 592, y: 500))
        var nearFacing: CGFloat = 9
        let close = CGPoint(x: 500, y: 560)
        near.onPickup = { j in
            nearFacing = abs(atan2(j.point.y - near.pos.y, j.point.x - near.pos.x) - near.heading)
            return false
        }
        near.start([Job(id: "b", point: close, shot: nil, thumb: nil)])
        for _ in 0..<240 { near.tick(1.0 / 60) }
        check("dosya çok yakındaysa robot yerinde dönüp ona bakar", nearFacing < 0.05)
    }

    // MARK: - Çarpma

    private func field(_ icons: [String: CGPoint]) -> IconField {
        let f = IconField()
        f.bounds = CGRect(x: 56, y: 56, width: 1300, height: 760)
        f.load(icons)
        return f
    }

    private func iconPhysics() {
        let robot = CGPoint(x: 600, y: 400)
        let ahead = CGPoint(x: 660, y: 400)

        var f = field(["klasor": ahead])
        var s = f.hit(robot: robot, heading: 0, speed: 240, now: 10, blocked: [])
        check("değen klasör itilir", s.count == 1)
        check("klasör robottan uzağa savrulur", s.first.map { hypot($0.to.x - robot.x, $0.to.y - robot.y) > 60 } ?? false)
        check("tam karşıdan vurunca yolun kenarına kayar", s.first.map { abs($0.to.y - 400) > 12 } ?? false)
        check("aynı klasöre hemen yeniden çarpılmaz", f.hit(robot: robot, heading: 0, speed: 240, now: 10.2, blocked: []).isEmpty)

        f = field(["uzak": CGPoint(x: 900, y: 400)])
        check("değmeyen klasör yerinde kalır", f.hit(robot: robot, heading: 0, speed: 240, now: 1, blocked: []).isEmpty)

        f = field(["arka": CGPoint(x: 540, y: 400)])
        check("robotun arkasındaki klasöre çarpılmaz", f.hit(robot: robot, heading: 0, speed: 240, now: 1, blocked: []).isEmpty)

        f = field(["klasor": ahead])
        check("duran robot klasörü itmez", f.hit(robot: robot, heading: 0, speed: 0, now: 1, blocked: []).isEmpty)

        f = field(["hedef.png": ahead])
        f.ignored = ["hedef.png"]
        check("toplanacak ekran görüntüsü itilmez", f.hit(robot: robot, heading: 0, speed: 240, now: 1, blocked: []).isEmpty)

        let rug = CGRect(x: 630, y: 340, width: 200, height: 140)
        f = field(["ortulu": ahead])
        check("halının altındaki dosyaya dokunulmaz", f.hit(robot: robot, heading: 0, speed: 240, now: 1, blocked: [rug]).isEmpty)

        var underRug = false, overlap = false, outside = false
        for _ in 0..<300 {
            let wall = CGPoint(x: CGFloat.random(in: 70...1340), y: CGFloat.random(in: 70...800))
            let a = CGFloat.random(in: 0...(2 * .pi))
            let r = CGPoint(x: wall.x - cos(a) * 55, y: wall.y - sin(a) * 55)
            let block = CGRect(x: wall.x + 60, y: wall.y - 70, width: 160, height: 140)
            f = field(["k": wall, "komsu": CGPoint(x: wall.x + cos(a) * 130, y: wall.y + sin(a) * 130)])
            f.ignored = ["komsu"]
            s = f.hit(robot: r, heading: a, speed: 240, now: 1, blocked: [block])
            for slide in s {
                if block.insetBy(dx: -40, dy: -40).contains(slide.to) { underRug = true }
                if let k = f.icons["komsu"], hypot(k.x - slide.to.x, k.y - slide.to.y) < IconField.spacing { overlap = true }
                if !f.bounds.insetBy(dx: -0.01, dy: -0.01).contains(slide.to) { outside = true }
            }
        }
        check("itilen simge halının altına girmez", !underRug)
        check("itilen simge başka simgenin üstüne binmez", !overlap)
        check("itilen simge ekran dışına çıkmaz", !outside)

        let frames = FinderIcons.frames(IconSlide(name: "a", from: CGPoint(x: 100, y: 700), to: CGPoint(x: 200, y: 600)), screenHeight: 900)
        check("kayma Finder koordinatında doğru yere varır", frames.last == CGPoint(x: 200, y: 300))
        let steps = zip(frames, frames.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        check("simge kayarken yavaşlayarak durur", steps.first! > steps.last!)
        let parsed = FinderIcons.parse("120,80,Yeni, Klasör\nbozuk\n300,200,not.txt", screenHeight: 900)
        check("virgüllü dosya adları doğru okunur", parsed == ["Yeni, Klasör": CGPoint(x: 120, y: 820), "not.txt": CGPoint(x: 300, y: 700)])
    }

    // MARK: - Çekme

    private func suckShape() {
        let a = CGPoint(x: 500, y: 300), b = CGPoint(x: 430, y: 300)
        let first = SuckMotion.pose(0, from: a, to: b, swirl: 1)
        let last = SuckMotion.pose(1, from: a, to: b, swirl: 1)
        let mid = SuckMotion.pose(0.75, from: a, to: b, swirl: 1)
        check("çekme dosyanın tam yerinden başlar", first.position == a && first.along == 1 && first.across == 1)
        check("dosya robotun ağzında biter", hypot(last.position.x - b.x, last.position.y - b.y) < 0.5)
        check("dosya sona doğru iyice küçülür", last.along < 0.1 && last.across < 0.1 && last.opacity == 0)
        check("dosya çekilirken çekiş yönünde uzar", mid.along > mid.across)
        var sizes: [CGFloat] = []
        for i in 0...20 {
            let p = SuckMotion.pose(0.2 + CGFloat(i) / 20 * 0.8, from: a, to: b, swirl: 1)
            sizes.append(sqrt(p.along * p.across))
        }
        check("dosya hep küçülerek ilerler", sizes.last! < sizes.first! * 0.1)
    }

    private func scripts() {
        for (name, source) in [("okuma", FinderIcons.readScript), ("kaydırma", FinderIcons.slideScript)] {
            let out = fm.temporaryDirectory.appendingPathComponent("robo-\(UUID().uuidString).scpt")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
            p.arguments = ["-e", source, "-o", out.path]
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            check("Finder \(name) betiği derlenir", p.terminationStatus == 0)
            try? fm.removeItem(at: out)
        }
    }

    // MARK: - Görsel kareler

    private func visuals(then next: @escaping () -> Void) {
        let o = OverlayController()
        overlay = o
        o.show()
        let size = DesktopMap.screen.frame.size
        let c = CGPoint(x: size.width / 2 - 42, y: size.height / 2)
        let e = RobotEngine(base: c, trash: c)
        o.sync(e)
        o.suck(Job(id: "kare", point: CGPoint(x: c.x + RobotEngine.standoff, y: c.y), shot: nil, thumb: RobotArt.demoCard(0)), robot: c, heading: 0)
        for (name, t) in [("cekme-1", 0.12), ("cekme-2", 0.62), ("cekme-3", 0.92), ("cekme-4", 1.14)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [self] in
                if let output { SelfTest.capture(o.root, to: output.appendingPathComponent(name + ".png")) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            o.impact(at: CGPoint(x: c.x + 58, y: c.y), angle: 0.3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [self] in
            if let output { SelfTest.capture(o.root, to: output.appendingPathComponent("carpma.png")) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: next)
    }

    // MARK: - Uçtan uca gezinti

    private func mission() {
        let tmp = fm.temporaryDirectory.appendingPathComponent("robo-motion-\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let m = AppModel(desktopOverride: tmp)
        m.silent = true
        model = m
        let s = DesktopMap.screen.frame.size

        // Ekranın her yanına yayılmış sahte simgeler.
        var icons: [String: CGPoint] = [:]
        for ix in 0..<9 {
            for iy in 0..<6 {
                icons["simge-\(ix)-\(iy)"] = CGPoint(x: s.width * (CGFloat(ix) + 1) / 10, y: s.height * (CGFloat(iy) + 1) / 7)
            }
        }
        let rug = CGRect(x: s.width * 0.42, y: s.height * 0.4, width: 260, height: 180)
        let hidden = Set(icons.filter { rug.contains($0.value) }.keys)
        m.rugFrameLocal = { rug }
        m.iconReader = { done in DispatchQueue.main.async { done(icons) } }
        var slides: [IconSlide] = []
        m.iconSlider = { slides.append($0) }
        m.attach(overlay!)

        m.onMissionFinished = { [self] in
            let moved = Set(slides.map(\.name))
            check("gezinti sırasında simgelere çarpılır (\(slides.count) çarpma)", !slides.isEmpty)
            check("halının altındaki simgelere çarpılmaz", moved.isDisjoint(with: hidden))
            check("itilen simgeler halının altına girmez", slides.allSatisfy { !rug.contains($0.to) })
            check("robot görev sonunda istasyona döner", m.engine.pos == m.engine.basePoint)
            check("gezinti hiçbir dosyayı toplamaz", m.history.isEmpty)
            try? fm.removeItem(at: tmp)
            print(failures == 0 ? "HAREKET_GECTI" : "HAREKET_KALDI \(failures)")
            exit(failures == 0 ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { m.cleanAllNow() }
    }
}
