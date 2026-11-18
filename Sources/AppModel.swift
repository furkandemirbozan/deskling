import AppKit
import Combine
import ServiceManagement

enum CleanMode: String, CaseIterable, Identifiable {
    case approval, automatic
    var id: String { rawValue }
    var title: String { self == .approval ? "Onayımla" : "Otomatik" }
}

final class AppModel: ObservableObject {
    // Durum
    @Published var shots: [Shot] = []
    @Published var selected: Set<String> = []
    @Published var protected: Set<String> = []
    @Published var history: [CleanRecord] = []
    @Published var thumbs: [String: NSImage] = [:]
    @Published var statusTitle = "İstasyonda"
    @Published var statusDetail = "Hazır"
    @Published var battery = 100
    @Published var busy = false
    @Published var paused = false
    @Published var message: String?

    // Ayarlar
    @Published var mode: CleanMode { didSet { d.set(mode.rawValue, forKey: "mode"); evaluateAuto() } }
    @Published var speed: Double { didSet { d.set(speed, forKey: "speed"); engine.maxSpeed = speed } }
    @Published var capacity: Int { didSet { d.set(capacity, forKey: "capacity"); engine.capacity = capacity } }
    @Published var minAge: Int { didSet { d.set(minAge, forKey: "minAge") } }
    @Published var sounds: Bool { didSet { d.set(sounds, forKey: "sounds") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); applyLoginItem() } }

    let engine: RobotEngine
    var overlay: OverlayController?
    let desktop: URL
    let usesRealDesktop: Bool

    private let d = UserDefaults.standard
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var watcher: DispatchSourceFileSystemObject?
    private var rescan: DispatchWorkItem?
    private var autoTimer: Timer?
    private var picked = 0
    private var failed = 0
    private var demoRunning = false
    private var launching = false
    private var autoSkip: Set<String> = []
    var silent = false
    var onDemoFinished: (() -> Void)?
    var onMissionFinished: (() -> Void)?
    var onNeedsPanel: (() -> Void)?
    private let scanQueue = DispatchQueue(label: "robo.scan", qos: .utility)

    private var carried: [CGImage] = []

    // Halı
    let rugStore: RugStore
    var rugFrameLocal: () -> CGRect? = { nil }
    var positionProvider: ([String], Bool, @escaping ([String: CGPoint]) -> Void) -> Void = { names, ask, done in
        DesktopMap.positions(names: names, askFinder: ask, completion: done)
    }
    @Published var rugCovered: Set<String> = []
    @Published var rugVisible: Bool { didSet { rugControl?.setVisible(rugVisible); rugMoved() } }
    @Published var rugScale: Double {
        didSet {
            rugControl?.setScale(rugScale)
            rugCoverWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.rugMoved() }
            rugCoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }
    private weak var rugControl: RugController?

    // Kar
    @Published var snowEnabled: Bool { didSet { d.set(snowEnabled, forKey: "snowEnabled"); snow?.setEnabled(snowEnabled) } }
    @Published var snowIntensity: Double { didSet { d.set(snowIntensity, forKey: "snowIntensity"); snow?.setIntensity(snowIntensity) } }
    @Published var snowLimit: Double { didSet { d.set(snowLimit, forKey: "snowLimit"); snow?.setLimit(snowLimit) } }
    @Published var snowPlowEnabled: Bool { didSet { d.set(snowPlowEnabled, forKey: "snowPlowEnabled"); snow?.setPlowEnabled(snowPlowEnabled) } }
    private var snow: SnowController?

    func connectSnow(_ controller: SnowController) {
        snow = controller
        controller.setIntensity(snowIntensity)
        controller.setLimit(snowLimit)
        controller.setPlowEnabled(snowPlowEnabled)
        controller.setEnabled(snowEnabled)
    }
    private var rugCoverWork: DispatchWorkItem?

    /// Panel, menü ve halının sağ tık menüsü aynı ayarları kullanır.
    func connectRug(_ rug: RugController) {
        rugControl = rug
        rugFrameLocal = { [weak rug] in rug?.frameLocal }
        rug.view.onSetScale = { [weak self] in self?.rugScale = $0 }
        rug.view.onHide = { [weak self] in self?.rugVisible = false }
    }

    /// Halının örtmediği, robotun görebildiği ekran görüntüleri.
    var visibleShots: [Shot] { shots.filter { !rugCovered.contains($0.id) } }

    /// Robotun topladığı ekran görüntülerinin durduğu klasör.
    var collectionDir: URL {
        if !usesRealDesktop { return desktop.appendingPathComponent(".hazne", isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoboSupurge/Toz Haznesi", isDirectory: true)
    }

    lazy var openCollection: () -> Void = { [weak self] in
        guard let self else { return }
        try? FileManager.default.createDirectory(at: self.collectionDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(self.collectionDir)
    }

    private var historyURL: URL {
        if !usesRealDesktop { return desktop.appendingPathComponent(".gecmis.json") }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoboSupurge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gecmis.json")
    }

    init(desktopOverride: URL? = nil) {
        desktop = desktopOverride ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        usesRealDesktop = desktopOverride == nil
        rugStore = RugStore(dir: desktopOverride?.appendingPathComponent(".hali/Hali Alti", isDirectory: true)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RoboSupurge/Halı Altı", isDirectory: true))
        d.register(defaults: ["mode": "automatic", "speed": 240.0, "capacity": 3, "minAge": 60, "sounds": true,
                              "launchAtLogin": true, "rugVisible": true, "rugScale": 1.0,
                              "snowEnabled": true, "snowIntensity": 0.5, "snowLimit": 1.0, "snowPlowEnabled": true])
        // Önceki sürümden gelenler de 1 saat kuralına geçsin.
        if !d.bool(forKey: "autoHourV1") {
            d.set(CleanMode.automatic.rawValue, forKey: "mode")
            d.set(60, forKey: "minAge")
            d.set(true, forKey: "autoHourV1")
        }
        mode = CleanMode(rawValue: d.string(forKey: "mode") ?? "") ?? .approval
        speed = d.double(forKey: "speed")
        capacity = d.integer(forKey: "capacity")
        minAge = d.integer(forKey: "minAge")
        sounds = d.bool(forKey: "sounds")
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        rugVisible = d.bool(forKey: "rugVisible")
        rugScale = d.double(forKey: "rugScale")
        snowEnabled = d.bool(forKey: "snowEnabled")
        snowIntensity = d.double(forKey: "snowIntensity")
        snowLimit = d.double(forKey: "snowLimit")
        snowPlowEnabled = d.bool(forKey: "snowPlowEnabled")
        protected = Set(d.stringArray(forKey: "protected") ?? [])
        engine = RobotEngine(base: DesktopMap.basePoint(), trash: DesktopMap.stationApproach())
        engine.maxSpeed = speed
        engine.capacity = capacity
        if let data = try? Data(contentsOf: historyURL),
           let list = try? JSONDecoder().decode([CleanRecord].self, from: data) { history = list }
        wire()
    }

    /// Yalnızca Uygulamalar klasöründeki kopya açılış öğesi olur.
    private func applyLoginItem() {
        guard usesRealDesktop, Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        do {
            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Mac açılışında başlatma ayarlanamadı: \(error.localizedDescription)"
        }
    }

    func attach(_ o: OverlayController) {
        overlay = o
        applyLoginItem()
        o.hitView.onDoubleClick = { [weak self] in self?.cleanAllNow() }
        o.stationHitView.onClick = { [weak self] in self?.openCollection() }
        o.placeStation(base: engine.basePoint)
        o.sync(engine)
        o.show()
        startWatching()
        scan()
        autoTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.evaluateAuto() }
    }

    // MARK: - Motor bağlantıları

    private func wire() {
        engine.onPhaseChange = { [weak self] p in
            guard let self else { return }
            self.overlay?.phaseChanged(p, engine: self.engine)
            self.refreshStatus()
        }
        engine.onPickup = { [weak self] job in self?.pickup(job) ?? false }
        engine.onDump = { [weak self] n in
            guard let self else { return }
            self.overlay?.dump(images: self.carried, from: self.engine.pos, to: DesktopMap.stationCenter())
            self.carried.removeAll()
            self.play("Pop")
        }
        engine.onMissionEnd = { [weak self] in self?.missionEnded() }
    }

    private func pickup(_ job: Job) -> Bool {
        if job.id.hasPrefix("patrol-") { return false }   // tur noktası: alınacak bir şey yok
        guard let shot = job.shot else {   // demo kartı
            overlay?.suck(job)
            carried.append(job.thumb ?? RobotArt.demoCard(carried.count))
            play("Tink")
            picked += 1
            return true
        }
        do {
            let record = try Cleaner.collect(shot, into: collectionDir)
            history.insert(record, at: 0)
            saveHistory()
            shots.removeAll { $0.id == shot.id }
            selected.remove(shot.id)
            overlay?.suck(job)
            carried.append(job.thumb ?? RobotArt.demoCard(carried.count))
            play("Tink")
            picked += 1
            return true
        } catch {
            failed += 1
            autoSkip.insert(shot.id)   // otomatik mod aynı dosyayı tekrar tekrar denemesin
            message = "\(shot.name): \(error.localizedDescription)"
            return false
        }
    }

    private func missionEnded() {
        overlay?.clearDemoCards()
        if demoRunning {
            message = "Demo bitti. Hiçbir dosyaya dokunulmadı."
            onDemoFinished?()
        } else if picked > 0 {
            message = failed > 0 ? "\(picked) görüntü toz haznesine toplandı, \(failed) tanesi atlandı."
                                 : "\(picked) görüntü toz haznesine toplandı."
        }
        demoRunning = false
        picked = 0
        failed = 0
        refreshStatus()
        scan()
        onMissionFinished?()
    }

    private func refreshStatus() {
        busy = engine.isBusy
        paused = engine.paused
        battery = Int(engine.battery.rounded())
        let remaining = engine.jobs.count + (engine.current == nil ? 0 : 1)
        statusDetail = busy ? (remaining > 0 ? "\(remaining) görüntü kaldı" : "Görev tamamlanıyor") : "Hazır"
        if engine.paused { statusTitle = "Duraklatıldı"; return }
        if engine.isCharging { statusTitle = "Şarj oluyor"; return }
        switch engine.phase {
        case .docked: statusTitle = "İstasyonda"
        case .scanning: statusTitle = "Masaüstü taranıyor"
        case .turning, .driving:
            switch engine.leg {
            case .job: statusTitle = "Ekran görüntüsüne gidiyor"
            case .trash: statusTitle = "Toz haznesine gidiyor"
            case .base: statusTitle = "İstasyona dönüyor"
            }
        case .vacuuming: statusTitle = "Süpürüyor"
        case .dumping: statusTitle = "Hazneyi boşaltıyor"
        case .aligning, .backing: statusTitle = "İstasyona yanaşıyor"
        }
    }

    // MARK: - Döngü

    private func ensureRunning() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.frame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var statusAccumulator = 0.0

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        engine.tick(dt)
        overlay?.sync(engine)
        statusAccumulator += dt
        if statusAccumulator > 0.5 { statusAccumulator = 0; refreshStatus() }
        if engine.isIdle {
            timer?.invalidate()
            timer = nil
            refreshStatus()
            overlay?.phaseChanged(.docked, engine: engine)
        }
    }

    // MARK: - Komutlar

    /// Çift tıklama: sormadan, kilitli olmayan tüm ekran görüntülerini temizler.
    func cleanAllNow() {
        if engine.paused { togglePause(); return }
        guard !engine.isBusy, !launching else { return }
        overlay?.pulse(at: engine.pos)
        scan { [weak self] in
            guard let self else { return }
            let list = self.visibleShots.filter { !self.protected.contains($0.id) }
            if !list.isEmpty {
                self.launch(list, manual: true)
            } else if (try? FileManager.default.contentsOfDirectory(atPath: self.desktop.path)) == nil {
                self.message = "Masaüstü izni gerekli. Sistem Ayarları > Gizlilik ve Güvenlik > Dosyalar ve Klasörler bölümünden izin ver."
                self.onNeedsPanel?()
            } else {
                self.message = "Temizlenecek ekran görüntüsü yok."
                self.patrol()
            }
        }
    }

    /// Temizlenecek dosya yoksa robot masaüstünde bir tur atıp istasyona döner.
    private func patrol() {
        let size = DesktopMap.screen.frame.size
        let spots = [(0.28, 0.62), (0.55, 0.72), (0.72, 0.42), (0.42, 0.34)]
        engine.start(spots.enumerated().map { i, s in
            Job(id: "patrol-\(i)", point: CGPoint(x: size.width * s.0, y: size.height * s.1), shot: nil, thumb: nil)
        })
        ensureRunning()
        refreshStatus()
    }

    func cleanSelected() { launch(visibleShots.filter { selected.contains($0.id) && !protected.contains($0.id) }) }

    /// Halı taşındığında neyin örtüldüğünü yeniden hesaplar.
    func rugMoved() { updateRugCover() }

    private func updateRugCover() {
        guard let rect = rugFrameLocal(), !shots.isEmpty else { rugCovered = []; evaluateAuto(); return }
        let list = shots
        positionProvider(list.map(\.name), usesRealDesktop) { [weak self] map in
            guard let self else { return }
            self.rugCovered = Set(list.filter { map[$0.name].map(rect.contains) ?? false }.map(\.id))
            self.selected.subtract(self.rugCovered)
            self.evaluateAuto()
        }
    }

    private func launch(_ list: [Shot], manual: Bool = false) {
        guard !list.isEmpty, !engine.isBusy, !launching else { return }
        launching = true
        message = nil
        statusTitle = "Simgeler bulunuyor"
        busy = true
        positionProvider(list.map(\.name), usesRealDesktop) { [weak self] map in
            guard let self else { return }
            self.launching = false
            let rugRect = self.rugFrameLocal()
            let jobs = list.compactMap { s -> Job? in
                guard let p = map[s.name] else { return nil }
                if rugRect?.contains(p) == true {   // son anda halının altında kaldıysa dokunma
                    self.rugCovered.insert(s.id)
                    return nil
                }
                return Job(id: s.id, point: p, shot: s, thumb: ScreenshotDetector.thumbnail(s.url))
            }
            guard !jobs.isEmpty else {
                self.refreshStatus()
                if manual { self.patrol() }
                return
            }
            self.engine.start(jobs)
            self.ensureRunning()
            self.refreshStatus()
        }
    }

    func runDemo() {
        guard !engine.isBusy, !launching else { return }
        message = nil
        let size = DesktopMap.screen.frame.size
        let spots = [(0.72, 0.72), (0.5, 0.56), (0.3, 0.74), (0.62, 0.36)]
        let jobs = spots.enumerated().map { i, s in
            Job(id: "demo-\(i)", point: CGPoint(x: size.width * s.0, y: size.height * s.1), shot: nil, thumb: RobotArt.demoCard(i))
        }
        demoRunning = true
        overlay?.showDemoCards(jobs)
        engine.start(jobs)
        ensureRunning()
        refreshStatus()
    }

    func togglePause() { engine.togglePause(); refreshStatus() }
    func goHome() { engine.goHome(); overlay?.clearDemoCards(); ensureRunning(); refreshStatus() }

    func toggleProtect(_ s: Shot) {
        if protected.contains(s.id) { protected.remove(s.id) } else { protected.insert(s.id); selected.remove(s.id) }
        d.set(Array(protected), forKey: "protected")
    }

    func restore(_ r: CleanRecord) {
        do {
            let url = try Cleaner.restore(r)
            if let i = history.firstIndex(where: { $0.id == r.id }) { history[i].restored = true }
            saveHistory()
            // Geri alınan dosya otomatik modda hemen tekrar süpürülmesin.
            protected.insert(url.path)
            d.set(Array(protected), forKey: "protected")
            message = "\(url.lastPathComponent) masaüstüne geri kondu ve korumaya alındı."
            scan()
        } catch {
            message = "Geri alınamadı. Dosya artık yerinde değil."
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(Array(history.prefix(500))) { try? data.write(to: historyURL, options: .atomic) }
    }

    private func play(_ name: String) { if sounds, !silent { NSSound(named: name)?.play() } }

    // MARK: - Tarama

    func scan(then done: (() -> Void)? = nil) {
        let dir = desktop
        scanQueue.async { [weak self] in
            let found = ScreenshotDetector.scan(dir)
            let images = Dictionary(uniqueKeysWithValues: found.compactMap { s -> (String, NSImage)? in
                guard let c = ScreenshotDetector.thumbnail(s.url, maxPixels: 120) else { return nil }
                return (s.id, NSImage(cgImage: c, size: NSSize(width: c.width, height: c.height)))
            })
            DispatchQueue.main.async {
                guard let self else { return }
                let known = Set(self.shots.map(\.id))
                let ids = Set(found.map(\.id))
                self.selected = self.selected.intersection(ids)
                for s in found where !known.contains(s.id) && !self.protected.contains(s.id) { self.selected.insert(s.id) }
                self.shots = found
                self.thumbs = images
                self.updateRugCover()
                done?()
            }
        }
    }

    /// İzin penceresi yanıtlanana kadar robot donmasın diye klasör arka planda açılır.
    private func startWatching() {
        let path = desktop.path
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return }
            DispatchQueue.main.async { self?.watch(fd) }
        }
    }

    private func watch(_ fd: Int32) {
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.rescan?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.scan() }
            self.rescan = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    /// Otomatik modda yalnızca belirlenen süreden eski ve korunmayan görüntüler alınır.
    private func evaluateAuto() {
        guard mode == .automatic, !engine.isBusy, !launching, !demoRunning else { return }
        let cutoff = Date().addingTimeInterval(-Double(minAge) * 60)
        launch(visibleShots.filter { !protected.contains($0.id) && !autoSkip.contains($0.id) && $0.created <= cutoff })
    }
}
