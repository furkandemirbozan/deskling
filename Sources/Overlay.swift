import AppKit
import QuartzCore

/// Robotun üstündeki görünmez tıklama alanı.
final class RobotHitView: NSView {
    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 { onClick() }
        if event.clickCount == 2 { onDoubleClick() }
    }
}

/// Masaüstü simgelerinin üstünde, uygulama pencerelerinin altında duran tıklanmaz sahne.
final class OverlayController {
    let window: NSWindow
    let root = CALayer()
    let hitView = RobotHitView(frame: NSRect(x: 0, y: 0, width: 92, height: 92))
    private let hitWindow: NSPanel
    let stationHitView = RobotHitView(frame: NSRect(x: 0, y: 0, width: 48, height: 100))
    private let stationWindow: NSPanel
    private var lastHitOrigin: NSPoint?

    private let station = CALayer()
    private let shadow = CALayer()
    private let robot = CALayer()
    private let brushL = CALayer()
    private let brushR = CALayer()
    private let lidar = CALayer()
    private let led = CALayer()
    private let badge = CATextLayer()
    private var demoCards: [String: CALayer] = [:]
    private var running = false

    private static func makeHitPanel(_ view: NSView) -> NSPanel {
        let p = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = NSColor(white: 0, alpha: 0.01)   // gözle görünmez ama tıklamayı kesin yakalar
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentView = view
        return p
    }

    init() {
        let s = DesktopMap.screen
        hitWindow = OverlayController.makeHitPanel(hitView)
        stationWindow = OverlayController.makeHitPanel(stationHitView)
        window = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: s)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: s.frame.size))
        view.layer = root
        view.wantsLayer = true
        root.frame = view.bounds
        root.contentsScale = s.backingScaleFactor
        window.contentView = view
        setOnTop(false)   // robot yalnızca masaüstünde görünür, pencerelerin arkasında kalır
        build()
    }

    private var onTopLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)

    func setOnTop(_ top: Bool) {
        onTopLevel = top ? .floating : NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        window.level = onTopLevel
        hitWindow.level = onTopLevel
        stationWindow.level = onTopLevel
    }

    func pulse(at p: CGPoint) { scanPulse(at: p) }

    /// Test için gerçek pencere olay yolundan tıklama gönderir.
    func simulateClick(count: Int, onStation: Bool = false) {
        let target = onStation ? stationWindow : hitWindow
        let center = NSPoint(x: 20, y: 20)
        guard let e = NSEvent.mouseEvent(with: .leftMouseDown, location: center, modifierFlags: [], timestamp: 0,
                                         windowNumber: target.windowNumber, context: nil, eventNumber: 1,
                                         clickCount: count, pressure: 1) else { return }
        target.sendEvent(e)
    }

    func show() {
        window.orderFrontRegardless()
        stationWindow.orderFrontRegardless()
        hitWindow.orderFrontRegardless()   // robot kutudan önce tıklansın
    }

    private func part(_ l: CALayer, _ image: CGImage, side: CGFloat) {
        l.contents = image
        l.contentsScale = RobotArt.scale
        l.bounds = CGRect(x: 0, y: 0, width: side, height: side)
    }

    private func build() {
        let S = RobotArt.size
        part(station, RobotArt.station, side: 120)
        root.addSublayer(station)
        part(shadow, RobotArt.shadow, side: S + 28)
        root.addSublayer(shadow)

        robot.bounds = CGRect(x: 0, y: 0, width: S, height: S)
        root.addSublayer(robot)
        let c = CGPoint(x: S / 2, y: S / 2)
        for (b, y) in [(brushL, CGFloat(29)), (brushR, CGFloat(-29))] {
            part(b, RobotArt.brush, side: 64)
            b.position = CGPoint(x: c.x + 27, y: c.y + y)
            robot.addSublayer(b)
        }
        let body = CALayer()
        part(body, RobotArt.body, side: S)
        body.position = c
        robot.addSublayer(body)
        part(lidar, RobotArt.lidar, side: S)
        lidar.position = c
        robot.addSublayer(lidar)
        led.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
        led.cornerRadius = 2.5
        led.position = CGPoint(x: c.x - 24, y: c.y + 15)
        led.shadowOpacity = 1
        led.shadowRadius = 4
        led.shadowOffset = .zero
        robot.addSublayer(led)

        badge.bounds = CGRect(x: 0, y: 0, width: 30, height: 22)
        badge.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.62, blue: 0.86, alpha: 1).cgColor
        badge.cornerRadius = 11
        badge.foregroundColor = NSColor.white.cgColor
        badge.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        badge.fontSize = 13
        badge.alignmentMode = .center
        badge.contentsScale = RobotArt.scale
        badge.opacity = 0
        root.addSublayer(badge)
        setLED(.systemGreen)
    }

    func placeStation(base: CGPoint) {
        instant { station.position = CGPoint(x: base.x - 46, y: base.y) }
        let f = DesktopMap.screen.frame
        stationWindow.setFrame(NSRect(x: f.minX + base.x - 76, y: f.minY + base.y - 50, width: 48, height: 100), display: false)
    }

    private func instant(_ f: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        f()
        CATransaction.commit()
    }

    private func setLED(_ color: NSColor) {
        led.backgroundColor = color.cgColor
        led.shadowColor = color.cgColor
    }

    // MARK: - Her kare

    func sync(_ e: RobotEngine) {
        let f = DesktopMap.screen.frame
        let origin = NSPoint(x: f.minX + e.pos.x - 46, y: f.minY + e.pos.y - 46)
        if origin != lastHitOrigin {
            lastHitOrigin = origin
            hitWindow.setFrameOrigin(origin)
        }
        instant {
            robot.position = e.pos
            robot.transform = CATransform3DMakeRotation(e.heading, 0, 0, 1)
            shadow.position = CGPoint(x: e.pos.x, y: e.pos.y - 4)
            badge.position = CGPoint(x: e.pos.x + 38, y: e.pos.y + 42)
            badge.string = "\(e.carrying)"
            badge.opacity = e.carrying > 0 ? 1 : 0
        }
    }

    func phaseChanged(_ p: Phase, engine e: RobotEngine) {
        setSpinning(p != .docked)
        switch p {
        case .docked: setLED(e.battery >= 100 ? .systemGreen : .systemOrange)
        case .scanning: setLED(.systemTeal); scanPulse(at: e.pos)
        case .vacuuming: setLED(.systemBlue)
        case .dumping: setLED(.systemYellow)
        default: setLED(.systemTeal)
        }
    }

    private func setSpinning(_ on: Bool) {
        guard on != running else { return }
        running = on
        guard on else {
            [brushL, brushR, lidar].forEach { $0.removeAnimation(forKey: "spin") }
            return
        }
        spin(brushL, duration: 0.42, clockwise: true)
        spin(brushR, duration: 0.42, clockwise: false)
        spin(lidar, duration: 1.1, clockwise: false)
    }

    private func spin(_ l: CALayer, duration: Double, clockwise: Bool) {
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = clockwise ? -2 * Double.pi : 2 * Double.pi
        a.duration = duration
        a.repeatCount = .infinity
        l.add(a, forKey: "spin")
    }

    // MARK: - Efektler

    private func scanPulse(at p: CGPoint) {
        for i in 0..<3 {
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: -60, y: -60, width: 120, height: 120), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = NSColor.systemTeal.withAlphaComponent(0.75).cgColor
            ring.lineWidth = 2
            ring.position = p
            ring.opacity = 0
            root.insertSublayer(ring, below: shadow)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.6; scale.toValue = 4.2
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9; fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [scale, fade]
            g.duration = 1.1
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.3
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ring.removeFromSuperlayer() }
        }
    }

    private func imageLayer(_ image: CGImage?, at p: CGPoint) -> CALayer {
        let l = CALayer()
        let img = image ?? RobotArt.demoCard(0)
        let w: CGFloat = 72
        let h = min(72, w * CGFloat(img.height) / CGFloat(max(img.width, 1)))
        l.contents = img
        l.contentsGravity = .resizeAspect
        l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        l.position = p
        l.shadowOpacity = 0.35
        l.shadowRadius = 5
        l.shadowOffset = CGSize(width: 0, height: -2)
        return l
    }

    /// Dosya önce direnir, sonra uzayıp küçülerek robotun ağzından içeri çekilir.
    func suck(_ job: Job, robot pos: CGPoint, heading: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let card = demoCards.removeValue(forKey: job.id) { card.removeFromSuperlayer() }
        let duration = 1.3
        let mouth = CGPoint(x: pos.x + cos(heading) * 34, y: pos.y + sin(heading) * 34)
        let direction = atan2(mouth.y - job.point.y, mouth.x - job.point.x)
        let swirl: CGFloat = Bool.random() ? 1 : -1

        // Arkadan gelen iki soluk kopya, hızlanırken iz bırakır.
        for echo in [2, 1, 0] {
            let l = imageLayer(job.thumb, at: job.point)
            l.opacity = 0
            l.shadowOpacity = echo == 0 ? 0.35 : 0
            root.insertSublayer(l, below: robot)
            let steps = 48
            var places: [NSValue] = [], shapes: [NSValue] = [], alphas: [Double] = []
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let p = SuckMotion.pose(max(0, t - CGFloat(echo) * 0.035), from: job.point, to: mouth, swirl: swirl)
                places.append(NSValue(point: p.position))
                shapes.append(NSValue(caTransform3D: SuckMotion.transform(p, direction: direction)))
                let trail: CGFloat = echo == 0 ? 1 : (t > SuckMotion.tug + 0.2 ? 0.34 / CGFloat(echo) : 0)
                alphas.append(Double(p.opacity * trail))
            }
            let move = CAKeyframeAnimation(keyPath: "position"); move.values = places
            let shape = CAKeyframeAnimation(keyPath: "transform"); shape.values = shapes
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = alphas
            let g = CAAnimationGroup()
            g.animations = [move, shape, fade]
            g.duration = duration
            g.timingFunction = CAMediaTimingFunction(name: .linear)
            l.add(g, forKey: "fx")
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { l.removeFromSuperlayer() }
        }

        // Robot emerken titrer, dosya girince yutkunur.
        let gulp = CAKeyframeAnimation(keyPath: "transform.scale")
        gulp.values = [1, 1.03, 0.98, 1.03, 0.98, 1.02, 1.11, 0.95, 1]
        gulp.keyTimes = [0, 0.14, 0.28, 0.42, 0.56, 0.72, 0.86, 0.94, 1]
        gulp.duration = duration + 0.1
        robot.add(gulp, forKey: "shake")
        suctionRings(at: mouth, duration: duration)
        dust(from: job.point, to: mouth, duration: duration)
    }

    /// Ağzın önünde içe doğru daralan hava halkaları.
    private func suctionRings(at p: CGPoint, duration: Double) {
        for i in 0..<4 {
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: -34, y: -34, width: 68, height: 68), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = NSColor(white: 1, alpha: 0.6).cgColor
            ring.lineWidth = 1.5
            ring.position = p
            ring.opacity = 0
            root.insertSublayer(ring, below: robot)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 2.3; scale.toValue = 0.15
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.8, 0]
            let g = CAAnimationGroup()
            g.animations = [scale, fade]
            g.duration = 0.55
            g.beginTime = CACurrentMediaTime() + Double(i) * (duration - 0.55) / 3
            g.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ring.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) { ring.removeFromSuperlayer() }
        }
    }

    /// Toz taneleri dosyanın çevresinden kopup ağza akar.
    private func dust(from p: CGPoint, to mouth: CGPoint, duration: Double) {
        for i in 0..<26 {
            let d = CALayer()
            let r = CGFloat.random(in: 1.1...2.5)
            let a = CGFloat(i) / 26 * 2 * .pi
            let reach = CGFloat.random(in: 34...92)
            let from = CGPoint(x: p.x + cos(a) * reach, y: p.y + sin(a) * reach)
            d.bounds = CGRect(x: 0, y: 0, width: r * 5, height: r * 1.6)
            d.cornerRadius = r * 0.8
            d.backgroundColor = NSColor(white: 0.86, alpha: 0.9).cgColor
            d.position = mouth
            d.opacity = 0
            d.transform = CATransform3DMakeRotation(atan2(mouth.y - from.y, mouth.x - from.x), 0, 0, 1)
            root.insertSublayer(d, below: robot)
            let m = CABasicAnimation(keyPath: "position")
            m.fromValue = NSValue(point: from); m.toValue = NSValue(point: mouth)
            let f = CAKeyframeAnimation(keyPath: "opacity")
            f.values = [0, 1, 1, 0]
            let g = CAAnimationGroup()
            g.animations = [m, f]
            g.duration = 0.6
            g.beginTime = CACurrentMediaTime() + Double.random(in: 0...(duration - 0.6))
            g.timingFunction = CAMediaTimingFunction(name: .easeIn)
            d.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) { d.removeFromSuperlayer() }
        }
    }

    /// Robot bir simgeye vurduğunda çıkan darbe halkası, kıvılcımlar ve sarsıntı.
    func impact(at p: CGPoint, angle: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -16, y: -16, width: 32, height: 32), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = NSColor(white: 1, alpha: 0.85).cgColor
        ring.lineWidth = 2.5
        ring.position = p
        ring.opacity = 0
        root.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.4; grow.toValue = 2.4
        let vanish = CABasicAnimation(keyPath: "opacity")
        vanish.fromValue = 0.9; vanish.toValue = 0
        let burst = CAAnimationGroup()
        burst.animations = [grow, vanish]
        burst.duration = 0.32
        burst.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(burst, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ring.removeFromSuperlayer() }

        for i in 0..<8 {
            let a = angle + (CGFloat(i) - 3.5) * 0.36 + CGFloat.random(in: -0.1...0.1)
            let spark = CALayer()
            spark.bounds = CGRect(x: 0, y: 0, width: 11, height: 2.2)
            spark.cornerRadius = 1.1
            spark.backgroundColor = NSColor(calibratedRed: 1, green: 0.86, blue: 0.45, alpha: 1).cgColor
            spark.position = p
            spark.opacity = 0
            spark.transform = CATransform3DMakeRotation(a, 0, 0, 1)
            root.addSublayer(spark)
            let reach = CGFloat.random(in: 24...46)
            let m = CABasicAnimation(keyPath: "position")
            m.fromValue = NSValue(point: p)
            m.toValue = NSValue(point: CGPoint(x: p.x + cos(a) * reach, y: p.y + sin(a) * reach))
            let f = CABasicAnimation(keyPath: "opacity")
            f.fromValue = 1; f.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [m, f]
            g.duration = 0.3
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            spark.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { spark.removeFromSuperlayer() }
        }

        let jolt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        jolt.values = [0, 0.14, -0.09, 0.05, 0]
        jolt.isAdditive = true
        jolt.duration = 0.3
        robot.add(jolt, forKey: "jolt")
    }

    /// Toplanan görüntüler robottan istasyondaki kutuya kavis çizerek uçar.
    func dump(images: [CGImage], from p: CGPoint, to trash: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (i, image) in images.enumerated() {
            let l = imageLayer(image, at: p)
            l.opacity = 0
            root.addSublayer(l)
            let path = CGMutablePath()
            path.move(to: p)
            path.addQuadCurve(to: trash, control: CGPoint(x: (p.x + trash.x) / 2, y: max(p.y, trash.y) + 80))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.3; scale.toValue = 0.22
            let rot = CABasicAnimation(keyPath: "transform.rotation.z")
            rot.fromValue = 0; rot.toValue = -2 * Double.pi
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.1, 0.85, 1]
            let g = CAAnimationGroup()
            g.animations = [move, scale, rot, fade]
            g.duration = 0.75
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.16
            g.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(g, forKey: "fx")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { l.removeFromSuperlayer() }
        }
        // Kutu, görüntüler içine düşerken hafifçe esner.
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1, 1.07, 0.97, 1]
        bounce.duration = 0.35
        bounce.beginTime = CACurrentMediaTime() + 0.6
        station.add(bounce, forKey: "bounce")
    }

    // MARK: - Demo

    func showDemoCards(_ jobs: [Job]) {
        for (i, j) in jobs.enumerated() {
            let l = imageLayer(RobotArt.demoCard(i), at: j.point)
            l.opacity = 0
            root.insertSublayer(l, below: shadow)
            demoCards[j.id] = l
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            l.opacity = 1
            CATransaction.commit()
        }
    }

    func clearDemoCards() {
        demoCards.values.forEach { $0.removeFromSuperlayer() }
        demoCards.removeAll()
    }
}
