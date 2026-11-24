import AppKit
import Combine
import SwiftUI

/// Menü çubuğunun üstünde duran, odak çalmayan pencere.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class IslandHostingView: NSHostingView<IslandRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Pencereyi çentiğe yerleştirir, fareyi izler ve pil, ses, müzik gibi kaynakları adaya bağlar.
final class IslandController {
    let manager: IslandManager
    private let panel: IslandPanel
    private var monitors: [Any] = []
    private var hover = HoverLogic()
    private var hoverWork: DispatchWorkItem?
    private let power = PowerWatch()
    private let audio = AudioWatch()
    private var bag: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var running = false
    private var screen: NSScreen?
    private var refreshTimer: Timer?

    init(manager: IslandManager) {
        self.manager = manager
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: IslandLayout.canvas),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let host = IslandHostingView(rootView: IslandRootView(manager: manager))
        host.frame = NSRect(origin: .zero, size: IslandLayout.canvas)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        manager.setSystemVolume = { [weak self] v in self?.audio.setVolume(v) }
        manager.onExpand = { [weak self] in self?.didExpand() }
        manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.stateChanged() }
            .store(in: &bag)
        manager.settings.$enabled.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &bag)
        manager.settings.$noNotch.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.place() }
            .store(in: &bag)
        manager.settings.$fullscreenMode.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkFullscreen() }
            .store(in: &bag)
        apply()
    }

    // MARK: - Açma ve kapama

    private func apply() {
        if manager.settings.enabled { start() } else { stop() }
    }

    private func start() {
        guard !running else { return }
        running = true
        place()
        panel.orderFrontRegardless()
        manager.media.start()
        power.onChange = { [weak self] s, e in self?.manager.powerChanged(s, e) }
        power.start()
        manager.power = power.state
        audio.onVolume = { [weak self] v, muted in self?.manager.volumeChanged(v, muted: muted) }
        audio.onDevice = { [weak self] o in self?.manager.show(.device(o), seconds: 3) }
        audio.start()
        manager.volume = audio.volume
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.pointer(dragging: e.type == .leftMouseDragged) }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.pointer(dragging: e.type == .leftMouseDragged); return e }) {
            monitors.append(l)
        }
        if let c = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.clickedOutside() }) {
            monitors.append(c)
        }
        let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.place()
        })
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.checkFullscreen()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.checkFullscreen() }   // tam ekran animasyonu bitsin
            })
        }
        checkFullscreen()
    }

    private func stop() {
        guard running else { return }
        running = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        power.stop()
        audio.stop()
        manager.media.stop()
        manager.collapse()
        refreshTimer?.invalidate()
        refreshTimer = nil
        panel.orderOut(nil)
    }

    /// Çentikli ekranı seçer; yoksa ayara göre ana ekranın üst ortasını kullanır.
    private func place() {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let chosen = notched ?? (manager.settings.noNotch ? (NSScreen.main ?? NSScreen.screens.first) : nil)
        screen = chosen
        manager.hasScreen = chosen != nil
        guard let s = chosen else { return }
        let g = IslandGeometry.of(s)
        if manager.geometry != g { manager.geometry = g }
        let c = IslandLayout.canvas
        panel.setFrame(NSRect(x: g.notch.midX - c.width / 2, y: s.frame.maxY - c.height, width: c.width, height: c.height), display: true)
    }

    private func checkFullscreen() {
        guard let s = screen else { return }
        let full = FullscreenDetector.frontIsFullscreen(on: s)
        if manager.fullscreen != full { manager.fullscreen = full }
    }

    // MARK: - Fare

    private var shapeRects: [CGRect] {
        let d = manager.display, g = manager.geometry
        guard d != .hidden || !g.hasNotch else { return [] }
        var out = [IslandLayout.rect(d, g)]
        if manager.secondary != nil { out.append(IslandLayout.bubbleRect(d, g)) }
        return out
    }

    private func pointer(dragging: Bool) {
        guard running else { return }
        let p = NSEvent.mouseLocation
        let d = manager.display, g = manager.geometry
        let trigger = IslandLayout.trigger(d == .hidden ? .closed : d, g).contains(p)
        let inside = trigger || shapeRects.contains { $0.insetBy(dx: -2, dy: -2).contains(p) }
        setCapture(inside)
        if dragging {
            // Dosya çentiğe sürüklenince raf açılır ve bırakmayı kabul eder.
            if trigger, manager.settings.isOn(.shelf), !quietFullscreen(d), Self.dragHasFiles() {
                manager.expand(page: .shelf)
                setCapture(true)
            }
            return
        }
        guard d != .alert, !quietFullscreen(d) else { return }
        hover.delay = manager.settings.hoverDelay
        let expandedRect = IslandLayout.rect(.expanded, g).insetBy(dx: -14, dy: -14)
        let action = hover.update(inTrigger: trigger, inExpanded: expandedRect.contains(p), expanded: manager.expanded,
                                  enabled: manager.settings.hoverOpen, now: Date())
        hoverWork?.cancel()
        switch action {
        case .none: break
        case .expand: manager.expand()
        case .collapse: if !manager.dropTargeted { manager.collapse() }
        case .recheck(let after):
            let w = DispatchWorkItem { [weak self] in self?.pointer(dragging: false) }
            hoverWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + after + 0.01, execute: w)
        }
    }

    /// Tam ekranda ada boşken fare menü çubuğuna gidince açılmasın.
    private func quietFullscreen(_ d: IslandDisplay) -> Bool {
        manager.fullscreen && manager.settings.fullscreenMode != .normal && d == .hidden
    }

    private func clickedOutside() {
        guard manager.expanded else { return }
        let p = NSEvent.mouseLocation
        if !IslandLayout.rect(.expanded, manager.geometry).contains(p) { manager.collapse() }
    }

    private func setCapture(_ on: Bool) {
        if panel.ignoresMouseEvents == on { panel.ignoresMouseEvents = !on }
    }

    private static func dragHasFiles() -> Bool {
        let pb = NSPasteboard(name: .drag)
        return pb.types?.contains(.fileURL) == true
    }

    // MARK: - Durum değişince

    private func stateChanged() {
        guard running else { return }
        // Durum değişince şekil fareden kaçmış olabilir; yakalama yeniden hesaplanır.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            let d = self.manager.display
            let inside = self.shapeRects.contains { $0.contains(p) } || IslandLayout.trigger(d == .hidden ? .closed : d, self.manager.geometry).contains(p)
            self.setCapture(inside)
            if !self.manager.expanded { self.refreshTimer?.invalidate(); self.refreshTimer = nil }
        }
    }

    private func didExpand() {
        if manager.settings.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        manager.volume = audio.volume
        manager.media.refreshPosition()
        refreshTimer?.invalidate()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.manager.expanded else { return }
            self.manager.media.refreshPosition()
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }
}
