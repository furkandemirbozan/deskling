import Foundation
import Combine

enum PomoPhase: String, Codable {
    case idle, focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .idle: return "Hazır"
        case .focus: return "Odak"
        case .shortBreak: return "Kısa mola"
        case .longBreak: return "Uzun mola"
        }
    }

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

struct PomoDurations: Equatable {
    var focus: TimeInterval = 25 * 60
    var shortBreak: TimeInterval = 5 * 60
    var longBreak: TimeInterval = 15 * 60
    var cycle = 4   // kaç odaktan sonra uzun mola

    func length(of p: PomoPhase) -> TimeInterval {
        switch p {
        case .idle, .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

/// Bir aşamadan diğerine geçiş. `finished` süre dolarak bittiğinde doğrudur; atlama ya da sıfırlamada yanlıştır.
struct PomoTransition: Equatable {
    var from: PomoPhase
    var to: PomoPhase
    var finished: Bool
}

/// Pomodoro durum makinesi. Kalan süre bitiş anından hesaplanır; Mac uyusa ya da zamanlayıcı gecikse de sayaç kaymaz.
final class PomodoroManager: ObservableObject {
    @Published private(set) var phase: PomoPhase = .idle
    @Published private(set) var running = false
    @Published private(set) var remaining: TimeInterval
    /// Bu döngüde tamamlanan odak sayısı; uzun moladan sonra sıfırlanır.
    @Published private(set) var cycleDone = 0
    /// Bugün tamamlanan odak sayısı.
    @Published private(set) var todayDone = 0

    var durations: PomoDurations {
        didSet {
            guard durations != oldValue else { return }
            // Bekleyen aşamanın süresi yeni ayara uyar; çalışan aşama, geçen süre korunarak yeni uzunluğa geçer.
            if phase == .idle { remaining = durations.focus }
            else if !running, remaining == oldValue.length(of: phase) { remaining = durations.length(of: phase) }
            else {
                let elapsed = oldValue.length(of: phase) - currentRemaining
                setRemaining(max(1, durations.length(of: phase) - elapsed))
            }
            save()
        }
    }
    var autoStartBreaks = true
    var autoStartFocus = false

    var now: () -> Date
    var onTransition: (PomoTransition) -> Void = { _ in }
    var onTick: () -> Void = {}

    private var endDate: Date?
    private var timer: Timer?
    private let defaults: UserDefaults?
    private var todayKey: String

    static let stateKey = "pomoState"

    /// `defaults` verilmezse durum kaydedilmez; testler böyle çalışır.
    init(durations: PomoDurations = PomoDurations(), defaults: UserDefaults? = nil, now: @escaping () -> Date = Date.init) {
        self.durations = durations
        self.defaults = defaults
        self.now = now
        remaining = durations.focus
        todayKey = Self.dayKey(now())
        restore()
    }

    // MARK: - Durum

    var isPaused: Bool { phase != .idle && !running }

    /// Geçerli aşamanın ilerleyişi: 0 başlangıç, 1 bitiş.
    var progress: Double {
        let total = durations.length(of: phase)
        guard phase != .idle, total > 0 else { return 0 }
        return min(1, max(0, 1 - currentRemaining / total))
    }

    var currentRemaining: TimeInterval {
        guard running, let endDate else { return remaining }
        return max(0, endDate.timeIntervalSince(now()))
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var clockText: String { Self.clock(currentRemaining) }

    // MARK: - Komutlar

    /// Hazırdayken odak başlatır, duraklatılmışsa devam ettirir.
    func start() {
        if phase == .idle { enter(.focus, finished: false, run: true); return }
        guard !running else { return }
        running = true
        endDate = now().addingTimeInterval(remaining)
        startTimer()
        save()
        onTick()
    }

    func pause() {
        guard running else { return }
        remaining = currentRemaining
        running = false
        endDate = nil
        stopTimer()
        save()
        onTick()
    }

    func toggle() { running ? pause() : start() }

    /// Sayacı durdurur ve hazır duruma döner. Döngü sayacı korunur.
    func reset() {
        guard phase != .idle || running else { return }
        enter(.idle, finished: false, run: false)
    }

    /// Geçerli aşamayı bitmiş saymadan sonrakine geçer.
    func skip() {
        switch phase {
        case .idle: enter(.focus, finished: false, run: true)
        case .focus: enter(.shortBreak, finished: false, run: true)
        case .shortBreak, .longBreak: enter(.focus, finished: false, run: true)
        }
    }

    /// Zamanlayıcı çağırır; testler de saati ilerletip elle çağırır.
    func tick() {
        rollDay()
        guard running else { return }
        if currentRemaining <= 0 { complete() } else { onTick() }
    }

    private func complete() {
        switch phase {
        case .idle: return
        case .focus:
            cycleDone += 1
            todayDone += 1
            let next: PomoPhase = cycleDone >= max(1, durations.cycle) ? .longBreak : .shortBreak
            enter(next, finished: true, run: autoStartBreaks)
        case .shortBreak:
            enter(autoStartFocus ? .focus : .idle, finished: true, run: autoStartFocus)
        case .longBreak:
            cycleDone = 0
            enter(autoStartFocus ? .focus : .idle, finished: true, run: autoStartFocus)
        }
    }

    private func enter(_ next: PomoPhase, finished: Bool, run: Bool) {
        let from = phase
        phase = next
        remaining = durations.length(of: next)
        running = run && next != .idle
        endDate = running ? now().addingTimeInterval(remaining) : nil
        running ? startTimer() : stopTimer()
        save()
        onTransition(PomoTransition(from: from, to: next, finished: finished))
        onTick()
    }

    private func setRemaining(_ t: TimeInterval) {
        remaining = t
        if running { endDate = now().addingTimeInterval(t) }
    }

    private func rollDay() {
        let key = Self.dayKey(now())
        if key != todayKey { todayKey = key; todayDone = 0; save() }
    }

    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: - Zamanlayıcı

    private func startTimer() {
        guard timer == nil, defaults != nil else { return }   // testlerde tick elle çağrılır
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Kayıt

    private struct Snapshot: Codable {
        var phase: PomoPhase
        var running: Bool
        var remaining: TimeInterval
        var endDate: Date?
        var cycleDone: Int
        var todayDone: Int
        var day: String
    }

    private func save() {
        guard let defaults else { return }
        let s = Snapshot(phase: phase, running: running, remaining: remaining, endDate: endDate,
                         cycleDone: cycleDone, todayDone: todayDone, day: todayKey)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: Self.stateKey) }
    }

    /// Uygulama yeniden açılınca sayaç kaldığı yerden sürer. Kapalıyken süresi dolan aşama sessizce kapanır.
    private func restore() {
        guard let defaults, let data = defaults.data(forKey: Self.stateKey),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        todayDone = s.day == todayKey ? s.todayDone : 0
        cycleDone = s.cycleDone
        guard s.phase != .idle else { return }
        if s.running, let end = s.endDate {
            let left = end.timeIntervalSince(now())
            guard left > 0 else { save(); return }
            phase = s.phase
            remaining = left
            running = true
            endDate = end
            startTimer()
        } else {
            phase = s.phase
            remaining = min(s.remaining, durations.length(of: s.phase))
        }
    }

    /// Ayar silinince ya da testlerde temiz başlangıç için.
    func forget() {
        stopTimer()
        defaults?.removeObject(forKey: Self.stateKey)
    }
}
