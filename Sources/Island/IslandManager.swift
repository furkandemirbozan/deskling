import AppKit
import Combine
import UniformTypeIdentifiers

/// Dinamik adanın durumu: hangi etkinlik görünür, ne zaman açılır, zamanlayıcılar ve geçici bildirimler.
/// Pencereden bağımsızdır; testler saati enjekte ederek doğrudan sürer.
final class IslandManager: ObservableObject {
    let settings: IslandSettings
    let media: NowPlaying
    let shelf: ShelfStore
    let pomo: PomodoroManager

    @Published var geometry: IslandGeometry = .sample
    @Published private(set) var expanded = false
    @Published var page: IslandPage = .home
    @Published private(set) var transient: IslandTransientKind?
    @Published private(set) var alert: IslandAlert?
    @Published private(set) var countdown: Countdown? { didSet { saveCountdown() } }
    @Published private(set) var stopwatch = Stopwatch()
    @Published private(set) var robot: RobotStatus?
    @Published var hiddenForFullscreen = false
    @Published var hasScreen = true
    @Published var dropTargeted = false
    @Published var power: PowerState?
    @Published var volume: Float = 0.5

    var pomoEnabled: () -> Bool = { false }
    var pomoDrink: () -> DrinkKind = { .tea }
    var now: () -> Date
    var playSound: (String) -> Void = { NSSound(named: $0)?.play() }
    var setSystemVolume: (Float) -> Void = { _ in }
    var onExpand: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Gerçek uygulamada süreler bir zamanlayıcıyla denetlenir; testler `tick()` çağırır.
    var autoTick: Bool

    private var transientUntil: Date?
    private var ticker: Timer?
    private let store: UserDefaults?
    private var bag: Set<AnyCancellable> = []
    static let countdownKey = "islandCountdown"

    init(settings: IslandSettings, pomo: PomodoroManager, store: UserDefaults?, media: NowPlaying = NowPlaying(),
         now: @escaping () -> Date = Date.init, autoTick: Bool = true) {
        self.settings = settings
        self.pomo = pomo
        self.store = store
        self.media = media
        self.now = now
        self.autoTick = autoTick
        shelf = ShelfStore(store: store)
        media.now = now
        if let data = store?.data(forKey: Self.countdownKey), let c = try? JSONDecoder().decode(Countdown.self, from: data) {
            if c.finished(now()) || c.remaining(now()) <= 0 { store?.removeObject(forKey: Self.countdownKey) } else { countdown = c }
        }
        media.onChange = { [weak self] in self?.objectWillChange.send() }
        settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        shelf.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        ensureTicker()
    }

    // MARK: - Ne görünür?

    /// Süren etkinlikler önem sırasıyla: zamanlayıcı, Pomodoro, müzik, kronometre, robot.
    var liveActivities: [LiveActivity] {
        var out: [LiveActivity] = []
        if countdown != nil { out.append(.timer) }
        if pomoEnabled(), pomo.phase != .idle { out.append(.pomodoro) }
        if media.track?.playing == true { out.append(.media) }
        if stopwatch.active { out.append(.stopwatch) }
        if robot != nil { out.append(.robot) }
        return out.filter { settings.isOn($0.feature) }
    }

    var display: IslandDisplay {
        guard settings.enabled, hasScreen, !hiddenForFullscreen else { return .hidden }
        if alert != nil { return .alert }
        if expanded { return .expanded }
        if let t = transient { return .compact(.transient(t)) }
        if let a = liveActivities.first { return .compact(.live(a)) }
        return geometry.hasNotch ? .closed : .hidden
    }

    /// İkinci etkinlik, adanın yanında ayrı bir baloncukta.
    var secondary: LiveActivity? {
        guard settings.secondary, case .compact(.live(let first)) = display else { return nil }
        return liveActivities.first { $0 != first }
    }

    // MARK: - Açma ve kapama

    func expand(page p: IslandPage? = nil) {
        guard settings.enabled else { return }
        if let p { page = p }
        guard !expanded else { return }
        expanded = true
        transient = nil
        transientUntil = nil
        shelf.prune()
        onExpand()
    }

    func collapse() {
        guard expanded else { return }
        expanded = false
        dropTargeted = false
        if page == .shelf, shelf.items.isEmpty { page = .home }
    }

    func toggleExpanded() { expanded ? collapse() : expand() }

    // MARK: - Geçici bildirimler

    /// Kısa süreli bildirim; ada açıkken ya da uyarı varken gösterilmez.
    func show(_ kind: IslandTransientKind, seconds: TimeInterval = 2.2) {
        guard settings.enabled, settings.isOn(kind.feature), !expanded, alert == nil else { return }
        transient = kind
        transientUntil = now().addingTimeInterval(seconds)
        ensureTicker()
    }

    func powerChanged(_ s: PowerState, _ events: [PowerEvent]) {
        power = s
        if let e = events.last { show(.power(s, e), seconds: e == .plugged ? 3 : 2.6) }
    }

    func volumeChanged(_ v: Float, muted: Bool) {
        volume = v
        show(.volume(muted ? 0 : v, muted: muted), seconds: 1.6)
    }

    func setVolume(_ v: Float) {
        volume = v
        setSystemVolume(v)
    }

    // MARK: - Uyarılar

    func dismissAlert() { alert = nil; ensureTicker() }

    func pomoTransition(_ t: PomoTransition, title: String, body: String) {
        guard settings.enabled, settings.isOn(.pomodoro), t.finished else { return }
        alert = IslandAlert(kind: .pomodoro(t.to), title: title, body: body,
                            symbol: t.to.isBreak ? "cup.and.saucer.fill" : "brain.head.profile",
                            until: now().addingTimeInterval(7))
        transient = nil
        ensureTicker()
    }

    // MARK: - Zamanlayıcı

    func startTimer(minutes: Int) { startTimer(seconds: TimeInterval(minutes * 60)) }

    func startTimer(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        countdown = Countdown(seconds: seconds, now: now())
        if case .timer = alert?.kind { alert = nil }
        ensureTicker()
    }

    func toggleTimer() {
        guard var c = countdown else { return }
        if c.running { c.pause(now()) } else { c.resume(now()) }
        countdown = c
        ensureTicker()
    }

    func addToTimer(_ seconds: TimeInterval) {
        guard var c = countdown else { return }
        c.add(seconds)
        countdown = c
    }

    func cancelTimer() {
        countdown = nil
        ensureTicker()
    }

    /// Uyarıdan "+5 dk": aynı zamanlayıcıyı ertele.
    func snooze(minutes: Int = 5) {
        alert = nil
        startTimer(minutes: minutes)
    }

    private func finishTimer(_ c: Countdown) {
        countdown = nil
        alert = IslandAlert(kind: .timer(c.total), title: "Süre doldu", body: "\(IslandFormat.minutes(c.total)) zamanlayıcı bitti.",
                            symbol: "timer", until: now().addingTimeInterval(30))
        transient = nil
        expanded = false
        if settings.timerSound { playSound("Glass") }
        onExpand()
    }

    // MARK: - Kronometre

    func toggleStopwatch() {
        if stopwatch.running { stopwatch.pause(now()) } else { stopwatch.start(now()) }
    }

    func lapOrReset() {
        if stopwatch.running { stopwatch.lap(now()) } else { stopwatch.reset() }
    }

    // MARK: - Robot

    func setRobot(busy: Bool, title: String, detail: String) {
        let next = busy ? RobotStatus(title: title, detail: detail) : nil
        if next != robot { robot = next }
    }

    func robotFinished(collected n: Int) {
        guard n > 0 else { return }
        show(.robot("\(n) görüntü toplandı"), seconds: 3)
    }

    // MARK: - Raf

    /// Sürüklenen dosyaları rafa ekler.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard settings.isOn(.shelf), !fileProviders.isEmpty else { return false }
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for p in fileProviders {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.shelf.add(urls)
            self.page = .shelf
            self.dropTargeted = false
        }
        return true
    }

    // MARK: - Saat

    func tick() {
        let t = now()
        if let u = transientUntil, t >= u { transient = nil; transientUntil = nil }
        if let u = alert?.until, t >= u { alert = nil }
        if let c = countdown, c.finished(t) { finishTimer(c) }
        ensureTicker()
    }

    private var needsTicking: Bool { transient != nil || alert?.until != nil || countdown?.running == true }

    private func ensureTicker() {
        guard autoTick else { return }
        if needsTicking, ticker == nil {
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !needsTicking {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func saveCountdown() {
        guard let store else { return }
        if let c = countdown, let data = try? JSONEncoder().encode(c) { store.set(data, forKey: Self.countdownKey) }
        else { store.removeObject(forKey: Self.countdownKey) }
    }
}
