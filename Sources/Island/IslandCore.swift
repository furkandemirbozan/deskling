import AppKit

// MARK: - Çentik ve ölçüler

/// Çentiğin ekrandaki yeri. Koordinatlar AppKit ekran koordinatıdır (köken sol alt).
struct IslandGeometry: Equatable {
    var notch: CGRect
    var hasNotch: Bool
    var screenFrame: CGRect

    /// Çentikli ekranda menü çubuğunun iki yanında kalan kullanılabilir alanlar arasındaki boşluk çentiktir.
    static func make(frame: CGRect, left: CGRect?, right: CGRect?, safeTop: CGFloat, menuBar: CGFloat) -> IslandGeometry {
        if safeTop > 0, let l = left, let r = right, l.width + r.width < frame.width - 40 {
            let w = frame.width - l.width - r.width
            return IslandGeometry(notch: CGRect(x: frame.minX + l.width, y: frame.maxY - safeTop, width: w, height: safeTop),
                                  hasNotch: true, screenFrame: frame)
        }
        let h = max(24, min(40, menuBar))
        return IslandGeometry(notch: CGRect(x: frame.midX - 90, y: frame.maxY - h, width: 180, height: h),
                              hasNotch: false, screenFrame: frame)
    }

    static func of(_ s: NSScreen) -> IslandGeometry {
        make(frame: s.frame, left: s.auxiliaryTopLeftArea, right: s.auxiliaryTopRightArea,
             safeTop: s.safeAreaInsets.top, menuBar: s.frame.maxY - s.visibleFrame.maxY)
    }

    /// MacBook Air 13" (M2/M3) ölçüleri; testler ve galeri için.
    static let sample = make(frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                             left: CGRect(x: 0, y: 924, width: 646, height: 32),
                             right: CGRect(x: 825, y: 924, width: 645, height: 32), safeTop: 32, menuBar: 33)
}

enum IslandLayout {
    /// Pencerenin sabit tuvali; ada bunun üst ortasında büyüyüp küçülür.
    static let canvas = CGSize(width: 800, height: 300)
    static let expanded = CGSize(width: 640, height: 220)
    static let alert = CGSize(width: 470, height: 132)
    static let bubbleGap: CGFloat = 7

    static func flare(_ d: IslandDisplay) -> CGFloat {
        switch d { case .hidden, .closed: return 0; default: return 6 }
    }

    static func radius(_ d: IslandDisplay) -> CGFloat {
        switch d {
        case .hidden, .closed: return 9
        case .compact: return 12
        case .expanded: return 32
        case .alert: return 30
        }
    }

    /// Adanın gövde ölçüsü (üstteki yumuşak geçişler hariç).
    static func size(_ d: IslandDisplay, _ g: IslandGeometry) -> CGSize {
        switch d {
        case .hidden, .closed: return g.notch.size
        case .compact(let c): return CGSize(width: g.notch.width + 2 * c.ear, height: g.notch.height)
        case .expanded: return CGSize(width: max(expanded.width, g.notch.width + 360), height: expanded.height)
        case .alert: return CGSize(width: max(alert.width, g.notch.width + 200), height: alert.height)
        }
    }

    /// Şeklin ekrandaki dikdörtgeni; fare bunun içindeyken pencere tıklamaları alır.
    static func rect(_ d: IslandDisplay, _ g: IslandGeometry) -> CGRect {
        let s = size(d, g), f = flare(d)
        return CGRect(x: g.notch.midX - s.width / 2 - f, y: g.screenFrame.maxY - s.height, width: s.width + 2 * f, height: s.height)
    }

    /// İkinci etkinliğin yuvarlak baloncuğu: adanın sağında, aynı yükseklikte.
    static func bubbleRect(_ d: IslandDisplay, _ g: IslandGeometry) -> CGRect {
        let r = rect(d, g), h = g.notch.height
        return CGRect(x: r.maxX + bubbleGap, y: g.screenFrame.maxY - h, width: h, height: h)
    }

    /// Kapalıyken fareyi yakalayan bölge: çentik ve biraz çevresi.
    static func trigger(_ d: IslandDisplay, _ g: IslandGeometry) -> CGRect {
        switch d {
        case .hidden, .closed: return g.notch.insetBy(dx: -10, dy: 0).offsetBy(dx: 0, dy: 0)
        default: return rect(d, g)
        }
    }
}

// MARK: - Görünüm durumları

enum LiveActivity: String, Equatable, CaseIterable {
    case health, timer, hole, pomodoro, media, stopwatch, robot

    var feature: IslandFeature {
        switch self {
        case .health: return .health
        case .hole: return .blackHole
        case .timer: return .timer
        case .pomodoro: return .pomodoro
        case .media: return .media
        case .stopwatch: return .stopwatch
        case .robot: return .robot
        }
    }

    var ear: CGFloat {
        switch self {
        case .media: return 58
        case .robot: return 84
        case .hole: return 80
        case .health: return 76
        default: return 72
        }
    }
}

enum IslandTransientKind: Equatable {
    case power(PowerState, PowerEvent)
    case volume(Float, muted: Bool)
    case device(AudioOutput)
    case clipboard(ClipKind, String)
    case robot(String)
    case shelf(Int)
    case hole(String, ok: Bool)

    var feature: IslandFeature {
        switch self {
        case .hole: return .blackHole
        case .power: return .battery
        case .volume: return .volume
        case .device: return .device
        case .clipboard: return .clipboard
        case .robot: return .robot
        case .shelf: return .shelf
        }
    }

    var ear: CGFloat {
        switch self {
        case .power: return 92
        case .volume: return 90
        case .device: return 128
        case .clipboard: return 104
        case .robot: return 200
        case .shelf: return 92
        case .hole: return 190
        }
    }

    /// Aynı türden ardışık olaylar (ör. ses düzeyi) içeriği yeniden canlandırmasın.
    var family: String {
        switch self {
        case .power: return "power"
        case .volume: return "volume"
        case .device: return "device"
        case .clipboard: return "clipboard"
        case .robot: return "robot"
        case .shelf: return "shelf"
        case .hole: return "hole"
        }
    }
}

enum CompactContent: Equatable {
    case live(LiveActivity)
    case transient(IslandTransientKind)

    var ear: CGFloat {
        switch self {
        case .live(let a): return a.ear
        case .transient(let t): return t.ear
        }
    }
}

enum IslandDisplay: Equatable {
    case hidden, closed, compact(CompactContent), expanded, alert

    /// İçerik geçişleri için kimlik.
    var key: String {
        switch self {
        case .hidden: return "hidden"
        case .closed: return "closed"
        case .compact(.live(let a)): return "live-" + a.rawValue
        case .compact(.transient(let t)): return "t-" + t.family
        case .expanded: return "expanded"
        case .alert: return "alert"
        }
    }

    var isLarge: Bool { self == .expanded || self == .alert }
}

enum IslandPage: String, CaseIterable, Identifiable {
    case home, timer, shelf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Şimdi"
        case .timer: return "Zamanlayıcı"
        case .shelf: return "Raf"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .timer: return "timer"
        case .shelf: return "tray.full.fill"
        }
    }
}

struct IslandAlert: Equatable {
    enum Kind: Equatable { case timer(TimeInterval), pomodoro(PomoPhase), health(HealthWarning.Kind, HealthWarning.Level) }
    var kind: Kind
    var title: String
    var body: String
    var symbol: String
    var until: Date?
    /// Tek tıklık eylem düğmesinin yazısı (ör. "Belleği temizle").
    var action: String? = nil
}

/// Kara delikte süren uzun iş (video sıkıştırma gibi).
struct HoleJob: Equatable {
    var title: String
    var percent: Int
}

/// Bellek ya da disk sıkışınca adada beliren uyarı.
struct HealthWarning: Equatable {
    enum Kind: String, Equatable, CaseIterable { case memory, disk }
    enum Level: Int, Comparable {
        case warning = 1, critical = 2
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    var kind: Kind
    var level: Level
    /// Kulakta görünen kısa yazı.
    var short: String
    var title: String
    var body: String
    var action: String

    var symbol: String { kind == .memory ? "memorychip.fill" : "internaldrive.fill" }
}

/// Ne zaman uyarılır? Saf; sayaçlar dışarıdan verilir.
enum HealthRules {
    static let gb: Int64 = 1_000_000_000
    static let diskWarning: Int64 = 15 * gb
    static let diskCritical: Int64 = 5 * gb

    static func evaluate(memory: MemoryStats?, volume: VolumeInfo?, suggested: [AppMemory] = []) -> [HealthWarning] {
        var out: [HealthWarning] = []
        if let m = memory {
            let level: HealthWarning.Level? = m.pressure >= 4 ? .critical
                : (m.pressure >= 2 || (m.usedFraction >= 0.9 && m.swapUsed >= 6 << 30)) ? .warning : nil
            if let level {
                let freed = suggested.reduce(UInt64(0)) { $0 + $1.footprint }
                let names = suggested.prefix(3).map(\.name)
                let body = suggested.isEmpty
                    ? "Kapatılabilecek ağır bir uygulama yok. Bellek sayfasından hangi uygulamanın ne kadar kullandığına bakabilirsin."
                    : "\(ListFormatter.localizedString(byJoining: names))\(suggested.count > 3 ? " +\(suggested.count - 3)" : "") kapanırsa ~\(DiskFormat.bytes(Int64(freed))) boşalır."
                out.append(HealthWarning(kind: .memory, level: level, short: "RAM %\(Int((m.usedFraction * 100).rounded()))",
                                         title: level == .critical ? "Bellek tükeniyor" : "Bellek sıkıştı",
                                         body: body, action: suggested.isEmpty ? "Bellek sayfası" : "Belleği temizle"))
            }
        }
        if let v = volume, v.total > 0 {
            let free = v.available
            let level: HealthWarning.Level? = free < diskCritical ? .critical
                : (free < diskWarning || Double(free) / Double(v.total) < 0.05) ? .warning : nil
            if let level {
                out.append(HealthWarning(kind: .disk, level: level, short: DiskFormat.bytes(free).replacingOccurrences(of: ",0", with: ""),
                                         title: level == .critical ? "Disk dolmak üzere" : "Disk azalıyor",
                                         body: "Yalnızca \(DiskFormat.bytes(free)) boş kaldı. Neyin silinebileceğine bak.",
                                         action: "Diski incele"))
            }
        }
        return out.sorted { $0.level > $1.level }
    }
}

/// Tam ekran bir uygulama öndeyken ada ne yapsın?
enum FullscreenMode: String, CaseIterable, Identifiable {
    case normal, activities, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: return "Her zamanki gibi"
        case .activities: return "Yalnızca etkinlik ve uyarılar"
        case .hidden: return "Tamamen gizle"
        }
    }
}

struct RobotStatus: Equatable {
    var title: String
    var detail: String

    /// Kulakta görünen kısa yazı.
    var short: String {
        if let n = detail.split(separator: " ").first, Int(n) != nil { return "\(n) kaldı" }
        if title.contains("Şarj") { return "Şarjda" }
        if title.contains("Duraklat") { return "Durdu" }
        return "Görevde"
    }
}

// MARK: - Ayarlar

enum IslandFeature: String, CaseIterable, Identifiable {
    case media, pomodoro, timer, stopwatch, robot, blackHole, health, battery, volume, device, clipboard, shelf
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blackHole: return "Kara delik"
        case .health: return "Bellek ve disk uyarıları"
        case .media: return "Şu an çalan"
        case .pomodoro: return "Pomodoro"
        case .timer: return "Zamanlayıcı"
        case .stopwatch: return "Kronometre"
        case .robot: return "Robot görevi"
        case .battery: return "Şarj ve pil"
        case .volume: return "Ses düzeyi"
        case .device: return "Kulaklık ve hoparlör"
        case .clipboard: return "Kopyalama"
        case .shelf: return "Dosya rafı"
        }
    }

    var symbol: String {
        switch self {
        case .blackHole: return "circle.dashed"
        case .health: return "exclamationmark.triangle.fill"
        case .media: return "music.note"
        case .pomodoro: return "cup.and.saucer.fill"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch"
        case .robot: return "sparkles"
        case .battery: return "bolt.fill"
        case .volume: return "speaker.wave.2.fill"
        case .device: return "airpods"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.full.fill"
        }
    }

    var detail: String {
        switch self {
        case .media: return "Müzik ve Spotify: kapak, ilerleme, oynat/duraklat, ileri/geri"
        case .pomodoro: return "Odak ve mola süresi kulakta görünür"
        case .timer: return "Geri sayım; bitince ada açılır ve ses çalar"
        case .stopwatch: return "Tur kaydeden kronometre"
        case .robot: return "Robot toplarken kalan görüntü sayısı, bitince özet"
        case .blackHole: return "Uzun işlerde (video sıkıştırma gibi) ilerleme, bitince sonuç"
        case .health: return "Bellek baskısı artınca ya da disk dolunca tek tıkla temizlik"
        case .battery: return "Şarja takınca, çıkarınca ve pil azalınca"
        case .volume: return "Ses açılıp kısılınca ince bir çubuk"
        case .device: return "AirPods ya da hoparlör değişince"
        case .clipboard: return "Bir şey kopyalanınca kısa bir onay"
        case .shelf: return "Çentiğe sürüklenen dosyalar rafta bekler"
        }
    }
}

final class IslandSettings: ObservableObject {
    static let defaults: [String: Any] = [
        "islandEnabled": true, "islandHoverOpen": true, "islandHoverDelay": 0.15, "islandHaptics": true,
        "islandNoNotch": false, "islandFullscreenMode": FullscreenMode.activities.rawValue, "islandSecondary": true, "islandTimerSound": true,
        "islandOff": [String](), "islandCustomMinutes": 20,
    ]
    static let hoverDelayRange = 0.0...0.8
    static let minutesRange = 1...180

    private let store: UserDefaults?

    @Published var enabled: Bool { didSet { put(enabled, "islandEnabled") } }
    @Published var hoverOpen: Bool { didSet { put(hoverOpen, "islandHoverOpen") } }
    @Published var hoverDelay: Double { didSet { put(hoverDelay, "islandHoverDelay") } }
    @Published var haptics: Bool { didSet { put(haptics, "islandHaptics") } }
    @Published var noNotch: Bool { didSet { put(noNotch, "islandNoNotch") } }
    @Published var fullscreenMode: FullscreenMode { didSet { put(fullscreenMode.rawValue, "islandFullscreenMode") } }
    @Published var secondary: Bool { didSet { put(secondary, "islandSecondary") } }
    @Published var timerSound: Bool { didSet { put(timerSound, "islandTimerSound") } }
    @Published var customMinutes: Int { didSet { put(customMinutes, "islandCustomMinutes") } }
    @Published var off: Set<IslandFeature> { didSet { put(off.map(\.rawValue).sorted(), "islandOff") } }

    /// `store` nil ise ayarlar yalnızca bellekte tutulur (testler).
    init(store: UserDefaults?) {
        self.store = store
        store?.register(defaults: Self.defaults)
        let d = Self.defaults
        func b(_ k: String) -> Bool { store?.bool(forKey: k) ?? (d[k] as! Bool) }
        enabled = b("islandEnabled")
        hoverOpen = b("islandHoverOpen")
        hoverDelay = min(Self.hoverDelayRange.upperBound, max(0, store?.double(forKey: "islandHoverDelay") ?? 0.15))
        haptics = b("islandHaptics")
        noNotch = b("islandNoNotch")
        fullscreenMode = FullscreenMode(rawValue: store?.string(forKey: "islandFullscreenMode") ?? "") ?? .activities
        secondary = b("islandSecondary")
        timerSound = b("islandTimerSound")
        customMinutes = min(Self.minutesRange.upperBound, max(1, store?.integer(forKey: "islandCustomMinutes") ?? 20))
        off = Set((store?.stringArray(forKey: "islandOff") ?? []).compactMap(IslandFeature.init(rawValue:)))
    }

    func isOn(_ f: IslandFeature) -> Bool { !off.contains(f) }

    func set(_ f: IslandFeature, _ on: Bool) {
        if on { off.remove(f) } else { off.insert(f) }
    }

    private func put(_ v: Any, _ k: String) { store?.set(v, forKey: k) }
}

// MARK: - Zamanlayıcı ve kronometre

struct Countdown: Codable, Equatable {
    var total: TimeInterval
    var endDate: Date?
    var left: TimeInterval

    init(seconds: TimeInterval, now: Date) {
        total = seconds
        left = seconds
        endDate = now.addingTimeInterval(seconds)
    }

    var running: Bool { endDate != nil }
    func remaining(_ now: Date) -> TimeInterval { endDate.map { max(0, $0.timeIntervalSince(now)) } ?? left }
    /// Geçen kısmın oranı (0 başta, 1 bitince).
    func progress(_ now: Date) -> Double { total > 0 ? min(1, max(0, 1 - remaining(now) / total)) : 1 }
    func finished(_ now: Date) -> Bool { running && remaining(now) <= 0 }

    mutating func pause(_ now: Date) {
        guard let e = endDate else { return }
        left = max(0, e.timeIntervalSince(now))
        endDate = nil
    }

    mutating func resume(_ now: Date) {
        guard endDate == nil else { return }
        endDate = now.addingTimeInterval(left)
    }

    mutating func add(_ s: TimeInterval) {
        if let e = endDate { endDate = e.addingTimeInterval(s) } else { left += s }
        total += s
    }
}

struct Stopwatch: Equatable {
    var startedAt: Date?
    var base: TimeInterval = 0
    var laps: [TimeInterval] = []

    var running: Bool { startedAt != nil }
    var active: Bool { running || base > 0 }
    func elapsed(_ now: Date) -> TimeInterval { base + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0) }

    mutating func start(_ now: Date) { if startedAt == nil { startedAt = now } }
    mutating func pause(_ now: Date) {
        guard let s = startedAt else { return }
        base += max(0, now.timeIntervalSince(s))
        startedAt = nil
    }
    mutating func lap(_ now: Date) {
        laps.insert(elapsed(now), at: 0)
        if laps.count > 30 { laps.removeLast() }
    }
    mutating func reset() { self = Stopwatch() }
}

enum IslandFormat {
    /// 65 → "1:05", 3725 → "1:02:05"; `tenths` ile "1:05,4".
    static func clock(_ t: TimeInterval, tenths: Bool = false, roundUp: Bool = false) -> String {
        let v = max(0, t)
        let whole = roundUp ? Int(v.rounded(.up)) : Int(v)
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        var out = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        if tenths { out += String(format: ",%d", Int((v - Double(Int(v))) * 10)) }
        return out
    }

    static func minutes(_ t: TimeInterval) -> String {
        if t < 60 { return "\(Int(t.rounded())) saniyelik" }
        let m = Int((t / 60).rounded())
        return m >= 60 && m % 60 == 0 ? "\(m / 60) saatlik" : "\(m) dakikalık"
    }
}

// MARK: - Üzerine gelme

/// Fare çentiğe gelince kısa bir gecikmeyle açar, ayrılınca küçük bir payla kapatır.
struct HoverLogic {
    enum Action: Equatable { case none, expand, collapse, recheck(TimeInterval) }

    var delay: TimeInterval = 0.15
    var grace: TimeInterval = 0.35
    private(set) var insideSince: Date?
    private(set) var outsideSince: Date?

    mutating func update(inTrigger: Bool, inExpanded: Bool, expanded: Bool, enabled: Bool, now: Date) -> Action {
        if expanded {
            insideSince = nil
            if inExpanded { outsideSince = nil; return .none }
            let since = outsideSince ?? now
            outsideSince = since
            let waited = now.timeIntervalSince(since)
            return waited >= grace ? .collapse : .recheck(grace - waited)
        }
        outsideSince = nil
        guard enabled, inTrigger else { insideSince = nil; return .none }
        let since = insideSince ?? now
        insideSince = since
        let waited = now.timeIntervalSince(since)
        if waited >= delay { insideSince = nil; return .expand }
        return .recheck(delay - waited)
    }

    mutating func reset() { insideSince = nil; outsideSince = nil }
}
