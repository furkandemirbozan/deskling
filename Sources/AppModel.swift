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
    @Published var panelTab: PanelTab = .found

    /// Portlar sekmesi: dinlenen portlar ve Docker konteynerleri.
    let dev = DevCenter()

    // Pano
    let clipboard: ClipboardStore
    @Published var clipEnabled: Bool { didSet { d.set(clipEnabled, forKey: "clipEnabled"); clipboard.enabled = clipEnabled; onShortcutChange?(clipShortcut) } }
    @Published var clipLimit: Int { didSet { d.set(clipLimit, forKey: "clipLimit"); clipboard.limit = clipLimit } }
    @Published var clipShortcut: ClipShortcut { didSet { clipShortcut.save(d); onShortcutChange?(clipShortcut) } }
    @Published var clipShortcutWorks = true
    var onShortcutChange: ((ClipShortcut?) -> Void)?
    var onShortcutRecording: ((Bool) -> Void)?

    // Ayarlar
    @Published var mode: CleanMode { didSet { d.set(mode.rawValue, forKey: "mode"); evaluateAuto() } }
    @Published var speed: Double { didSet { d.set(speed, forKey: "speed"); engine.maxSpeed = speed } }
    @Published var capacity: Int { didSet { d.set(capacity, forKey: "capacity"); engine.capacity = capacity } }
    @Published var minAge: Int { didSet { d.set(minAge, forKey: "minAge") } }
    @Published var sounds: Bool { didSet { d.set(sounds, forKey: "sounds") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); applyLoginItem() } }
    @Published var bumpIcons: Bool { didSet { d.set(bumpIcons, forKey: "bumpIcons") } }

    // Çarpma ve gezinti
    let iconField = IconField()
    private var planner = PatrolPlanner()
    private(set) var lastPatrol: PatrolRoute?
    /// Yalnızca gerçek masaüstünde Finder'a bağlanır; testler kendi sahte simgelerini verir.
    var iconReader: ((@escaping ([String: CGPoint]) -> Void) -> Void)?
    var iconSlider: ((IconSlide) -> Void)?

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
    @Published var snowEnabled: Bool { didSet { d.set(snowEnabled, forKey: "snowEnabled"); snow?.setEnabled(snowEnabled && !quietActive) } }
    @Published var snowIntensity: Double { didSet { d.set(snowIntensity, forKey: "snowIntensity"); snow?.setIntensity(snowIntensity) } }
    @Published var snowLimit: Double { didSet { d.set(snowLimit, forKey: "snowLimit"); snow?.setLimit(snowLimit) } }
    @Published var snowPlowEnabled: Bool { didSet { d.set(snowPlowEnabled, forKey: "snowPlowEnabled"); snow?.setPlowEnabled(snowPlowEnabled) } }
    // Kara delik
    @Published var holeEnabled: Bool { didSet { d.set(holeEnabled, forKey: "holeEnabled"); hole?.setVisible(holeEnabled) } }
    @Published var holeTrashOriginal: Bool { didSet { d.set(holeTrashOriginal, forKey: "holeTrashOriginal"); hole?.trashOriginal = holeTrashOriginal } }
    @Published var holeImageFormat: String { didSet { d.set(holeImageFormat, forKey: "holeImageFormat"); hole?.settings = holeSettings } }
    @Published var holeQuality: String { didSet { d.set(holeQuality, forKey: "holeQuality"); hole?.settings = holeSettings } }
    @Published var holeStripLocation: Bool { didSet { d.set(holeStripLocation, forKey: "holeStripLocation"); hole?.settings = holeSettings } }
    private weak var hole: BlackHoleController?
    private(set) var quietActive = false
    private var robotPausedByFocus = false
    var pomoFocusStarted: Date?
    /// Son molada toplanmak üzere seçilen görüntüler (testler için).
    private(set) var lastBreakCleanup: [String]?

    // Pomodoro (mantığı Sources/Pomodoro/PomodoroModel.swift içinde)
    let pomo: PomodoroManager
    var pomoAlerts: PomodoroAlerts
    var pomoListeners: [() -> Void] = []
    var pomoTransitionListeners: [(PomoTransition) -> Void] = []
    @Published var pomoEnabled: Bool {
        didSet { d.set(pomoEnabled, forKey: "pomoEnabled"); if !pomoEnabled { pomo.reset() }; pomoChanged() }
    }
    @Published var pomoShowDrink: Bool { didSet { d.set(pomoShowDrink, forKey: "pomoShowDrink"); pomoChanged() } }
    @Published var pomoDrink: DrinkKind { didSet { d.set(pomoDrink.rawValue, forKey: "pomoDrink"); pomoChanged() } }
    @Published var pomoFocus: Int { didSet { d.set(pomoFocus, forKey: "pomoFocus"); pomo.durations = pomoDurations; pomoChanged() } }
    @Published var pomoShort: Int { didSet { d.set(pomoShort, forKey: "pomoShort"); pomo.durations = pomoDurations; pomoChanged() } }
    @Published var pomoLong: Int { didSet { d.set(pomoLong, forKey: "pomoLong"); pomo.durations = pomoDurations; pomoChanged() } }
    @Published var pomoCycle: Int { didSet { d.set(pomoCycle, forKey: "pomoCycle"); pomo.durations = pomoDurations; pomoChanged() } }
    @Published var pomoScale: Double { didSet { d.set(pomoScale, forKey: "pomoScale"); pomoChanged() } }
    @Published var pomoMenuTimer: Bool { didSet { d.set(pomoMenuTimer, forKey: "pomoMenuTimer"); pomoChanged() } }
    @Published var pomoEffects: DrinkEffects { didSet { d.set(pomoEffects.rawValue, forKey: "pomoEffects"); pomoChanged() } }
    @Published var pomoSound: Bool { didSet { d.set(pomoSound, forKey: "pomoSound") } }
    @Published var pomoNotify: Bool { didSet { d.set(pomoNotify, forKey: "pomoNotify") } }
    @Published var pomoKeepAwake: Bool { didSet { d.set(pomoKeepAwake, forKey: "pomoKeepAwake"); updateAwake() } }
    @Published var pomoQuietFocus: Bool { didSet { d.set(pomoQuietFocus, forKey: "pomoQuietFocus"); applyQuiet() } }
    @Published var pomoCleanOnBreak: Bool { didSet { d.set(pomoCleanOnBreak, forKey: "pomoCleanOnBreak") } }

    var holeSettings: HoleSettings {
        HoleSettings(format: HoleSettings.Format(rawValue: holeImageFormat) ?? .jpg,
                     quality: HoleSettings.Quality(rawValue: holeQuality) ?? .medium,
                     stripLocation: holeStripLocation)
    }

    func connectHole(_ h: BlackHoleController) {
        hole = h
        h.trashOriginal = holeTrashOriginal
        h.settings = holeSettings
        h.onSettingsChange = { [weak self] s in
            self?.holeImageFormat = s.format.rawValue
            self?.holeQuality = s.quality.rawValue
            self?.holeStripLocation = s.stripLocation
        }
        h.onTrashOriginalChange = { [weak self] in self?.holeTrashOriginal = $0 }
        h.onHide = { [weak self] in self?.holeEnabled = false }
        h.onFinished = { [weak self] r in if r.ok { self?.play(r.consumed ? "Submarine" : "Funk") } else { self?.play("Basso") } }
        h.setVisible(holeEnabled)
    }

    @Published var snowSculpt: Bool { didSet { d.set(snowSculpt, forKey: "snowSculpt"); snow?.setSculptEnabled(snowSculpt) } }
    private var snow: SnowController?

    func connectSnow(_ controller: SnowController) {
        snow = controller
        controller.setSculptEnabled(snowSculpt)
        controller.setIntensity(snowIntensity)
        controller.setLimit(snowLimit)
        controller.setPlowEnabled(snowPlowEnabled)
        controller.setEnabled(snowEnabled && !quietActive)
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
            .appendingPathComponent("\(AppInfo.name)/Toz Haznesi", isDirectory: true)
    }

    lazy var openCollection: () -> Void = { [weak self] in
        guard let self else { return }
        try? FileManager.default.createDirectory(at: self.collectionDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(self.collectionDir)
    }

    private var historyURL: URL {
        if !usesRealDesktop { return desktop.appendingPathComponent(".gecmis.json") }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gecmis.json")
    }

    init(desktopOverride: URL? = nil) {
        desktop = desktopOverride ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        usesRealDesktop = desktopOverride == nil
        // Testler gerçek panoya ve gerçek geçmiş dosyasına dokunmaz.
        clipboard = desktopOverride == nil
            ? ClipboardStore(fileURL: ClipboardStore.defaultFile)
            : ClipboardStore(pasteboard: NSPasteboard(name: NSPasteboard.Name("robo-test-\(UUID().uuidString)")), fileURL: nil)
        rugStore = RugStore(dir: desktopOverride?.appendingPathComponent(".hali/Hali Alti", isDirectory: true)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("\(AppInfo.name)/Halı Altı", isDirectory: true))
        d.register(defaults: ["mode": "automatic", "speed": 240.0, "capacity": 3, "minAge": 60, "sounds": true,
                              "launchAtLogin": true, "bumpIcons": true, "rugVisible": true, "rugScale": 1.0,
                              "snowEnabled": true, "snowIntensity": 0.5, "snowLimit": 1.0, "snowPlowEnabled": true, "snowSculpt": true, "holeEnabled": true, "holeTrashOriginal": false,
                              "holeImageFormat": "jpg", "holeQuality": "medium", "holeStripLocation": true,
                              "clipEnabled": true, "clipLimit": 200])
        d.register(defaults: PomoLimits.defaults)
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
        bumpIcons = d.bool(forKey: "bumpIcons")
        rugVisible = d.bool(forKey: "rugVisible")
        rugScale = d.double(forKey: "rugScale")
        snowEnabled = d.bool(forKey: "snowEnabled")
        snowIntensity = d.double(forKey: "snowIntensity")
        snowLimit = d.double(forKey: "snowLimit")
        snowPlowEnabled = d.bool(forKey: "snowPlowEnabled")
        snowSculpt = d.bool(forKey: "snowSculpt")
        clipEnabled = d.bool(forKey: "clipEnabled")
        clipLimit = d.integer(forKey: "clipLimit")
        clipShortcut = ClipShortcut.load(d)
        holeEnabled = d.bool(forKey: "holeEnabled")
        holeTrashOriginal = d.bool(forKey: "holeTrashOriginal")
        holeImageFormat = d.string(forKey: "holeImageFormat") ?? "jpg"
        holeQuality = d.string(forKey: "holeQuality") ?? "medium"
        holeStripLocation = d.bool(forKey: "holeStripLocation")
        let ps = Self.loadPomoSettings(d)
        pomoEnabled = ps.enabled
        pomoShowDrink = ps.showDrink
        pomoDrink = ps.drink
        pomoFocus = ps.focus
        pomoShort = ps.shortBreak
        pomoLong = ps.longBreak
        pomoCycle = ps.cycle
        pomoScale = ps.scale
        pomoMenuTimer = ps.menuTimer
        pomoEffects = ps.effects
        pomoSound = ps.sound
        pomoNotify = ps.notify
        pomoKeepAwake = ps.keepAwake
        pomoQuietFocus = ps.quietFocus
        pomoCleanOnBreak = ps.cleanOnBreak
        // Testler gerçek sayaç kaydına, bildirimlere ve güç yönetimine dokunmaz.
        pomo = PomodoroManager(durations: PomoDurations(focus: TimeInterval(ps.focus * 60), shortBreak: TimeInterval(ps.shortBreak * 60),
                                                        longBreak: TimeInterval(ps.longBreak * 60), cycle: ps.cycle),
                               defaults: desktopOverride == nil ? d : nil)
        pomoAlerts = desktopOverride == nil ? .system()
            : PomodoroAlerts(notify: { _, _ in }, playSound: { _ in }, keepAwake: FakeKeepAwake())
        protected = Set(d.stringArray(forKey: "protected") ?? [])
        engine = RobotEngine(base: DesktopMap.basePoint(), trash: DesktopMap.stationApproach())
        engine.maxSpeed = speed
        engine.capacity = capacity
        if let data = try? Data(contentsOf: historyURL),
           let list = try? JSONDecoder().decode([CleanRecord].self, from: data) { history = list }
        if usesRealDesktop {
            iconReader = { FinderIcons.read(completion: $0) }
            iconSlider = { FinderIcons.slide($0) }
        }
        wire()
        connectPomodoro()
    }

    // MARK: - Simgelere çarpma

    /// Görev başında simgelerin yerini öğrenir; robot bu sırada yola çıkmış olabilir.
    private func prepareIcons(skipping names: Set<String>) {
        iconField.clear()
        guard bumpIcons, !demoRunning, let iconReader else { return }
        let s = DesktopMap.screen
        let v = s.visibleFrame.offsetBy(dx: -s.frame.minX, dy: -s.frame.minY)
        iconField.bounds = CGRect(x: v.minX + 56, y: v.minY + 56, width: v.width - 112, height: v.height - 106)
        iconField.ignored = names
        iconReader { [weak self] map in
            guard let self, self.engine.isBusy else { return }
            self.iconField.load(map)
        }
    }

    private func knockIcons() {
        guard bumpIcons, !demoRunning, engine.phase == .driving, !iconField.isEmpty else { return }
        let b = engine.basePoint
        var blocked = [CGRect(x: b.x - 130, y: b.y - 90, width: 280, height: 190)]
        if let rug = rugFrameLocal() { blocked.append(rug) }
        let slides = iconField.hit(robot: engine.pos, heading: engine.heading, speed: engine.speed,
                                   now: CACurrentMediaTime(), blocked: blocked)
        for s in slides {
            let angle = atan2(s.to.y - s.from.y, s.to.x - s.from.x)
            let contact = CGPoint(x: (engine.pos.x + s.from.x) / 2, y: (engine.pos.y + s.from.y) / 2)
            iconSlider?(s)
            overlay?.impact(at: contact, angle: angle)
            engine.bumped()
        }
        if !slides.isEmpty { play("Morse") }
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
            overlay?.suck(job, robot: engine.pos, heading: engine.heading)
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
            iconField.remove(shot.name)
            overlay?.suck(job, robot: engine.pos, heading: engine.heading)
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
        iconField.clear()
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
        let roaming = engine.current?.waypoint == true
        statusDetail = roaming ? "Temizlenecek bir şey yok" : busy ? (remaining > 0 ? "\(remaining) görüntü kaldı" : "Görev tamamlanıyor") : "Hazır"
        if engine.paused { statusTitle = "Duraklatıldı"; return }
        if engine.isCharging { statusTitle = "Şarj oluyor"; return }
        if roaming { statusTitle = "Masaüstünde geziyor"; return }
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
        knockIcons()
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

    /// Temizlenecek dosya yoksa robot her seferinde farklı bir rotayla gezip istasyona döner.
    private func patrol() {
        let s = DesktopMap.screen
        let v = s.visibleFrame.offsetBy(dx: -s.frame.minX, dy: -s.frame.minY)
        let route = planner.next(in: CGRect(x: v.minX + 120, y: v.minY + 120, width: v.width - 240, height: v.height - 230))
        lastPatrol = route
        prepareIcons(skipping: [])
        engine.start(route.points.enumerated().map { i, p in
            Job(id: "patrol-\(i)", point: p, shot: nil, thumb: nil, waypoint: true)
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
            self.prepareIcons(skipping: Set(jobs.compactMap { $0.shot?.name }))
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
        guard mode == .automatic, !engine.isBusy, !launching, !demoRunning, !quietActive else { return }
        let cutoff = Date().addingTimeInterval(-Double(minAge) * 60)
        launch(visibleShots.filter { !protected.contains($0.id) && !autoSkip.contains($0.id) && $0.created <= cutoff })
    }

    // MARK: - Pomodoro ile senkron

    /// Odak çalışırken (ayar açıksa) kar yağışı durur, robotun görevi duraklar ve otomatik toplama bekler.
    /// Ayarların kendisi değişmez; odak bitince her şey eski haline döner.
    func applyQuiet() {
        let want = pomoEnabled && pomoQuietFocus && pomo.phase == .focus && pomo.running
        guard want != quietActive else { return }
        quietActive = want
        snow?.setEnabled(snowEnabled && !want)
        if want {
            if engine.isBusy, !engine.paused {
                engine.togglePause()
                robotPausedByFocus = true
                refreshStatus()
            }
        } else {
            if robotPausedByFocus, engine.paused {
                engine.togglePause()
                refreshStatus()
            }
            robotPausedByFocus = false
            evaluateAuto()
        }
    }

    /// Mola başlayınca robot, odak sırasında masaüstüne düşen ekran görüntülerini toplar.
    /// Kilitli ve halının altındaki dosyalar her zamanki gibi dışarıda kalır.
    func cleanAfterFocus() {
        guard let start = pomoFocusStarted else { return }
        let since = start.addingTimeInterval(-5)
        scan { [weak self] in
            guard let self else { return }
            let list = self.visibleShots.filter { !self.protected.contains($0.id) && $0.created >= since }
            self.lastBreakCleanup = list.map(\.name).sorted()
            guard !list.isEmpty else { return }
            if self.engine.isBusy || self.launching {
                // Robot zaten çalışıyorsa görev bitince otomatik mod devralır.
                return
            }
            self.launch(list, manual: false)
        }
    }
}
