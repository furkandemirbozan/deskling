import AppKit
import QuartzCore

// MARK: - Halının altı

struct RugItem: Equatable {
    let url: URL
    var name: String { url.lastPathComponent }
}

/// Halı altına süpürülen dosyalar masaüstünden bu özel klasöre taşınır, böylece robot onları hiç göremez.
final class RugStore {
    let dir: URL
    private let manifest: URL
    private var origins: [String: String] = [:]
    private(set) var items: [RugItem] = []
    var onChange: () -> Void = {}
    private let queue = DispatchQueue(label: "robo.rug", qos: .userInitiated)

    init(dir: URL) {
        self.dir = dir
        manifest = dir.deletingLastPathComponent().appendingPathComponent(".hali-kayit.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: manifest),
           let map = try? JSONDecoder().decode([String: String].self, from: data) { origins = map }
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let fresh = sorted.map { RugItem(url: $0) }
        let names = Set(fresh.map(\.name))
        let pruned = origins.filter { names.contains($0.key) }
        if pruned.count != origins.count { origins = pruned; save() }
        if fresh != items { items = fresh; onChange() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(origins) { try? data.write(to: manifest, options: .atomic) }
    }

    /// Sistem klasörleri, uygulamanın kendisi ve halı klasörünü içeren klasörler halı altına giremez.
    func canSweep(_ url: URL) -> Bool {
        let fm = FileManager.default
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let store = dir.standardizedFileURL.resolvingSymlinksInPath().path
        guard fm.fileExists(atPath: url.path), path != "/", path != store,
              !path.hasPrefix(store + "/"), !store.hasPrefix(path + "/") else { return false }
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        if path == bundle || path.hasPrefix(bundle + "/") || bundle.hasPrefix(path + "/") { return false }
        var roots = ["/Applications", "/Library", "/System", "/Users", "/Volumes", "/private", "/usr", "/bin", "/sbin", "/opt"]
        for d in [FileManager.SearchPathDirectory.desktopDirectory, .documentDirectory, .downloadsDirectory, .picturesDirectory,
                  .moviesDirectory, .musicDirectory, .libraryDirectory] {
            roots += fm.urls(for: d, in: .userDomainMask).map { $0.resolvingSymlinksInPath().path }
        }
        roots.append(fm.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path)
        return !roots.contains(path)
    }

    func sweep(_ urls: [URL], completion: @escaping (_ moved: Int, _ failed: Int) -> Void) {
        let allowed = urls.filter(canSweep)
        var failed = urls.count - allowed.count
        queue.async { [self] in
            var added: [String: String] = [:]
            for url in allowed {
                let dest = Cleaner.uniqueURL(dir.appendingPathComponent(url.lastPathComponent))
                do {
                    try FileManager.default.moveItem(at: url, to: dest)
                    added[dest.lastPathComponent] = url.path
                } catch {
                    failed += 1
                }
            }
            DispatchQueue.main.async { [self] in
                origins.merge(added) { _, new in new }
                save()
                reload()
                completion(added.count, failed)
            }
        }
    }

    /// Dosyayı geldiği yere, orası yoksa masaüstüne geri koyar.
    @discardableResult
    func restore(_ item: RugItem, fallback: URL) throws -> URL {
        var target = fallback.appendingPathComponent(item.name)
        if let original = origins[item.name] {
            let url = URL(fileURLWithPath: original)
            if FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) { target = url }
        }
        let dest = Cleaner.uniqueURL(target)
        try FileManager.default.moveItem(at: item.url, to: dest)
        reload()
        return dest
    }
}

// MARK: - Halı görünümü

final class RugView: NSView, NSDraggingSource {
    static let padding: CGFloat = 14
    static var windowSize: CGSize {
        CGSize(width: RugArt.size.width + padding * 2, height: RugArt.size.height + padding * 2)
    }

    static let scaleRange = 0.6...1.6

    static func sizeFor(scale: CGFloat) -> CGSize {
        CGSize(width: RugArt.size.width * scale + padding * 2, height: RugArt.size.height * scale + padding * 2)
    }

    let store: RugStore
    var restoreFallback: URL
    var onSetScale: (Double) -> Void = { _ in }
    var onHide: () -> Void = {}
    var onMoved: () -> Void = {}
    var onOpenFolder: () -> Void = {}
    var onSwept: (_ moved: Int, _ failed: Int) -> Void = { _, _ in }
    var testMouse: NSPoint?

    private let root = CALayer()
    private let ground = CAShapeLayer()
    private let floorLayer = CALayer()
    private let floorMask = CAShapeLayer()
    private let itemsLayer = CALayer()
    private let shade = CAShapeLayer()
    private let rug = CALayer()
    private let rugMask = CAShapeLayer()
    private let flapShadow = CAShapeLayer()
    private let flap = CALayer()
    private let flapMask = CAShapeLayer()
    private let crease = CAShapeLayer()
    private let backImage = CALayer()

    private var rugRect: CGRect { bounds.insetBy(dx: Self.padding, dy: Self.padding) }

    // Katlama durumu
    private var corner: CGPoint?
    private var foldPoint: CGPoint = .zero
    private var exposed: [CGPoint] = []
    private var mid: CGPoint = .zero
    private var normal: CGPoint = .zero
    private var hinting = false
    private var autoFolded = false
    private var foldTimer: Timer?
    private let minimumFold: CGFloat = 70

    var isFolded: Bool { corner != nil && !hinting && dist(corner!, foldPoint) >= minimumFold }

    // Fare durumu
    private enum Drag { case none, move(mouse: NSPoint, origin: NSPoint), fold(wasOpen: Bool), item(RugItem) }
    private var drag: Drag = .none
    private var moved = false
    private var downEvent: NSEvent?
    private var downPoint: CGPoint = .zero

    // Halı altındaki simgeler
    private var cells: [(rect: CGRect, item: RugItem?)] = []
    private var layoutKey = ""

    init(store: RugStore, restoreFallback: URL) {
        self.store = store
        self.restoreFallback = restoreFallback
        super.init(frame: NSRect(origin: .zero, size: Self.windowSize))
        layer = root
        wantsLayer = true
        root.frame = bounds
        build()
        registerForDraggedTypes([.fileURL])
        store.onChange = { [weak self] in self?.layoutItems() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func build() {
        let r = rugRect
        let body = r.insetBy(dx: 13, dy: 0)
        ground.path = CGPath(rect: body, transform: nil)
        ground.fillColor = NSColor.black.cgColor
        ground.shadowColor = NSColor.black.cgColor
        ground.shadowOpacity = 0.55
        ground.shadowRadius = 9
        ground.shadowOffset = CGSize(width: 0, height: -4)
        root.addSublayer(ground)

        floorLayer.frame = bounds
        floorLayer.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.075, blue: 0.055, alpha: 1).cgColor
        floorMask.frame = bounds
        floorLayer.mask = floorMask
        floorLayer.isHidden = true
        itemsLayer.frame = bounds
        floorLayer.addSublayer(itemsLayer)
        shade.frame = bounds
        shade.fillColor = nil
        shade.strokeColor = NSColor.black.cgColor
        shade.lineWidth = 2
        shade.shadowColor = NSColor.black.cgColor
        shade.shadowOpacity = 0.95
        shade.shadowRadius = 16
        shade.shadowOffset = .zero
        floorLayer.addSublayer(shade)
        root.addSublayer(floorLayer)

        rug.frame = r
        rug.contents = RugArt.front
        rug.contentsGravity = .resize
        rug.magnificationFilter = .nearest
        rugMask.frame = rug.bounds
        root.addSublayer(rug)

        flapShadow.fillColor = nil   // saçak aralarından siyah görünmesin
        flapShadow.shadowColor = NSColor.black.cgColor
        flapShadow.shadowOpacity = 0.65
        flapShadow.shadowRadius = 10
        flapShadow.shadowOffset = CGSize(width: 0, height: -3)
        flapShadow.isHidden = true
        root.addSublayer(flapShadow)

        flap.anchorPoint = .zero
        flap.bounds = bounds
        flap.position = .zero
        flap.isHidden = true
        backImage.frame = r
        backImage.contents = RugArt.back
        backImage.contentsGravity = .resize
        backImage.magnificationFilter = .nearest
        flap.addSublayer(backImage)
        flapMask.frame = bounds
        flap.mask = flapMask
        root.addSublayer(flap)

        crease.fillColor = nil
        crease.strokeColor = NSColor(calibratedRed: 0.95, green: 0.88, blue: 0.72, alpha: 0.4).cgColor
        crease.lineWidth = 1.5
        crease.isHidden = true
        root.addSublayer(crease)
    }

    /// Pencere boyutu değişince tüm katmanları yeni boyuta oturtur.
    func relayout() {
        foldTimer?.invalidate()
        corner = nil
        hinting = false
        autoFolded = false
        applyFold()
        clearItems()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.frame = bounds
        let r = rugRect
        let fringe = 13 * r.width / RugArt.size.width
        ground.path = CGPath(rect: r.insetBy(dx: fringe, dy: 0), transform: nil)
        for l in [floorLayer, floorMask, itemsLayer, shade, flapMask] { l.frame = bounds }
        rug.frame = r
        rugMask.frame = rug.bounds
        flap.bounds = bounds
        backImage.frame = r
    }

    // MARK: - Geometri

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private func dot(_ p: CGPoint) -> CGFloat { (p.x - mid.x) * normal.x + (p.y - mid.y) * normal.y }

    private func reflect(_ p: CGPoint) -> CGPoint {
        let d = dot(p)
        return CGPoint(x: p.x - 2 * d * normal.x, y: p.y - 2 * d * normal.y)
    }

    private func clip(_ poly: [CGPoint], keepCornerSide: Bool) -> [CGPoint] {
        var out: [CGPoint] = []
        let side: (CGPoint) -> CGFloat = { [self] in keepCornerSide ? dot($0) : -dot($0) }
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let da = side(a), db = side(b)
            if da >= 0 { out.append(a) }
            if (da >= 0) != (db >= 0) {
                let t = da / (da - db)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out
    }

    private func path(_ pts: [CGPoint], offset: CGPoint = .zero) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) })
        p.closeSubpath()
        return p
    }

    private func nearestCorner(_ p: CGPoint) -> CGPoint {
        let r = rugRect
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].min { dist($0, p) < dist($1, p) }!
    }

    private func inward(_ c: CGPoint, by amount: CGFloat) -> CGPoint {
        let r = rugRect
        let a = min(amount, r.width * 0.7)   // küçük halıda da kat, halının içinde kalsın
        return CGPoint(x: c.x + (c.x < r.midX ? a : -a), y: c.y + (c.y < r.midY ? a * 0.72 : -a * 0.72))
    }

    private func applyFold() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let c = corner, dist(c, foldPoint) > 1 else {
            rug.mask = nil
            floorLayer.isHidden = true
            flap.isHidden = true
            flapShadow.isHidden = true
            crease.isHidden = true
            exposed = []
            return
        }
        let r = rugRect
        let rect = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        mid = CGPoint(x: (c.x + foldPoint.x) / 2, y: (c.y + foldPoint.y) / 2)
        let len = dist(c, foldPoint)
        normal = CGPoint(x: (c.x - foldPoint.x) / len, y: (c.y - foldPoint.y) / len)
        exposed = clip(rect, keepCornerSide: true)
        let rest = clip(rect, keepCornerSide: false)
        let line = exposed.filter { abs(dot($0)) < 0.5 }

        rugMask.path = path(rest, offset: r.origin)
        rug.mask = rugMask
        floorMask.path = path(exposed)
        floorLayer.isHidden = false
        flapMask.path = path(exposed)
        let d = mid.x * normal.x + mid.y * normal.y
        flap.setAffineTransform(CGAffineTransform(a: 1 - 2 * normal.x * normal.x, b: -2 * normal.x * normal.y,
                                                  c: -2 * normal.x * normal.y, d: 1 - 2 * normal.y * normal.y,
                                                  tx: 2 * d * normal.x, ty: 2 * d * normal.y))
        flap.isHidden = false
        flapShadow.shadowPath = path(exposed.map(reflect))
        flapShadow.isHidden = false
        if line.count >= 2 {
            let l = CGMutablePath()
            l.move(to: line[0]); l.addLine(to: line[line.count - 1])
            crease.path = l
            shade.path = l
            crease.isHidden = false
        }
    }

    private func animateFold(to target: CGPoint, closing: Bool) {
        foldTimer?.invalidate()
        let start = foldPoint, began = CACurrentMediaTime(), duration = 0.22
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let k = min(1, (CACurrentMediaTime() - began) / duration)
            let e = CGFloat(1 - pow(1 - k, 3))
            self.foldPoint = CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
            self.applyFold()
            self.layoutItems()
            if k >= 1 {
                timer.invalidate()
                if closing {
                    self.corner = nil
                    self.hinting = false
                    self.applyFold()
                    self.layoutItems()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        foldTimer = t
    }

    func closeFold() {
        guard let c = corner else { return }
        animateFold(to: c, closing: true)
    }

    private func openFold(near p: CGPoint, amount: CGFloat, hint: Bool) {
        let c = corner ?? nearestCorner(p)
        if corner == nil { foldPoint = c }
        corner = c
        hinting = hint
        animateFold(to: inward(c, by: amount), closing: false)
    }

    // MARK: - Halı altındaki simgeler

    private func layoutItems() {
        guard corner != nil, !exposed.isEmpty, !hinting else {
            if !cells.isEmpty || layoutKey != "" { clearItems() }
            return
        }
        let c = corner!, r = rugRect
        let w: CGFloat = 70, h: CGFloat = 76
        let sx: CGFloat = c.x < r.midX ? 1 : -1, sy: CGFloat = c.y < r.midY ? 1 : -1
        var rects: [CGRect] = []
        for row in 0..<4 {
            for col in 0..<6 {
                let x = sx > 0 ? c.x + 12 + CGFloat(col) * w : c.x - 12 - w - CGFloat(col) * w
                let y = sy > 0 ? c.y + 8 + CGFloat(row) * h : c.y - 8 - h - CGFloat(row) * h
                let cell = CGRect(x: x, y: y, width: w, height: h)
                let pts = [CGPoint(x: cell.minX, y: cell.minY), CGPoint(x: cell.maxX, y: cell.minY),
                           CGPoint(x: cell.minX, y: cell.maxY), CGPoint(x: cell.maxX, y: cell.maxY)]
                if pts.allSatisfy({ dot($0) >= 4 }) { rects.append(cell) }
            }
        }
        rects.sort { dist(CGPoint(x: $0.midX, y: $0.midY), c) < dist(CGPoint(x: $1.midX, y: $1.midY), c) }
        let key = rects.map { "\(Int($0.minX)),\(Int($0.minY))" }.joined(separator: ";") + "|" + store.items.map(\.name).joined(separator: ";")
        guard key != layoutKey else { return }
        layoutKey = key

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        itemsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        cells = []
        let items = store.items
        if items.isEmpty {
            if let first = rects.first { itemsLayer.addSublayer(label("Buraya bırak", in: first, size: 11, centered: true)) }
            return
        }
        for (i, rect) in rects.enumerated() where i < items.count {
            if i == rects.count - 1, items.count > rects.count {
                cells.append((rect, nil))
                itemsLayer.addSublayer(label("+\(items.count - i)", in: rect, size: 20, centered: true))
                break
            }
            cells.append((rect, items[i]))
            let icon = CALayer()
            icon.contents = NSWorkspace.shared.icon(forFile: items[i].url.path)
            icon.contentsGravity = .resizeAspect
            icon.frame = CGRect(x: rect.midX - 22, y: rect.maxY - 47, width: 44, height: 44)
            itemsLayer.addSublayer(icon)
            itemsLayer.addSublayer(label(items[i].name, in: CGRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width - 4, height: 25), size: 10, centered: false))
        }
    }

    private func clearItems() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        itemsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
        cells = []
        layoutKey = ""
    }

    private func label(_ text: String, in rect: CGRect, size: CGFloat, centered: Bool) -> CATextLayer {
        let t = CATextLayer()
        t.string = text
        t.font = NSFont.systemFont(ofSize: size, weight: .medium)
        t.fontSize = size
        t.foregroundColor = NSColor(calibratedWhite: 0.93, alpha: 1).cgColor
        t.alignmentMode = .center
        t.isWrapped = !centered
        t.truncationMode = .middle
        t.contentsScale = 2
        t.frame = centered ? CGRect(x: rect.minX, y: rect.midY - size * 0.7, width: rect.width, height: size * 1.5) : rect
        return t
    }

    private func cell(at p: CGPoint) -> (rect: CGRect, item: RugItem?)? { cells.first { $0.rect.contains(p) } }

    private func inFlap(_ p: CGPoint) -> Bool {
        guard corner != nil, !exposed.isEmpty else { return false }
        return path(exposed.map(reflect)).contains(p)
    }

    private func inExposed(_ p: CGPoint) -> Bool { !exposed.isEmpty && path(exposed).contains(p) }

    // MARK: - Fare

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private func nearCorner(_ p: CGPoint) -> Bool { dist(p, nearestCorner(p)) < 62 }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if nearCorner(p) {
            NSCursor.pointingHand.set()
            if corner == nil || hinting, !isFolded {
                let c = nearestCorner(p)
                if corner != c || !hinting {
                    corner = c
                    foldPoint = c
                    openFold(near: p, amount: 30, hint: true)
                }
            }
        } else {
            NSCursor.openHand.set()
            if hinting { closeFold() }
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        if hinting { closeFold() }
    }

    private func mouseScreen(_ event: NSEvent) -> NSPoint { testMouse ?? NSEvent.mouseLocation }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        downEvent = event
        downPoint = p
        moved = false
        foldTimer?.invalidate()

        if isFolded, inExposed(p), let hit = cell(at: p) {
            guard let item = hit.item else { onOpenFolder(); return }
            if event.clickCount == 2 { NSWorkspace.shared.open(item.url); return }
            drag = .item(item)
            return
        }
        if isFolded, inFlap(p) {
            drag = .fold(wasOpen: true)
            return
        }
        if nearCorner(p), !isFolded {
            let c = nearestCorner(p)
            if corner != c { corner = c; foldPoint = c }
            hinting = false
            drag = .fold(wasOpen: false)
            return
        }
        NSCursor.closedHand.set()
        drag = .move(mouse: mouseScreen(event), origin: window?.frame.origin ?? .zero)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .none:
            break
        case let .move(mouse, origin):
            moved = true
            let now = mouseScreen(event)
            setWindowOrigin(NSPoint(x: origin.x + now.x - mouse.x, y: origin.y + now.y - mouse.y))
        case .fold:
            guard dist(p, downPoint) > 3 || moved else { return }
            moved = true
            let r = rugRect.insetBy(dx: 6, dy: 6)
            foldPoint = CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
            applyFold()
            layoutItems()
        case let .item(item):
            guard dist(p, downPoint) > 5, let down = downEvent else { return }
            drag = .none
            startDragging(item, event: down)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = .none }
        switch drag {
        case .move:
            NSCursor.openHand.set()
            if moved { onMoved() }
        case let .fold(wasOpen):
            guard let c = corner else { return }
            if !moved {
                if wasOpen { closeFold() } else { openFold(near: c, amount: 250, hint: false) }
            } else if dist(c, foldPoint) < minimumFold {
                closeFold()
            }
        default:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        if isFolded, inExposed(p), let item = cell(at: p)?.item {
            add(menu, "Aç", #selector(openItem(_:)), item.url)
            add(menu, "Masaüstüne Geri Çıkar", #selector(restoreItem(_:)), item.url)
        } else {
            add(menu, "Halının Altını Finder'da Aç", #selector(openStore), nil)
        }
        menu.addItem(.separator())
        for (title, value) in [("Küçük Halı", 0.7), ("Orta Halı", 1.0), ("Büyük Halı", 1.4)] {
            add(menu, title, #selector(pickSize(_:)), value)
        }
        menu.addItem(.separator())
        add(menu, "Halıyı Gizle", #selector(hideRug), nil)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ object: Any?) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = object
        menu.addItem(item)
    }

    @objc private func openItem(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func restoreItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let item = store.items.first(where: { $0.url == url }) else { return }
        try? store.restore(item, fallback: restoreFallback)
    }

    @objc private func openStore() { onOpenFolder() }
    @objc private func hideRug() { onHide() }
    @objc private func pickSize(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double { onSetScale(value) }
    }

    private func setWindowOrigin(_ origin: NSPoint) {
        guard let window, let screen = window.screen ?? NSScreen.screens.first else { return }
        let f = screen.frame, size = window.frame.size
        window.setFrameOrigin(NSPoint(x: min(max(origin.x, f.minX - Self.padding), f.maxX - size.width + Self.padding),
                                      y: min(max(origin.y, f.minY - Self.padding), f.maxY - size.height + Self.padding)))
    }

    // MARK: - Halının altından dışarı sürükleme

    private func startDragging(_ item: RugItem, event: NSEvent) {
        let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        dragItem.setDraggingFrame(NSRect(x: downPoint.x - 24, y: downPoint.y - 24, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.store.reload() }
    }

    // MARK: - Halının altına süpürme

    private func droppedURLs(_ info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as AnyObject? !== self, droppedURLs(sender).contains(where: store.canSweep) else { return [] }
        if !isFolded {
            autoFolded = true
            openFold(near: convert(sender.draggingLocation, from: nil), amount: 250, hint: false)
        }
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource as AnyObject? === self ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if autoFolded { autoFolded = false; closeFold() }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return false }
        acceptDrop(urls, at: convert(sender.draggingLocation, from: nil))
        return true
    }

    /// Dosyalar halının altına kayar ve halı hafifçe dalgalanır.
    func acceptDrop(_ urls: [URL], at p: CGPoint) {
        let target = corner.map { inward($0, by: 40) } ?? CGPoint(x: rugRect.midX, y: rugRect.midY)
        for (i, url) in urls.prefix(8).enumerated() {
            let ghost = CALayer()
            ghost.contents = NSWorkspace.shared.icon(forFile: url.path)
            ghost.contentsGravity = .resizeAspect
            ghost.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
            ghost.position = p
            ghost.opacity = 0
            root.addSublayer(ghost)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: CGPoint(x: p.x + CGFloat(i) * 8, y: p.y - CGFloat(i) * 6))
            move.toValue = NSValue(point: target)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1; scale.toValue = 0.3
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.7, 1]
            let g = CAAnimationGroup()
            g.animations = [move, scale, fade]
            g.duration = 0.45
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.05
            g.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ghost.add(g, forKey: "fx")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ghost.removeFromSuperlayer() }
        }
        store.sweep(urls) { [weak self] moved, failed in
            guard let self else { return }
            self.ripple()
            self.layoutKey = ""
            self.layoutItems()
            self.onSwept(moved, failed)
            if self.autoFolded {
                self.autoFolded = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.closeFold() }
            }
        }
    }

    private func ripple() {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1, 1.018, 0.994, 1.006, 1]
        a.duration = 0.5
        rug.add(a, forKey: "ripple")
    }

    // MARK: - Test yardımcıları

    func testPoint(cornerOffset d: CGPoint) -> CGPoint {
        CGPoint(x: rugRect.maxX + d.x, y: rugRect.maxY + d.y)
    }

    var testCellCount: Int { cells.count }
    var testShowsUnderside: Bool { (itemsLayer.sublayers?.count ?? 0) > 0 }
    var testFlapPoint: CGPoint { exposed.isEmpty ? .zero : reflect(corner ?? .zero) }

    func renderPNG(to url: URL, background: CGColor) {
        let w = Int(bounds.width * 2), h = Int(bounds.height * 2)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: 2, y: 2)
        root.render(in: ctx)
        guard let image = ctx.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: - Halı penceresi

final class RugController {
    let window: NSPanel
    let view: RugView
    private let persist: Bool
    private let d = UserDefaults.standard

    init(store: RugStore, restoreFallback: URL, persist: Bool, onMoved: @escaping () -> Void) {
        self.persist = persist
        view = RugView(store: store, restoreFallback: restoreFallback)
        window = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        // Masaüstü simgelerinin üstünde, robotun ve uygulama pencerelerinin altında durur.
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view

        let s = DesktopMap.screen.visibleFrame
        let saved = persist ? d.double(forKey: "rugScale") : 1
        let startScale = CGFloat(saved > 0 ? min(max(saved, RugView.scaleRange.lowerBound), RugView.scaleRange.upperBound) : 1)
        let size = RugView.sizeFor(scale: startScale)
        var origin = NSPoint(x: s.midX - size.width / 2, y: s.midY - size.height / 2)
        if persist, d.object(forKey: "rugX") != nil {
            origin = NSPoint(x: d.double(forKey: "rugX"), y: d.double(forKey: "rugY"))
        }
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        view.relayout()
        view.onMoved = { [weak self] in
            self?.savePosition()
            onMoved()
        }
        view.onOpenFolder = { NSWorkspace.shared.open(store.dir) }
        if !persist || d.object(forKey: "rugVisible") == nil || d.bool(forKey: "rugVisible") { window.orderFrontRegardless() }
    }

    var isVisible: Bool { window.isVisible }

    /// Halıyı ortası sabit kalacak şekilde büyütür ya da küçültür.
    func setScale(_ value: Double) {
        let s = CGFloat(min(max(value, RugView.scaleRange.lowerBound), RugView.scaleRange.upperBound))
        let size = RugView.sizeFor(scale: s)
        let old = window.frame, f = DesktopMap.screen.frame, pad = RugView.padding
        let origin = NSPoint(x: min(max(old.midX - size.width / 2, f.minX - pad), f.maxX - size.width + pad),
                             y: min(max(old.midY - size.height / 2, f.minY - pad), f.maxY - size.height + pad))
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        view.relayout()
        if persist {
            d.set(Double(s), forKey: "rugScale")
            savePosition()
        }
    }

    func setVisible(_ visible: Bool) {
        if visible { window.orderFrontRegardless() } else { view.closeFold(); window.orderOut(nil) }
        if persist { d.set(visible, forKey: "rugVisible") }
    }

    private func savePosition() {
        guard persist else { return }
        d.set(window.frame.origin.x, forKey: "rugX")
        d.set(window.frame.origin.y, forKey: "rugY")
    }

    /// Halının ekranın sol altına göre konumu. Gizliyse hiçbir şeyi örtmez.
    var frameLocal: CGRect? {
        guard window.isVisible else { return nil }
        let s = DesktopMap.screen.frame
        return window.frame.insetBy(dx: RugView.padding, dy: RugView.padding).offsetBy(dx: -s.minX, dy: -s.minY)
    }
}
