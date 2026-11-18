import AppKit
import Metal
import QuartzCore

// MARK: - Metal çizimi

final class SnowRenderer {
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { packed_float2 pos; packed_float2 uv; packed_float4 color; float soft; };
    struct O { float4 p [[position]]; float2 uv; float4 color; float soft; };
    vertex O snowVertex(device const V* v [[buffer(0)]], uint i [[vertex_id]], constant float2& size [[buffer(1)]]) {
        O o;
        float2 p = float2(v[i].pos);
        o.p = float4(p.x / size.x * 2.0 - 1.0, 1.0 - p.y / size.y * 2.0, 0.0, 1.0);
        o.uv = float2(v[i].uv);
        o.color = float4(v[i].color);
        o.soft = v[i].soft;
        return o;
    }
    fragment float4 snowFragment(O in [[stage_in]]) {
        if (in.soft < 0.0) return in.color;
        float d = length(in.uv - 0.5) * 2.0;
        return in.color * (1.0 - smoothstep(in.soft, 1.0, d));
    }
    """

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var buffers: [MTLBuffer] = []
    private var index = 0
    private let inFlight = DispatchSemaphore(value: 3)
    private let capacity = 180_000

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "snowVertex")
        d.fragmentFunction = library.makeFunction(name: "snowFragment")
        let a = d.colorAttachments[0]!
        a.pixelFormat = .bgra8Unorm
        a.isBlendingEnabled = true
        a.sourceRGBBlendFactor = .one
        a.destinationRGBBlendFactor = .oneMinusSourceAlpha
        a.sourceAlphaBlendFactor = .one
        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        for _ in 0..<3 {
            guard let b = device.makeBuffer(length: capacity * 36, options: .storageModeShared) else { return nil }
            buffers.append(b)
        }
    }

    func draw(_ engine: SnowEngine, to texture: MTLTexture, drawable: MTLDrawable?, wait: Bool = false) {
        inFlight.wait()
        index = (index + 1) % buffers.count
        let buffer = buffers[index]
        let count = engine.buildVertices(into: buffer.contents().assumingMemoryBound(to: Float.self), capacity: capacity)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        if count > 0 {
            var size = SIMD2<Float>(engine.width, engine.height)
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()
        if let drawable { cmd.present(drawable) }
        let sem = inFlight
        cmd.addCompletedHandler { _ in sem.signal() }
        cmd.commit()
        if wait { cmd.waitUntilCompleted() }
    }
}

// MARK: - Ekrandaki kar

final class SnowController {
    private let window: NSWindow
    private let metal = CAMetalLayer()
    private let renderer: SnowRenderer?
    private var engine: SnowEngine
    private var link: CVDisplayLink?

    private let lock = NSLock()
    private var pending: [SnowWindow]?
    private var pendingDt: Float = 0.1
    private var spaceChanged = false
    private var targetIntensity: Float = 0.5
    private var targetLimit: Float = 1
    private var targetPlow = true
    private var wantsSnow = false
    private var rebuild = false

    private var lastFrame = CACurrentMediaTime()
    private var lastPoll = 0.0
    private var polling = false
    private var skip = false
    private let pollQueue = DispatchQueue(label: "robo.snow.windows", qos: .userInteractive)
    private var observers: [NSObjectProtocol] = []

    init() {
        let s = DesktopMap.screen
        renderer = SnowRenderer()
        engine = SnowEngine(width: s.frame.width, height: s.frame.height)
        window = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: s)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // Normal pencerelerin üstünde, Dock ve menü çubuğunun altında.
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.dockWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: NSRect(origin: .zero, size: s.frame.size))
        metal.device = renderer?.device
        metal.pixelFormat = .bgra8Unorm
        metal.isOpaque = false
        metal.framebufferOnly = true
        metal.maximumDrawableCount = 3
        metal.frame = view.bounds
        metal.contentsScale = s.backingScaleFactor
        metal.drawableSize = CGSize(width: s.frame.width * s.backingScaleFactor, height: s.frame.height * s.backingScaleFactor)
        view.layer = metal
        view.wantsLayer = true
        window.contentView = view
        updateMinimumTop()

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.spaceChanged = true; self.lock.unlock()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenChanged()
        })
    }

    private func updateMinimumTop() {
        let s = DesktopMap.screen
        engine.minimumTop = Float(s.frame.maxY - s.visibleFrame.maxY) - 1
    }

    private func screenChanged() {
        let s = DesktopMap.screen
        window.setFrame(s.frame, display: false)
        metal.frame = CGRect(origin: .zero, size: s.frame.size)
        metal.contentsScale = s.backingScaleFactor
        metal.drawableSize = CGSize(width: s.frame.width * s.backingScaleFactor, height: s.frame.height * s.backingScaleFactor)
        lock.lock(); rebuild = true; lock.unlock()
    }

    // MARK: - Ayarlar

    func setIntensity(_ value: Double) { lock.lock(); targetIntensity = Float(value); lock.unlock() }
    func setLimit(_ value: Double) { lock.lock(); targetLimit = Float(value); lock.unlock() }
    func setPlowEnabled(_ on: Bool) { lock.lock(); targetPlow = on; lock.unlock() }

    func setEnabled(_ on: Bool) {
        lock.lock(); wantsSnow = on; lock.unlock()
        guard on, renderer != nil else { return }
        window.orderFrontRegardless()
        startLink()
    }

    private func startLink() {
        guard link == nil else { return }
        var created: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&created)
        guard let created else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(created, { _, _, _, _, _, context in
            Unmanaged<SnowController>.fromOpaque(context!).takeUnretainedValue().frame()
            return kCVReturnSuccess
        }, me)
        lastFrame = CACurrentMediaTime()
        link = created
        CVDisplayLinkStart(created)
    }

    // MARK: - Kare döngüsü (görüntü iş parçacığında)

    private func frame() {
        autoreleasepool {
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                skip.toggle()
                if skip { return }
            }
            let now = CACurrentMediaTime()
            let dt = Float(min(now - lastFrame, 0.05))
            lastFrame = now

            lock.lock()
            let windows = pending, pollDt = pendingDt, space = spaceChanged, wants = wantsSnow
            let intensity = targetIntensity, limit = targetLimit, needsRebuild = rebuild, plowOn = targetPlow
            pending = nil; spaceChanged = false; rebuild = false
            lock.unlock()

            if needsRebuild {
                let s = DesktopMap.screen.frame
                engine = SnowEngine(width: s.width, height: s.height)
                DispatchQueue.main.async { [weak self] in self?.updateMinimumTop() }
            }
            engine.intensity = intensity
            engine.limit = limit
            engine.plowEnabled = plowOn
            engine.setMelting(!wants)
            if space { engine.noteSpaceChange() }
            if let windows { engine.apply(windows: windows, dt: pollDt) }
            engine.step(dt)
            schedulePoll(now)

            if engine.isFinished, !wants {
                finish()
                return
            }
            guard let renderer, let drawable = metal.nextDrawable() else { return }
            renderer.draw(engine, to: drawable.texture, drawable: drawable)
        }
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let wants = self.wantsSnow; self.lock.unlock()
            guard !wants, let link = self.link else { return }
            CVDisplayLinkStop(link)
            self.link = nil
            self.window.orderOut(nil)
        }
    }

    /// Pencere hareket ederken sık, dururken seyrek bakılır.
    private func schedulePoll(_ now: Double) {
        let interval = engine.isMoving ? 1.0 / 60 : 1.0 / 8
        guard !polling, now - lastPoll >= interval else { return }
        let dt = Float(now - lastPoll)
        lastPoll = now
        polling = true
        pollQueue.async { [weak self] in
            let list = SnowController.visibleWindows()
            guard let self else { return }
            self.lock.lock()
            self.pending = list
            self.pendingDt = dt
            self.lock.unlock()
            self.polling = false
        }
    }

    static func visibleWindows() -> [SnowWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,
                  let id = w[kCGWindowNumber as String] as? UInt32,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width >= 100, rect.height >= 50 else { return nil }
            return SnowWindow(id: id, frame: rect)
        }
    }
}
