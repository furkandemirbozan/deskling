import AppKit

/// AppModel'in Pomodoro tarafı: ayarlar yöneticiye, geçişler bildirim, ses ve uyanık tutmaya bağlanır.
extension AppModel {
    var pomoDurations: PomoDurations {
        PomoDurations(focus: TimeInterval(pomoFocus * 60), shortBreak: TimeInterval(pomoShort * 60),
                      longBreak: TimeInterval(pomoLong * 60), cycle: pomoCycle)
    }

    static func loadPomoSettings(_ d: UserDefaults) -> PomoStored {
        PomoStored(enabled: d.bool(forKey: "pomoEnabled"), showDrink: d.bool(forKey: "pomoShowDrink"),
                   drink: DrinkKind(rawValue: d.string(forKey: "pomoDrink") ?? "") ?? .tea,
                   focus: PomoLimits.clamp(d.integer(forKey: "pomoFocus"), PomoLimits.focus),
                   shortBreak: PomoLimits.clamp(d.integer(forKey: "pomoShort"), PomoLimits.shortBreak),
                   longBreak: PomoLimits.clamp(d.integer(forKey: "pomoLong"), PomoLimits.longBreak),
                   cycle: PomoLimits.clamp(d.integer(forKey: "pomoCycle"), PomoLimits.cycle),
                   scale: min(PomoLimits.scale.upperBound, max(PomoLimits.scale.lowerBound, d.double(forKey: "pomoScale"))),
                   menuTimer: d.bool(forKey: "pomoMenuTimer"),
                   effects: DrinkEffects(rawValue: d.string(forKey: "pomoEffects") ?? "") ?? .high,
                   sound: d.bool(forKey: "pomoSound"), notify: d.bool(forKey: "pomoNotify"),
                   keepAwake: d.bool(forKey: "pomoKeepAwake"), quietFocus: d.bool(forKey: "pomoQuietFocus"),
                   cleanOnBreak: d.bool(forKey: "pomoCleanOnBreak"))
    }

    func connectPomodoro() {
        pomo.onTransition = { [weak self] t in self?.pomoTransition(t) }
        pomo.onTick = { [weak self] in self?.pomoChanged() }
        // Uygulama odak sürerken açıldıysa odağın başladığı an geri hesaplanır.
        if pomo.phase == .focus {
            pomoFocusStarted = pomo.now().addingTimeInterval(-(pomoDurations.focus - pomo.currentRemaining))
        }
        updateAwake()
    }

    /// Masaüstündeki içecek ayarları izler; sağ tık menüsündeki seçimler ayarlara yazılır.
    func connectDrink(_ c: DrinkController) {
        let apply = { [weak self, weak c] in
            guard let self, let c else { return }
            c.kind = self.pomoDrink
            c.scale = self.pomoScale
            c.effects = self.pomoEffects
            c.setVisible(self.pomoEnabled && self.pomoShowDrink)
        }
        pomoListeners.append(apply)
        pomoTransitionListeners.append { [weak c] in c?.transition($0) }
        c.onChooseKind = { [weak self] in self?.pomoDrink = $0 }
        c.onChooseScale = { [weak self] in self?.pomoScale = $0 }
        c.onHide = { [weak self] in self?.pomoShowDrink = false }
        apply()
    }

    func pomoTransition(_ t: PomoTransition) {
        applyQuiet()
        if t.to == .focus { pomoFocusStarted = pomo.now() }
        if t.from == .focus, t.to.isBreak, t.finished, pomoCleanOnBreak, pomoEnabled { cleanAfterFocus() }
        if pomoNotify, let m = PomodoroAlerts.message(for: t, done: pomo.cycleDone == 0 ? pomoCycle : pomo.cycleDone,
                                                       durations: pomoDurations) {
            pomoAlerts.notify(m.title, m.body)
        }
        if t.finished, pomoSound, !silent {
            pomoAlerts.playSound(t.from == .focus ? pomoDrink.focusEndSound : pomoDrink.breakEndSound)
        }
        for l in pomoTransitionListeners { l(t) }
    }

    /// Her saniye ve her ayar değişiminde çağrılır: menü çubuğu, masaüstündeki içecek ve uyanık tutma güncellenir.
    func pomoChanged() {
        updateAwake()
        applyQuiet()
        for l in pomoListeners { l() }
    }

    func updateAwake() {
        pomoAlerts.keepAwake.set(pomoEnabled && pomoKeepAwake && pomo.phase == .focus && pomo.running)
    }

    /// Menü çubuğunda gösterilecek kısa durum; sayaç çalışmıyorsa ya da ayar kapalıysa boş.
    var pomoMenuLabel: String? {
        guard pomoEnabled, pomoMenuTimer, pomo.phase != .idle else { return nil }
        return pomo.clockText
    }

    var pomoSummary: String {
        let p = pomo.phase
        if p == .idle { return "Pomodoro · hazır · bugün \(pomo.todayDone) seans" }
        let state = pomo.running ? p.title : "\(p.title) (duraklatıldı)"
        return "\(state) · \(pomo.clockText) · \(pomo.cycleDone)/\(pomoCycle)"
    }
}

/// Kayıtlı Pomodoro ayarları; AppModel açılırken bir kerede okunur.
struct PomoStored {
    var enabled: Bool
    var showDrink: Bool
    var drink: DrinkKind
    var focus, shortBreak, longBreak, cycle: Int
    var scale: Double
    var menuTimer: Bool
    var effects: DrinkEffects
    var sound, notify, keepAwake, quietFocus, cleanOnBreak: Bool
}
