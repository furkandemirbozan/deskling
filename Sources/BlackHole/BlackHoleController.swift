import AppKit
import QuartzCore

/// Kara deliğin ortasındaki görünmez alan: dosya bırakma, taşıma ve sağ tık menüsü buradan gelir.
final class HoleHitView: NSView {
    weak var controller: BlackHoleController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { controller?.grab() }
    override func mouseDragged(with e: NSEvent) { controller?.dragHole() }
    override func mouseUp(with e: NSEvent) { controller?.letGo() }
    override func rightMouseDown(with e: NSEvent) { controller?.showMenu(e, in: self) }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { controller?.hover(s) ?? [] }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { controller?.hover(s) ?? [] }
    override func draggingExited(_ s: NSDraggingInfo?) { controller?.hoverEnded() }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { controller?.drop(s) ?? false }
}

/// Masaüstünün sol üst köşesinde duran, sürüklenebilir kara delik.
final class BlackHoleController: NSObject {
    static let size = NSSize(width: 440, height: 300)
    static let rs: CGFloat = 36
    static let hitSide: CGFloat = 170
    private static let level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    let window: NSWindow
    let hitPanel: NSPanel
    let hitView: HoleHitView
    let fx = CALayer()
    private let metal = CAMetalLayer()
    private let renderer: HoleRenderer?
    private var link: CVDisplayLink?
    private let persist: Bool

    // Ana iş parçacığının istediği görünüş; görüntü iş parçacığı buna yumuşakça yaklaşır.
    private struct Target {
        var pull: Float = 0
        var tint = SIMD3<Float>(0.62, 0.48, 1)
        var tintAmount: Float = 0
        var pulse: Float = 0
        var spin: Float = 1
        var cursor = SIMD2<Float>(0, 0)
        var cursorOn: Float = 0
        var burstStart: Double = -10
    }
    private let lock = NSLock()
    private var target = Target()
    private var look = HoleLook()
    private var phase: Float = 0
    private var lastFrame = CACurrentMediaTime()
    private var skipCount = 0

    private(set) var center: NSPoint
    private(set) var isVisible = false
    private(set) var busy = false
    private(set) var lastResult: HoleResult?
    var trashOriginal = false
    var onTrashOriginalChange: (Bool) -> Void = { _ in }
    var settings = HoleSettings()
    var onSettingsChange: (HoleSettings) -> Void = { _ in }
    var onHide: () -> Void = {}
    var trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    var onFinished: (HoleResult) -> Void = { _ in }
    /// Uzun işlerde ilerleme (dinamik ada için).
    var onProgress: (HoleJob) -> Void = { _ in }

    private var hoverMode: HoleMode = .normal
    private var grabStart: (mouse: NSPoint, center: NSPoint)?
    private var moved = false
    private var screenObserver: NSObjectProtocol?

    static func tint(_ m: HoleMode) -> SIMD3<Float> {
        switch m {
        case .normal: return SIMD3(0.62, 0.48, 1)
        case .white: return SIMD3(0.9, 0.96, 1)
        case .red: return SIMD3(1, 0.22, 0.2)
        }
    }

    static var defaultCenter: NSPoint {
        let v = DesktopMap.screen.visibleFrame
        return NSPoint(x: v.minX + 175, y: v.maxY - 145)   // sonuç etiketi menü çubuğunun altında kalmasın
    }

    init(persist: Bool = true) {
        self.persist = persist
        let d = UserDefaults.standard
        var c = Self.defaultCenter
        if persist, d.object(forKey: "holeCenterX") != nil {
            let saved = NSPoint(x: d.double(forKey: "holeCenterX"), y: d.double(forKey: "holeCenterY"))
            if NSScreen.screens.contains(where: { $0.frame.contains(saved) }) { c = saved }
        }
        center = c
        renderer = HoleRenderer()

        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = Self.level
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        hitView = HoleHitView(frame: NSRect(x: 0, y: 0, width: Self.hitSide, height: Self.hitSide))
        hitPanel = NSPanel(contentRect: hitView.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hitPanel.isOpaque = false
        hitPanel.backgroundColor = NSColor(white: 0, alpha: 0.01)   // gözle görünmez ama bırakmayı kesin yakalar
        hitPanel.hasShadow = false
        hitPanel.hidesOnDeactivate = false
        hitPanel.isReleasedWhenClosed = false
        hitPanel.level = Self.level
        hitPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hitPanel.contentView = hitView
        super.init()
        hitView.controller = self

        let scale = DesktopMap.screen.backingScaleFactor
        let view = NSView(frame: NSRect(origin: .zero, size: Self.size))
        let root = CALayer()
        view.layer = root
        view.wantsLayer = true
        root.frame = view.bounds
        metal.device = renderer?.device
        metal.pixelFormat = .bgra8Unorm
        metal.isOpaque = false
        metal.framebufferOnly = true
        metal.frame = view.bounds
        metal.contentsScale = scale
        metal.drawableSize = CGSize(width: Self.size.width * scale, height: Self.size.height * scale)
        root.addSublayer(metal)
        fx.frame = view.bounds
        root.addSublayer(fx)
        window.contentView = view
        look.size = SIMD2(Float(Self.size.width * scale), Float(Self.size.height * scale))
        look.center = look.size / 2
        look.rs = Float(Self.rs * scale)
        layout()

        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(self.center) }) { self.resetPosition() }
        }
    }

    // MARK: - Konum ve görünürlük

    private func layout() {
        window.setFrameOrigin(NSPoint(x: center.x - Self.size.width / 2, y: center.y - Self.size.height / 2))
        hitPanel.setFrameOrigin(NSPoint(x: center.x - Self.hitSide / 2, y: center.y - Self.hitSide / 2))
    }

    func setVisible(_ on: Bool) {
        isVisible = on
        if on {
            window.orderFrontRegardless()
            hitPanel.orderFrontRegardless()
            startLink()
        } else {
            window.orderOut(nil)
            hitPanel.orderOut(nil)
            stopLink()
        }
    }

    func resetPosition() {
        center = Self.defaultCenter
        layout()
        save()
    }

    private func save() {
        guard persist else { return }
        UserDefaults.standard.set(Double(center.x), forKey: "holeCenterX")
        UserDefaults.standard.set(Double(center.y), forKey: "holeCenterY")
    }

    func grab() {
        grabStart = (NSEvent.mouseLocation, center)
        moved = false
    }

    func dragHole() {
        guard let g = grabStart else { return }
        let m = NSEvent.mouseLocation
        if hypot(m.x - g.mouse.x, m.y - g.mouse.y) > 3 { moved = true }
        guard moved else { return }
        center = NSPoint(x: g.center.x + m.x - g.mouse.x, y: g.center.y + m.y - g.mouse.y)
        layout()
    }

    func letGo() {
        if moved { save() } else { lock.lock(); target.burstStart = CACurrentMediaTime(); lock.unlock() }   // dokununca dalgalanır
        grabStart = nil
    }

    // MARK: - Sürükle bırak

    private func fileURLs(_ s: NSDraggingInfo) -> [URL] {
        (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func pixel(_ global: NSPoint) -> SIMD2<Float> {
        let scale = window.backingScaleFactor
        return SIMD2(Float((global.x - window.frame.minX) * scale), Float((window.frame.maxY - global.y) * scale))
    }

    /// Dosya üstüne gelince çekim alanı genişler, dönüş hızlanır, renk moda göre değişir.
    func hover(_ s: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(s)
        guard !urls.isEmpty, !busy else { return [] }
        let flags = NSEvent.modifierFlags
        hoverMode = HoleProcessor.mode(for: urls, shift: flags.contains(.shift), option: flags.contains(.option))
        let global = hitPanel.convertPoint(toScreen: s.draggingLocation)
        lock.lock()
        target.pull = 1
        target.tint = Self.tint(hoverMode)
        target.tintAmount = 0.85
        target.spin = 3.4
        target.cursor = pixel(global)
        target.cursorOn = 1
        lock.unlock()
        return hoverMode == .red ? .generic : .copy
    }

    func hoverEnded() {
        guard !busy else { return }
        lock.lock()
        target.pull = 0
        target.tintAmount = 0
        target.spin = 1
        target.cursorOn = 0
        lock.unlock()
    }

    func drop(_ s: NSDraggingInfo) -> Bool {
        let urls = fileURLs(s)
        guard !urls.isEmpty, !busy else { return false }
        let flags = NSEvent.modifierFlags
        let mode = HoleProcessor.mode(for: urls, shift: flags.contains(.shift), option: flags.contains(.option))
        let global = hitPanel.convertPoint(toScreen: s.draggingLocation)
        receive(urls, mode: mode, at: NSPoint(x: global.x - window.frame.minX, y: global.y - window.frame.minY))
        return true
    }

    /// Dosyaları içine çeker, arka planda işler, sonucu fırlatıp etiketle gösterir.
    func receive(_ urls: [URL], mode: HoleMode, at point: NSPoint) {
        guard !busy else { return }
        busy = true
        suck(urls, from: point)
        lock.lock()
        target.cursorOn = 0
        target.pull = 0.55
        target.pulse = 1
        target.spin = 2.6
        target.tint = Self.tint(mode)
        target.tintAmount = 0.85
        lock.unlock()

        let started = CACurrentMediaTime()
        let trashOriginal = trashOriginal, trash = trash, settings = settings
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var shown = -1
            let result = HoleProcessor.process(urls, mode: mode, trashOriginal: trashOriginal, settings: settings, trash: trash) { p in
                let percent = Int(p * 100)
                guard percent != shown, CACurrentMediaTime() - started > 1.2 else { return }   // kısa işlerde yüzde gösterilmez
                shown = percent
                DispatchQueue.main.async { self?.showProgress(percent, urls: urls) }
            }
            let wait = max(0, 1.2 - (CACurrentMediaTime() - started))   // çekme animasyonu bitsin
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                self?.finish(result, urls: urls, from: point, mode: mode)
            }
        }
    }

    private func finish(_ r: HoleResult, urls: [URL], from point: NSPoint, mode: HoleMode) {
        busy = false
        progressBox?.removeFromSuperlayer()
        progressBox = nil
        lastResult = r
        lock.lock()
        target.pulse = 0
        target.pull = 0
        target.spin = 1
        target.burstStart = CACurrentMediaTime()
        target.tintAmount = r.ok ? 0.6 : 0.3
        lock.unlock()
        if r.consumed {
            eject(r.outputs, tint: Self.tint(mode))
        } else {
            spitBack(urls, to: point)
        }
        showLabel(r.title, r.detail, ok: r.ok)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.busy else { return }
            self.lock.lock(); self.target.tintAmount = 0; self.lock.unlock()
        }
        onFinished(r)
    }

    // MARK: - Animasyonlar

    private var hole: CGPoint { CGPoint(x: Self.size.width / 2, y: Self.size.height / 2) }

    private func icon(_ u: URL) -> CGImage? {
        let image = NSWorkspace.shared.icon(forFile: u.path)
        image.size = NSSize(width: 128, height: 128)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func iconLayer(_ u: URL) -> CALayer {
        let l = CALayer()
        l.contents = icon(u)
        l.contentsGravity = .resizeAspect
        l.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
        l.contentsScale = window.backingScaleFactor
        return l
    }

    /// Dosya simgesi spiral çizerek diske yassılır, olay ufkuna yaklaşınca uzayıp kaybolur.
    func suck(_ urls: [URL], from point: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let c = hole, rs = Self.rs
        for (i, u) in urls.prefix(6).enumerated() {
            let l = iconLayer(u)
            let start = CGPoint(x: point.x + CGFloat(i) * 9, y: point.y - CGFloat(i) * 7)
            l.position = start
            l.opacity = 0
            fx.addSublayer(l)
            let dx = start.x - c.x, dy = start.y - c.y
            let r0 = max(hypot(dx, dy), rs * 1.6), a0 = atan2(dy, dx)
            let dir: CGFloat = -1
            var places: [NSValue] = [], shapes: [NSValue] = [], alphas: [Double] = []
            let steps = 44
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps)
                let e = pow(t, 1.6)
                let r = r0 * (1 - e) + rs * 0.2 * e
                let a = a0 + dir * 2.3 * .pi * e
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * (1 - 0.7 * e))   // diskin düzlemine yassılır
                places.append(NSValue(point: p))
                let radial = atan2(p.y - c.y, p.x - c.x)
                let s = max(0.03, 1 - 0.97 * pow(t, 1.25))
                let stretch = 1 + 2.6 * e * e, squeeze = 1 / (1 + 1.6 * e)
                var m = CATransform3DMakeRotation(dir * t * .pi * 0.8, 0, 0, 1)
                m = CATransform3DConcat(m, CATransform3DMakeRotation(-radial, 0, 0, 1))
                m = CATransform3DConcat(m, CATransform3DMakeScale(s * stretch, s * squeeze, 1))
                m = CATransform3DConcat(m, CATransform3DMakeRotation(radial, 0, 0, 1))
                shapes.append(NSValue(caTransform3D: m))
                let fade = min(1, max(0, (r - rs * 0.6) / (rs * 0.5)))
                alphas.append(Double(t > 0.97 ? 0 : fade))
            }
            let move = CAKeyframeAnimation(keyPath: "position"); move.values = places
            let shape = CAKeyframeAnimation(keyPath: "transform"); shape.values = shapes
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = alphas
            let g = CAAnimationGroup()
            g.animations = [move, shape, fade]
            g.duration = 1.0
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.07
            g.fillMode = .backwards
            g.timingFunction = CAMediaTimingFunction(name: .linear)
            l.add(g, forKey: "fx")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 + Double(i) * 0.07) { l.removeFromSuperlayer() }
        }
    }

    /// Çıktı dosyası parçacıklarla birlikte kara delikten dışarı fırlar.
    private func eject(_ outputs: [URL], tint: SIMD3<Float>) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let c = hole, rs = Self.rs
        let color = CGColor(srgbRed: CGFloat(0.55 + tint.x * 0.45), green: CGFloat(0.55 + tint.y * 0.45), blue: CGFloat(0.55 + tint.z * 0.45), alpha: 1)
        for k in 0..<22 {   // kıvılcımlar
            let a = CGFloat(k) / 22 * 2 * .pi + CGFloat.random(in: -0.1...0.1)
            let d = CALayer()
            let size = CGFloat.random(in: 2...4.5)
            d.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            d.cornerRadius = size / 2
            d.backgroundColor = color
            d.position = c
            d.opacity = 0
            fx.addSublayer(d)
            let reach = CGFloat.random(in: rs * 1.6...rs * 3.4)
            let m = CABasicAnimation(keyPath: "position")
            m.fromValue = NSValue(point: CGPoint(x: c.x + cos(a) * rs * 1.05, y: c.y + sin(a) * rs * 1.05))
            m.toValue = NSValue(point: CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach * 0.8))
            let f = CAKeyframeAnimation(keyPath: "opacity"); f.values = [0, 1, 0]
            let g = CAAnimationGroup()
            g.animations = [m, f]
            g.duration = Double.random(in: 0.6...0.9)
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            d.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { d.removeFromSuperlayer() }
        }
        for (i, u) in outputs.prefix(4).enumerated() {
            let l = iconLayer(u)
            l.position = c
            l.opacity = 0
            fx.addSublayer(l)
            let a = CGFloat.pi * 0.62 - CGFloat(i) * 0.42
            let end = CGPoint(x: c.x + cos(a) * rs * 2.7, y: c.y + sin(a) * rs * 1.6 - 6)
            let path = CGMutablePath()
            path.move(to: c)
            path.addQuadCurve(to: end, control: CGPoint(x: c.x + cos(a) * rs * 1.4, y: c.y + rs * 2.2))
            let move = CAKeyframeAnimation(keyPath: "position"); move.path = path
            move.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let scale = CAKeyframeAnimation(keyPath: "transform.scale"); scale.values = [0.1, 1.15, 0.95, 0.9]; scale.keyTimes = [0, 0.35, 0.55, 1]
            let spin = CABasicAnimation(keyPath: "transform.rotation.z"); spin.fromValue = -2.4; spin.toValue = 0
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.12, 0.7, 1]
            let g = CAAnimationGroup()
            g.animations = [move, scale, spin, fade]
            g.duration = 1.6
            g.beginTime = CACurrentMediaTime() + 0.05 + Double(i) * 0.12
            g.fillMode = .backwards
            l.add(g, forKey: "fx")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8 + Double(i) * 0.12) { l.removeFromSuperlayer() }
        }
    }

    /// İşlenemeyen dosya kara delikten geri tükürülür; dosyanın kendisi hiç yerinden oynamamıştır.
    private func spitBack(_ urls: [URL], to point: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let c = hole
        for (i, u) in urls.prefix(4).enumerated() {
            let l = iconLayer(u)
            l.position = point
            l.opacity = 0
            fx.addSublayer(l)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: c); move.toValue = NSValue(point: point)
            move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.4, 0.4, 1)
            let scale = CAKeyframeAnimation(keyPath: "transform.scale"); scale.values = [0.1, 1.1, 1]
            let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z"); shake.values = [0, 0.3, -0.25, 0.15, 0]
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.15, 0.75, 1]
            let g = CAAnimationGroup()
            g.animations = [move, scale, shake, fade]
            g.duration = 1.2
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.08
            g.fillMode = .backwards
            l.add(g, forKey: "fx")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4 + Double(i) * 0.08) { l.removeFromSuperlayer() }
        }
    }

    private(set) var label: CALayer?
    private(set) var progressBox: CALayer?

    /// Uzun süren işlerde (video gibi) kara deliğin üstünde yüzde gösterilir.
    private func showProgress(_ percent: Int, urls: [URL]) {
        guard busy else { return }
        let video = urls.allSatisfy(HoleProcessor.isVideo)
        let title = (video ? "Video işleniyor" : "İşleniyor") + " · %\(min(99, percent))"
        onProgress(HoleJob(title: video ? "Video işleniyor" : "İşleniyor", percent: min(99, percent)))
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        let w = ceil(text.size().width) + 26, h: CGFloat = 26
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let box = progressBox ?? {
            let b = CALayer()
            b.cornerRadius = 9
            b.backgroundColor = CGColor(gray: 0.08, alpha: 0.72)
            b.borderWidth = 1
            b.borderColor = CGColor(gray: 1, alpha: 0.18)
            let t = CATextLayer()
            t.alignmentMode = .center
            t.contentsScale = window.backingScaleFactor
            b.addSublayer(t)
            let bar = CALayer()
            bar.backgroundColor = CGColor(srgbRed: 0.75, green: 0.65, blue: 1, alpha: 0.9)
            bar.cornerRadius = 1
            b.addSublayer(bar)
            fx.addSublayer(b)
            progressBox = b
            return b
        }()
        box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        box.position = CGPoint(x: hole.x, y: hole.y + Self.rs * 2.45 + h / 2)
        if let t = box.sublayers?.first as? CATextLayer {
            t.string = text
            t.frame = CGRect(x: 8, y: 6, width: w - 16, height: h - 10)
        }
        if let bar = box.sublayers?.last, !(bar is CATextLayer) {
            bar.frame = CGRect(x: 8, y: 3, width: (w - 16) * CGFloat(min(100, percent)) / 100, height: 2)
        }
        CATransaction.commit()
    }

    /// Kara deliğin üstünde birkaç saniye durup kaybolan sonuç etiketi.
    private func showLabel(_ title: String, _ detail: String?, ok: Bool) {
        label?.removeFromSuperlayer()
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        if let detail {
            text.append(NSAttributedString(string: "\n" + detail, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.82),
            ]))
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        text.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: text.length))
        let bounds = text.boundingRect(with: NSSize(width: Self.size.width - 40, height: 80), options: [.usesLineFragmentOrigin])
        let w = min(Self.size.width - 20, ceil(bounds.width) + 26), h = ceil(bounds.height) + 14

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let box = CALayer()
        box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        box.position = CGPoint(x: hole.x, y: hole.y + Self.rs * 2.45 + h / 2)
        box.cornerRadius = 10
        box.backgroundColor = ok ? CGColor(gray: 0.08, alpha: 0.72) : CGColor(srgbRed: 0.45, green: 0.08, blue: 0.1, alpha: 0.8)
        box.borderWidth = 1
        box.borderColor = CGColor(gray: 1, alpha: 0.18)
        let t = CATextLayer()
        t.string = text
        t.isWrapped = true
        t.alignmentMode = .center
        t.contentsScale = window.backingScaleFactor
        t.frame = CGRect(x: 10, y: 6, width: w - 20, height: h - 12)
        box.addSublayer(t)
        box.opacity = 0
        fx.addSublayer(box)
        CATransaction.commit()

        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = box.position.y - 10; rise.toValue = box.position.y
        rise.duration = 0.3
        rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.08, 0.86, 1]
        fade.duration = 3.2
        box.add(rise, forKey: "rise")
        box.add(fade, forKey: "fade")
        label = box
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.25) { [weak self, weak box] in
            box?.removeFromSuperlayer()
            if self?.label === box { self?.label = nil }
        }
    }

    // MARK: - Sağ tık menüsü

    func showMenu(_ e: NSEvent, in view: NSView) {
        let menu = NSMenu()
        for line in ["Bırak: görsel, PDF ve video sıkıştır, PDF birleştir, ZIP yap, JSON/CSV dönüştür",
                     "⇧ Shift ile bırak: arşivi aç, PDF'i ayır, görselleri PDF yap, videodan ses ya da GIF çıkar",
                     "⌥ Option ile bırak: Çöp Sepeti'ne taşı"] {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let formats = NSMenu()
        let hasWebP = HoleTools.cwebp != nil
        for f in HoleSettings.Format.allCases {
            let item = NSMenuItem(title: f == .webp && !hasWebP ? "WebP (cwebp kurulu değil)" : f.title, action: #selector(pickFormat(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = f.rawValue
            item.state = settings.format == f ? .on : .off
            item.isEnabled = f != .webp || hasWebP
            formats.addItem(item)
        }
        let formatItem = NSMenuItem(title: "Görsel biçimi: \(settings.format.title)", action: nil, keyEquivalent: "")
        formatItem.submenu = formats
        menu.addItem(formatItem)
        let qualities = NSMenu()
        for q in HoleSettings.Quality.allCases {
            let item = NSMenuItem(title: q.title, action: #selector(pickQuality(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = q.rawValue
            item.state = settings.quality == q ? .on : .off
            qualities.addItem(item)
        }
        let qualityItem = NSMenuItem(title: "Sıkıştırma kalitesi: \(settings.quality.title)", action: nil, keyEquivalent: "")
        qualityItem.submenu = qualities
        menu.addItem(qualityItem)
        let gps = NSMenuItem(title: "Fotoğraflardan konum bilgisini sil", action: #selector(toggleLocation), keyEquivalent: "")
        gps.target = self
        gps.state = settings.stripLocation ? .on : .off
        menu.addItem(gps)
        let trashItem = NSMenuItem(title: "İşlemden sonra orijinali Çöp Sepeti'ne taşı", action: #selector(toggleTrash), keyEquivalent: "")
        trashItem.target = self
        trashItem.state = trashOriginal ? .on : .off
        menu.addItem(trashItem)
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Sol üst köşeye geri koy", action: #selector(resetFromMenu), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        let hide = NSMenuItem(title: "Kara deliği gizle", action: #selector(hideFromMenu), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        NSMenu.popUpContextMenu(menu, with: e, for: view)
    }

    @objc private func toggleTrash() {
        trashOriginal.toggle()
        onTrashOriginalChange(trashOriginal)
    }

    @objc private func pickFormat(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let f = HoleSettings.Format(rawValue: raw) else { return }
        settings.format = f
        onSettingsChange(settings)
    }

    @objc private func pickQuality(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let q = HoleSettings.Quality(rawValue: raw) else { return }
        settings.quality = q
        onSettingsChange(settings)
    }

    @objc private func toggleLocation() {
        settings.stripLocation.toggle()
        onSettingsChange(settings)
    }

    @objc private func resetFromMenu() { resetPosition() }
    @objc private func hideFromMenu() { onHide() }

    // MARK: - Kare döngüsü

    private func startLink() {
        guard link == nil, renderer != nil else { return }
        var created: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&created)
        guard let created else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(created, { _, _, _, _, _, context in
            Unmanaged<BlackHoleController>.fromOpaque(context!).takeUnretainedValue().frame()
            return kCVReturnSuccess
        }, me)
        lastFrame = CACurrentMediaTime()
        link = created
        CVDisplayLinkStart(created)
    }

    private func stopLink() {
        guard let link else { return }
        CVDisplayLinkStop(link)
        self.link = nil
    }

    private func frame() {
        autoreleasepool {
            let now = CACurrentMediaTime()
            let dt = Float(min(now - lastFrame, 0.1))
            lock.lock(); let t = target; lock.unlock()
            let calm = t.pull < 0.01 && t.pulse < 0.01 && look.pull < 0.02 && look.pulse < 0.02 && now - t.burstStart > 1.2
            // Boştayken yavaş dönen disk için saniyede 20 kare yeter.
            if calm {
                skipCount = (skipCount + 1) % 3
                if skipCount != 0 { return }
            }
            lastFrame = now
            let k = min(1, dt * 5)
            look.pull += (t.pull - look.pull) * k
            look.tintAmount += (t.tintAmount - look.tintAmount) * k
            look.pulse += (t.pulse - look.pulse) * min(1, dt * 8)
            look.tint += (t.tint - look.tint) * min(1, dt * 8)
            look.cursor = t.cursor
            look.cursorOn = t.cursorOn
            let spin = t.spin
            phase += dt * (0.55 + (spin - 1) * 0.5 + look.pull * 0.6)   // dönüş açısı birikerek ilerler, hız değişince sıçramaz
            look.time = phase
            look.spin = 1
            let b = Float((now - t.burstStart) / 0.9)
            look.burst = b >= 0 && b < 1 ? b : -1
            guard let renderer, let drawable = metal.nextDrawable() else { return }
            renderer.draw(look, to: drawable.texture, drawable: drawable)
        }
    }
}
