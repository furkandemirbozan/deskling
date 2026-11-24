import AppKit
import IOKit.pwr_mgt
import UserNotifications

/// Bildirim, ses ve uyanık tutma. Her biri dışarıdan değiştirilebilir; testler gerçek sisteme dokunmaz.
final class PomodoroAlerts {
    var notify: (_ title: String, _ body: String) -> Void
    var playSound: (_ name: String) -> Void
    var keepAwake: KeepAwake

    init(notify: @escaping (String, String) -> Void, playSound: @escaping (String) -> Void, keepAwake: KeepAwake) {
        self.notify = notify
        self.playSound = playSound
        self.keepAwake = keepAwake
    }

    static func system() -> PomodoroAlerts {
        PomodoroAlerts(notify: Notifier.post, playSound: { NSSound(named: $0)?.play() }, keepAwake: KeepAwake())
    }

    /// Bir geçişte ne söyleneceği. Yalnızca süre dolarak biten aşamalar duyurulur.
    static func message(for t: PomoTransition, done: Int, durations: PomoDurations) -> (title: String, body: String)? {
        guard t.finished else { return nil }
        switch t.to {
        case .shortBreak:
            return ("Odak tamamlandı", "\(Int(durations.shortBreak / 60)) dakika mola. Bu döngüde \(done)/\(durations.cycle) seans bitti.")
        case .longBreak:
            return ("Döngü tamamlandı", "\(durations.cycle) odak seansı bitti. \(Int(durations.longBreak / 60)) dakika uzun mola.")
        case .focus:
            return ("Mola bitti", "Yeni odak seansı başladı.")
        case .idle:
            return ("Mola bitti", "Hazır olduğunda yeni odak seansını başlat.")
        }
    }
}

/// Yerel bildirimler. İzin ilk bildirimden önce bir kez istenir.
enum Notifier {
    private static var asked = false

    static func requestOnce() {
        guard !asked, Bundle.main.bundleIdentifier != nil else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        requestOnce()
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        // Ses bildirimle değil, temanın kendi sesiyle çalınır; "sessiz" ayarı ikisini birden susturmasın diye ayrı tutulur.
        let r = UNNotificationRequest(identifier: "pomo-\(UUID().uuidString)", content: c, trigger: nil)
        UNUserNotificationCenter.current().add(r)
    }
}

/// Odak sırasında ekranın kararmasını ve Mac'in uyumasını engeller.
class KeepAwake {
    private var id: IOPMAssertionID = 0
    private var held = false
    var active: Bool { held }

    func set(_ on: Bool) {
        if on == active { return }
        on ? acquire() : release()
    }

    func acquire() {
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "Deskling odak seansı" as CFString, &id)
        held = r == kIOReturnSuccess
    }

    func release() {
        if held { IOPMAssertionRelease(id) }
        held = false
    }

    deinit { release() }
}

/// Testlerde gerçek güç yönetimine dokunmayan sahte uyanık tutma.
final class FakeKeepAwake: KeepAwake {
    private(set) var log: [Bool] = []
    private var on = false
    override var active: Bool { on }
    override func acquire() { on = true; log.append(true) }
    override func release() { if on { log.append(false) }; on = false }
}
