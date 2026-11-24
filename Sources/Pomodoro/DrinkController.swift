import AppKit
import SwiftUI

/// Bardağın gövdesindeki görünmez alan: sürükleme, çift tık, sağ tık ve üzerine gelme buradan gelir.
final class DrinkHitView: NSView {
    weak var controller: DrinkController?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with e: NSEvent) { controller?.setHover(glass: true) }
    override func mouseExited(with e: NSEvent) { controller?.setHover(glass: false) }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount >= 2 { controller?.doubleClick() } else { controller?.grab(at: NSEvent.mouseLocation) }
    }
    override func mouseDragged(with e: NSEvent) { controller?.drag(to: NSEvent.mouseLocation) }
    override func mouseUp(with e: NSEvent) { controller?.letGo() }
    override func rightMouseDown(with e: NSEvent) { controller?.showMenu(e, in: self) }
}

/// Kontrol çubuğunun düğmeleri, uygulama öne gelmeden ilk tıklamada çalışsın.
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    weak var controller: DrinkController?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with e: NSEvent) { controller?.setHover(bar: true) }
    override func mouseExited(with e: NSEvent) { controller?.setHover(bar: false) }
}

/// Masaüstünde duran, sürüklenebilen Pomodoro içeceği.
final class DrinkController: NSObject {
    static let barSize = NSSize(width: 252, height: 54)
    private static let level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    let pomo: PomodoroManager
    let window: NSWindow
    let view: DrinkView
    let hitPanel: NSPanel
    let hitView: DrinkHitView
    let barPanel: NSPanel
    private let persist: Bool

    var kind: DrinkKind = .tea { didSet { if kind != oldValue { view.state.kind = kind; layout(); redraw() } } }
    var scale: Double = 1 { didSet { if scale != oldValue { layout(); redraw() } } }
    var effects: DrinkEffects = .high { didSet { if effects != oldValue { view.state.effects = effects; restartTimer() } } }

    var onChooseKind: (DrinkKind) -> Void = { _ in }
    var onChooseScale: (Double) -> Void = { _ in }
    var onHide: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    /// Bardağın tabanının ortası (ekran koordinatı). Boyut değişince bardak yerinde büyür.
    private(set) var anchor: NSPoint
    private(set) var isVisible = false
    /// Testler kareleri elle ilerletir.
    var runsTimer = true
    var frameInterval: TimeInterval? { timer?.timeInterval }
    private(set) var barShown = false
    private var hoverGlass = false, hoverBar = false
    private var hideWork: DispatchWorkItem?
    private var grabStart: (mouse: NSPoint, anchor: NSPoint)?
    private(set) var moved = false
    private var tracker = MotionTracker()
    private var timer: Timer?
    private var lastFrame = CACurrentMediaTime()
    private var screenObserver: NSObjectProtocol?

    static var defaultAnchor: NSPoint {
        let v = DesktopMap.screen.visibleFrame
        return NSPoint(x: v.maxX - 300, y: v.minY + 150)   // sağ altta; robotun istasyonu sol altta
    }

    init(pomo: PomodoroManager, persist: Bool = true) {
        self.pomo = pomo
        self.persist = persist
        let d = UserDefaults.standard
        var a = Self.defaultAnchor
        if persist, d.object(forKey: "pomoAnchorX") != nil {
            let saved = NSPoint(x: d.double(forKey: "pomoAnchorX"), y: d.double(forKey: "pomoAnchorY"))
            if NSScreen.screens.contains(where: { $0.frame.contains(saved) }) { a = saved }
        }
        anchor = a

        view = DrinkView(frame: NSRect(origin: .zero, size: DrinkArt.canvas))
        window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = Self.level
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = view

        hitView = DrinkHitView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        hitPanel = NSPanel(contentRect: hitView.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hitPanel.isOpaque = false
        hitPanel.backgroundColor = NSColor(white: 0, alpha: 0.01)   // görünmez ama tıklamayı yakalar
        hitPanel.hasShadow = false
        hitPanel.hidesOnDeactivate = false
        hitPanel.isReleasedWhenClosed = false
        hitPanel.level = Self.level
        hitPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hitPanel.contentView = hitView

        barPanel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.barSize), styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        barPanel.isOpaque = false
        barPanel.backgroundColor = .clear
        barPanel.hasShadow = false
        barPanel.hidesOnDeactivate = false
        barPanel.isReleasedWhenClosed = false
        barPanel.level = Self.level
        barPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        barPanel.alphaValue = 0
        super.init()
        hitView.controller = self
        let host = FirstMouseHostingView(rootView: DrinkControlBar(pomo: pomo))
        host.frame = NSRect(origin: .zero, size: Self.barSize)
        host.controller = self
        barPanel.contentView = host

        view.state.kind = kind
        layout()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(self.anchor) }) { self.resetPosition() }
        }
    }

    // MARK: - Yerleşim

    var canvasSize: NSSize { NSSize(width: DrinkArt.canvas.width * scale, height: DrinkArt.canvas.height * scale) }

    /// Gövdenin ekrandaki yeri.
    var bodyFrame: NSRect {
        let b = DrinkArt.body(kind), o = window.frame.origin
        return NSRect(x: o.x + b.minX * scale, y: o.y + b.minY * scale, width: b.width * scale, height: b.height * scale)
    }

    private func layout() {
        let size = canvasSize
        let base = DrinkArt.body(kind).minY * scale
        window.setFrame(NSRect(x: anchor.x - size.width / 2, y: anchor.y - base, width: size.width, height: size.height), display: false)
        view.frame = NSRect(origin: .zero, size: size)
        hitPanel.setFrame(bodyFrame, display: false)
        hitView.frame = NSRect(origin: .zero, size: bodyFrame.size)
        placeBar()
    }

    /// Çubuk bardağın altında durur; ekranın altına sığmazsa üstüne geçer.
    private func placeBar() {
        let body = bodyFrame, s = Self.barSize
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? DesktopMap.screen
        var y = body.minY - s.height - 6
        if y < screen.visibleFrame.minY + 4 { y = body.maxY + 6 }
        var x = body.midX - s.width / 2
        x = min(max(x, screen.visibleFrame.minX + 4), screen.visibleFrame.maxX - s.width - 4)
        barPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func setVisible(_ on: Bool) {
        guard on != isVisible else { return }
        isVisible = on
        if on {
            window.orderFrontRegardless()
            hitPanel.orderFrontRegardless()
            lastFrame = CACurrentMediaTime()
            restartTimer()
        } else {
            window.orderOut(nil)
            hitPanel.orderOut(nil)
            hideBar(animated: false)
            timer?.invalidate()
            timer = nil
        }
    }

    func resetPosition() {
        anchor = Self.defaultAnchor
        layout()
        save()
    }

    private func save() {
        guard persist else { return }
        UserDefaults.standard.set(Double(anchor.x), forKey: "pomoAnchorX")
        UserDefaults.standard.set(Double(anchor.y), forKey: "pomoAnchorY")
    }

    // MARK: - Fare

    func grab(at mouse: NSPoint) {
        grabStart = (mouse, anchor)
        moved = false
    }

    func drag(to mouse: NSPoint) {
        guard let g = grabStart else { return }
        if hypot(mouse.x - g.mouse.x, mouse.y - g.mouse.y) > 3 { moved = true }
        guard moved else { return }
        anchor = NSPoint(x: g.anchor.x + mouse.x - g.mouse.x, y: g.anchor.y + mouse.y - g.mouse.y)
        layout()
    }

    func letGo() {
        if moved { save() } else { view.state.slosh.kick(tilt: 0, wave: -0.9) }   // dokununca sıvı hafifçe sıçrar
        grabStart = nil
    }

    func doubleClick() {
        grabStart = nil
        pomo.toggle()
        view.state.slosh.kick(tilt: 0, wave: -1.4)
    }

    func setHover(glass: Bool? = nil, bar: Bool? = nil) {
        if let glass { hoverGlass = glass }
        if let bar { hoverBar = bar }
        if hoverGlass || hoverBar {
            hideWork?.cancel()
            showBar()
        } else {
            hideWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.hideBar(animated: true) }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: w)
        }
    }

    private func showBar() {
        guard isVisible, !barShown else { return }
        barShown = true
        placeBar()
        barPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.18
            barPanel.animator().alphaValue = 1
        }
    }

    private func hideBar(animated: Bool) {
        guard barShown else { return }
        barShown = false
        guard animated else { barPanel.alphaValue = 0; barPanel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.25
            barPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.barShown else { return }
            self.barPanel.orderOut(nil)
        })
    }

    // MARK: - Sağ tık menüsü

    func menu() -> NSMenu {
        let m = NSMenu()
        for k in DrinkKind.allCases {
            let i = NSMenuItem(title: k.title, action: #selector(pickKind(_:)), keyEquivalent: "")
            i.representedObject = k.rawValue
            i.state = k == kind ? .on : .off
            i.target = self
            m.addItem(i)
        }
        m.addItem(.separator())
        let current = DrinkSize.nearest(scale)
        for s in DrinkSize.allCases {
            let i = NSMenuItem(title: s.title, action: #selector(pickSize(_:)), keyEquivalent: "")
            i.representedObject = s.rawValue
            i.state = s == current ? .on : .off
            i.target = self
            m.addItem(i)
        }
        m.addItem(.separator())
        addItem(m, pomo.phase == .idle ? "Odak Başlat" : pomo.running ? "Duraklat" : "Devam Et", #selector(toggleTimer))
        if pomo.phase != .idle {
            addItem(m, pomo.phase == .focus ? "Molaya Geç" : "Molayı Atla", #selector(skipPhase))
            addItem(m, "Sayacı Sıfırla", #selector(resetTimer))
        }
        m.addItem(.separator())
        addItem(m, "Pomodoro Ayarları…", #selector(openSettings))
        addItem(m, "Gizle", #selector(hide))
        return m
    }

    private func addItem(_ m: NSMenu, _ title: String, _ sel: Selector) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        m.addItem(i)
    }

    func showMenu(_ e: NSEvent, in v: NSView) { NSMenu.popUpContextMenu(menu(), with: e, for: v) }

    @objc private func pickKind(_ i: NSMenuItem) {
        if let k = DrinkKind(rawValue: i.representedObject as? String ?? "") { onChooseKind(k) }
    }
    @objc private func pickSize(_ i: NSMenuItem) {
        if let s = DrinkSize(rawValue: i.representedObject as? String ?? "") { onChooseScale(s.scale) }
    }
    @objc private func toggleTimer() { pomo.toggle() }
    @objc private func skipPhase() { pomo.skip() }
    @objc private func resetTimer() { pomo.reset() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func hide() { onHide() }

    // MARK: - Sayaçla bağlantı

    /// Odak başlayınca bardak boşalır ve yeniden dolar; süre bitince titrer.
    func transition(_ t: PomoTransition) {
        if t.to == .focus, t.from != .focus { view.state.level = 0.02 }
        if t.finished, t.from == .focus {
            view.state.shake = 1
            view.state.slosh.kick(tilt: 0.9, wave: -1.2)
        }
        redraw()
    }

    /// Sıvının olması gereken seviyesi: odakta kalan süreyle azalır, molada ve hazırda doludur.
    var targetLevel: Double {
        pomo.phase == .focus ? max(0.08, 1 - pomo.progress * 0.92) : 1
    }

    var targetSteam: Double {
        switch pomo.phase {
        case .focus: return max(0, 1 - pow(pomo.progress, 1.6)) * (pomo.progress > 0.94 ? (1 - pomo.progress) / 0.06 : 1)
        case .idle, .shortBreak, .longBreak: return 0.75
        }
    }

    // MARK: - Kare döngüsü

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard isVisible, runsTimer else { return }
        let t = Timer(timeInterval: 1.0 / Double(fast ? effects.activeFps : effects.fps), repeats: true) { [weak self] _ in self?.frame() }
        t.tolerance = 0.002
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Bir kare ilerletir. Testler zamanı elle verir.
    func frame(dt given: Double? = nil) {
        let now = CACurrentMediaTime()
        let dt = given ?? min(0.1, now - lastFrame)
        lastFrame = now
        var s = view.state
        s.time += dt
        tracker.update(CGPoint(x: anchor.x, y: anchor.y), dt: dt)
        s.slosh.step(dt: dt, accel: tracker.accel)

        let target = targetLevel
        if target - s.level > 0.03 {
            // Dolum: sıvı akarak yükselir, yüzey akışın çarptığı yerde dalgalanır.
            s.level = min(target, s.level + dt * 0.5)
            s.pour = min(1, s.pour + dt * 5)
            s.slosh.kick(tilt: 0, wave: -dt * 0.8)
        } else {
            s.level += (target - s.level) * min(1, dt * 3)
            s.pour = max(0, s.pour - dt * 3)
        }
        s.steam += (targetSteam - s.steam) * min(1, dt * 0.8)
        s.shake = max(0, s.shake - dt * 1.2)
        s.progress = pomo.progress
        s.phase = pomo.phase
        s.running = pomo.running
        view.particles.step(dt: dt, state: s)
        view.state = s
        // Sakinken yarı kare hızında çizilir; sürükleme, dolum ve titremede tam hız.
        // Sakinken düşük, hareket varken yüksek kare hızı.
        let lively = grabStart != nil || s.pour > 0 || s.shake > 0 || s.slosh.energy > 2e-4
        if lively != fast, runsTimer, given == nil { fast = lively; view.fastFrames = lively; restartTimer() }
        redraw()
    }
    private(set) var fast = false

    func redraw() { view.render() }
}
