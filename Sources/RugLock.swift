import AppKit
import LocalAuthentication

/// Halının altını Touch ID (yoksa Mac parolası) ile kilitler.
/// Halı açıkken kilit açık kalır; kapandıktan kısa bir süre sonra, uykuda ya da ekran kilitlenince yeniden kilitlenir.
final class RugLock {
    static let grace: TimeInterval = 60

    var enabled: () -> Bool = { false }
    /// Halının altında bir şey yoksa sorulmaz.
    var hasSecrets: () -> Bool = { true }
    var now: () -> Date = Date.init
    /// Gerçek uygulamada sistemin kimlik doğrulama penceresi; testler sahtesini verir.
    var evaluate: (String, @escaping (Bool) -> Void) -> Void = RugLock.system
    var onLock: () -> Void = {}

    private(set) var unlockedUntil: Date?
    private var waiting: [(Bool) -> Void] = []
    private var observers: [NSObjectProtocol] = []

    var needsAuth: Bool { enabled() && hasSecrets() && !isUnlocked }
    var isUnlocked: Bool { unlockedUntil.map { now() < $0 } ?? false }
    /// Halının altındakiler gösterilebilir mi?
    var canReveal: Bool { !needsAuth }

    init(watchSystem: Bool = false) {
        guard watchSystem else { return }
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.lock() })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                                             object: nil, queue: .main) { [weak self] _ in self?.lock() })
    }

    /// Gerekirse kimlik sorar; aynı anda gelen istekler tek pencereyle yanıtlanır.
    func unlock(_ reason: String, then done: @escaping (Bool) -> Void) {
        guard needsAuth else { done(true); return }
        waiting.append(done)
        guard waiting.count == 1 else { return }
        evaluate(reason) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else { return }
                if ok { self.unlockedUntil = .distantFuture }
                let list = self.waiting
                self.waiting = []
                list.forEach { $0(ok) }
            }
        }
    }

    /// Halı kapandı: kısa bir süre daha açık kalır.
    func closed() {
        guard unlockedUntil != nil else { return }
        unlockedUntil = now().addingTimeInterval(Self.grace)
    }

    func lock() {
        guard unlockedUntil != nil else { return }
        unlockedUntil = nil
        onLock()
    }

    /// Touch ID varsa onu, yoksa Mac parolasını sorar. Hiçbiri kullanılamıyorsa kilit engel olmaz.
    static func system(_ reason: String, _ done: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Vazgeç"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { done(true); return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in done(ok) }
    }
}

/// `--rug-lock-check`: kilidin mantığı, gerçek kimlik penceresi açılmadan.
enum RugLockCheck {
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print((ok ? "GEÇTİ  " : "KALDI  ") + name)
            if !ok { failures += 1 }
        }
        var t = Date(timeIntervalSinceReferenceDate: 0)
        var asked = 0
        var answer = true
        var secrets = true
        var enabled = true
        let lock = RugLock()
        lock.now = { t }
        lock.enabled = { enabled }
        lock.hasSecrets = { secrets }
        lock.evaluate = { _, done in asked += 1; done(answer) }
        func unlockNow() -> Bool {
            var result: Bool?
            lock.unlock("deneme") { result = $0 }
            let end = Date().addingTimeInterval(2)
            while result == nil, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            return result ?? false
        }

        check("kilitliyken halının altı gösterilmez", !lock.canReveal)
        answer = false
        check("doğrulama başarısızsa açılmaz", !unlockNow() && asked == 1 && !lock.canReveal)
        answer = true
        check("doğrulayınca açılır", unlockNow() && asked == 2 && lock.canReveal)
        check("açıkken yeniden sorulmaz", unlockNow() && asked == 2)
        t += 3600
        check("halı açık kaldıkça kilit açık kalır", lock.canReveal)
        lock.closed()
        t += RugLock.grace - 1
        check("kapandıktan hemen sonra sorulmaz", lock.canReveal)
        t += 2
        check("süre dolunca yeniden kilitlenir", !lock.canReveal)
        _ = unlockNow()
        var locked = false
        lock.onLock = { locked = true }
        lock.lock()
        check("uyku ya da ekran kilidinde kilitlenir", !lock.canReveal && locked)
        secrets = false
        check("halının altı boşsa sorulmaz", lock.canReveal && unlockNow() && asked == 3)
        secrets = true
        enabled = false
        check("ayar kapalıysa sorulmaz", lock.canReveal && unlockNow() && asked == 3)
        enabled = true
        var results: [Bool] = []
        lock.evaluate = { _, done in asked += 1; DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { done(true) } }
        lock.unlock("a") { results.append($0) }
        lock.unlock("b") { results.append($0) }
        let end = Date().addingTimeInterval(2)
        while results.count < 2, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check("aynı anda iki istek tek pencere açar", results == [true, true] && asked == 4)
        print(failures == 0 ? "HALI_KILIT_GECTI" : "HALI_KILIT_KALDI hata=\(failures)")
        return failures == 0 ? 0 : 1
    }
}
