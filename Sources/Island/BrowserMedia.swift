import AppKit
import ApplicationServices
import CoreAudio

/// Desteklenen tarayıcılar. Chromium tabanlılar aynı AppleScript sözlüğünü paylaşır.
struct BrowserKind: Equatable {
    enum Engine: Equatable { case chromium, safari, firefox }
    let id: String
    let name: String
    let engine: Engine

    var chromium: Bool { engine == .chromium }

    static let all: [BrowserKind] = [
        BrowserKind(id: "com.google.Chrome", name: "Google Chrome", engine: .chromium),
        BrowserKind(id: "com.brave.Browser", name: "Brave", engine: .chromium),
        BrowserKind(id: "com.microsoft.edgemac", name: "Microsoft Edge", engine: .chromium),
        BrowserKind(id: "com.vivaldi.Vivaldi", name: "Vivaldi", engine: .chromium),
        BrowserKind(id: "org.chromium.Chromium", name: "Chromium", engine: .chromium),
        BrowserKind(id: "company.thebrowser.Browser", name: "Arc", engine: .chromium),
        BrowserKind(id: "com.operasoftware.Opera", name: "Opera", engine: .chromium),
        BrowserKind(id: "com.apple.Safari", name: "Safari", engine: .safari),
        BrowserKind(id: "org.mozilla.firefox", name: "Firefox", engine: .firefox),
        BrowserKind(id: "org.mozilla.firefoxdeveloperedition", name: "Firefox Developer Edition", engine: .firefox),
        BrowserKind(id: "app.zen-browser.zen", name: "Zen", engine: .firefox),
    ]

    var pid: pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.processIdentifier }

    /// Ses çıkaran süreç bu tarayıcıya mı ait? Sekmeler ayrı yardımcı süreçlerde çalar.
    func owns(audioBundle b: String) -> Bool {
        switch engine {
        case .chromium: return b.hasPrefix(id)
        case .safari: return b.hasPrefix("com.apple.WebKit") || b.hasPrefix(id)
        case .firefox: return b.hasPrefix("org.mozilla.") || b.hasPrefix(id)
        }
    }

    static func find(_ id: String) -> BrowserKind? { all.first { $0.id == id } }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }

    /// Ayarın yeri, kullanıcıya gösterilecek ipucu.
    var jsHint: String {
        engine == .firefox ? "Firefox: Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik'te Deskling'i aç"
        : chromium ? "\(name) menü çubuğunda Görünüm → Geliştirici → \"Apple Events'ten JavaScript'e izin ver\". Birden çok Chrome profili varsa müziğin çaldığı profilin penceresinde açılmalı"
        : "Safari: Ayarlar → Gelişmiş → \"Web geliştiricileri için özellikleri göster\"; sonra Ayarlar → Geliştirici → \"Apple Events'ten JavaScript'e izin ver\""
    }
}

/// Bir sekmenin kimliği: Chromium'da pencere ve sekme kimliği, Safari'de pencere kimliği ve sekme sırası.
struct BrowserTab: Equatable {
    var browser: String
    var window: String
    var tab: String
}

/// Sekmedeki oynatıcıdan okunan bilgi.
struct BrowserPayload: Equatable {
    var title: String
    var artist: String
    var album: String
    var artwork: String
    var duration: Double
    var position: Double
    var playing: Bool
    /// Yalnızca sekme ya da pencere başlığından okunduysa: konum, kapak ve sayfa içi denetim yok.
    var limited = false
}

enum BrowserStatus: Equatable { case ok, jsOff, denied, needsAccess }

/// Tarayıcılardaki müzik sekmelerini AppleScript ve sayfa içi JavaScript ile okur ve denetler.
/// Yalnızca bilinen müzik ve video sitelerinin sekmelerine bakar; tarayıcı açık değilse hiçbir şey göndermez.
final class BrowserMedia {
    static let sites = ["music.youtube.com", "youtube.com/watch", "open.spotify.com", "soundcloud.com",
                        "music.apple.com", "deezer.com", "listen.tidal.com"]

    /// Sayfada çalan (yoksa ilk) medya öğesini ve Media Session bilgisini JSON olarak döner.
    /// AppleScript dizgesine gömüldüğü için içinde çift tırnak ve ters bölü yoktur.
    static let readJS = """
    (function(){var ms=document.querySelectorAll('video,audio');var m=null;for(var i=0;i<ms.length;i++){if(!ms[i].paused){m=ms[i];break}}\
    if(!m&&ms.length)m=ms[0];var md=navigator.mediaSession?navigator.mediaSession.metadata:null;if(!m&&!md)return '';\
    var art='';if(md&&md.artwork&&md.artwork.length)art=md.artwork[md.artwork.length-1].src;\
    var st=navigator.mediaSession?navigator.mediaSession.playbackState:'none';\
    return JSON.stringify({t:(md&&md.title)?md.title:document.title,a:md?(md.artist||''):'',al:md?(md.album||''):'',art:art,\
    d:(m&&isFinite(m.duration))?m.duration:0,p:m?m.currentTime:0,pl:m?!m.paused:st==='playing'})})()
    """

    enum Command: Equatable {
        /// `true` çal, `false` duraklat. Ada hangi durumu gösteriyorsa tersini ister; düz "değiştir" ile durum kaymaz.
        case setPlaying(Bool), next, previous, seek(Double)

        /// Sayfadaki asıl oynatıcı: YouTube'un ana videosu, yoksa çalan, yoksa en uzun ortam öğesi.
        static let media = "var ms=[].slice.call(document.querySelectorAll('video,audio'));var m=document.querySelector('video.html5-main-video')||ms.filter(function(x){return !x.paused})[0]||ms.sort(function(a,b){return (b.duration||0)-(a.duration||0)})[0];"

        var js: String {
            let media = Self.media
            switch self {
            case .setPlaying(let want):
                // Spotify kendi düğmesini ister; diğerlerinde ortam öğesi doğrudan yönetilir, düğme son çare.
                return "(function(want){var sb=document.querySelector('[data-testid=control-button-playpause]');if(sb&&location.host.indexOf('spotify')>=0){sb.click();return 'b'}\(media)if(m){if(want&&m.paused){var p=m.play();if(p&&p.catch)p.catch(function(){})}else if(!want&&!m.paused){m.pause()}return 'm'}var b=sb||document.querySelector('#play-pause-button,.ytp-play-button,.playControl');if(b){b.click();return 'b'}return 'yok'})(\(want))"
            case .next:
                return "(function(){var b=document.querySelector('.next-button,.ytp-next-button,[data-testid=control-button-skip-forward],.skipControl__next');if(b){b.click();return 'b'}return 'yok'})()"
            case .previous:
                return "(function(){var b=document.querySelector('.previous-button,[data-testid=control-button-skip-back],.skipControl__previous');if(b){b.click();return 'b'}\(media)if(m){m.currentTime=0;return 'm'}return 'yok'})()"
            case .seek(let s):
                return "(function(){\(media)if(m){m.currentTime=\(String(format: "%.2f", max(0, s)));return 'm'}return 'yok'})()"
            }
        }
    }

    var onResult: ([(BrowserTab, BrowserPayload)]) -> Void = { _ in }
    var onStatus: ([String: BrowserStatus]) -> Void = { _ in }
    private(set) var status: [String: BrowserStatus] = [:]
    private let queue: DispatchQueue
    private var timer: Timer?
    private var busy = false
    private var nextAllowed: [String: Date] = [:]
    private var compiled: [String: NSAppleScript] = [:]   // yalnızca `queue` üzerinde kullanılır
    var hasTrack = false { didSet { if hasTrack != oldValue { reschedule() } } }

    init(queue: DispatchQueue) { self.queue = queue }

    func start() {
        guard timer == nil else { return }
        makeTimer()
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Çalan bir sekme varken sık, yokken seyrek bakılır.
    private func reschedule() {
        guard timer != nil else { return }
        makeTimer()
    }

    private func makeTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: hasTrack ? 1.5 : 3, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func poll() {
        guard !busy else { return }
        let now = Date()
        let targets = BrowserKind.all.filter { $0.isRunning && (nextAllowed[$0.id] ?? .distantPast) <= now }
        let running = Set(BrowserKind.all.filter(\.isRunning).map(\.id))
        if status.keys.contains(where: { !running.contains($0) }) {
            status = status.filter { running.contains($0.key) }
            onStatus(status)
        }
        guard !targets.isEmpty else { onResult([]); return }
        busy = true
        queue.async { [weak self] in
            guard let self else { return }
            var found: [(BrowserTab, BrowserPayload)] = []
            var states: [String: BrowserStatus] = [:]
            let audio = AudioActivity.playingBundles()
            for b in targets {
                let sounding = audio.map { set in set.contains { b.owns(audioBundle: $0) } } ?? true
                if b.engine == .firefox {
                    // Firefox AppleScript ile sekme vermez; pencere başlığı Erişilebilirlik üzerinden okunur.
                    guard let pid = b.pid, let titles = WindowTitles.read(pid: pid) else { states[b.id] = .needsAccess; continue }
                    states[b.id] = .ok
                    found += titles.enumerated().compactMap { i, t in
                        Self.fromTitle(t, browser: b.id, window: String(i), tab: "0", sounding: sounding, requireSite: true)
                    }
                    continue
                }
                let (out, err) = self.execute(Self.readScript(b), key: "read-" + b.id)
                if let err {
                    states[b.id] = err
                } else {
                    let text = out ?? ""
                    let got = Self.parse(text, browser: b.id, sounding: sounding)
                    found += got
                    // Ayar kapalıysa sekme başlığıyla sınırlı çalışılır; ipucu yine de gösterilir.
                    let jsError = text.split(whereSeparator: \.isNewline).contains { $0.hasPrefix("ERR|") && $0.localizedCaseInsensitiveContains("javascript") }
                    states[b.id] = jsError && !got.contains { !$0.1.limited } ? .jsOff : .ok
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                for (id, s) in states {
                    // Kapalı ayar ya da reddedilen izin için tarayıcıyı her saniye rahatsız etme.
                    self.nextAllowed[id] = s == .denied ? Date().addingTimeInterval(60) : nil
                }
                if states.contains(where: { self.status[$0.key] != $0.value }) {
                    self.status.merge(states) { $1 }
                    self.onStatus(self.status)
                }
                self.onResult(found)
            }
        }
    }

    /// Komutu sekmenin içinde çalıştırır. JavaScript kapalıysa, izin yoksa ya da sayfada oynatıcı bulunamazsa
    /// `fallback` ana iş parçacığında çağrılır.
    func send(_ c: Command, to tab: BrowserTab, fallback: @escaping () -> Void = {}) {
        guard let b = BrowserKind.find(tab.browser), b.isRunning, b.engine != .firefox else { fallback(); return }
        let src = b.chromium
            ? "tell application id \"\(b.id)\" to execute (tab id \(tab.tab) of window id \(tab.window)) javascript \"\(c.js)\""
            : "tell application id \"\(b.id)\" to do JavaScript \"\(c.js)\" in tab \(tab.tab) of window id \(tab.window)"
        queue.async { [weak self] in
            guard let self else { return }
            let (out, err) = self.execute(src, key: nil)
            let worked = err == nil && out != nil && out != "" && out != "yok"
            DispatchQueue.main.async {
                if !worked { fallback() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
            }
        }
    }

    func activate(_ tab: BrowserTab) {
        NSRunningApplication.runningApplications(withBundleIdentifier: tab.browser).first?.activate()
    }

    // MARK: Betikler

    static func readScript(_ b: BrowserKind) -> String {
        let cond = sites.map { "u contains \"\($0)\"" }.joined(separator: " or ")
        if b.chromium {
            return """
            tell application id "\(b.id)"
                set out to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if \(cond) then
                            try
                                set r to execute t javascript "\(readJS)"
                                if r is not missing value and r is not "" then set out to out & (id of w as text) & "|" & (id of t as text) & "|" & r & linefeed
                            on error m number n
                                set out to out & "ERR|" & n & "|" & m & linefeed
                                set out to out & "T|" & (id of w as text) & "|" & (id of t as text) & "|" & (title of t) & linefeed
                            end try
                        end if
                    end repeat
                end repeat
                return out
            end tell
            """
        }
        return """
        tell application id "\(b.id)"
            set out to ""
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    set u to URL of t
                    if u is not missing value then
                        if \(cond) then
                            try
                                set r to do JavaScript "\(readJS)" in t
                                if r is not missing value and r is not "" then set out to out & (id of w as text) & "|" & (i as text) & "|" & r & linefeed
                            on error m number n
                                set out to out & "ERR|" & n & "|" & m & linefeed
                                set out to out & "T|" & (id of w as text) & "|" & (i as text) & "|" & (name of t) & linefeed
                            end try
                        end if
                    end if
                end repeat
            end repeat
            return out
        end tell
        """
    }

    /// Satırlar "pencere|sekme|json" biçimindedir.
    static func parse(_ text: String, browser: String, sounding: Bool = true) -> [(BrowserTab, BrowserPayload)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            if line.hasPrefix("T|") {
                let p = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
                guard p.count == 4 else { return nil }
                return fromTitle(String(p[3]), browser: browser, window: String(p[1]), tab: String(p[2]), sounding: sounding, requireSite: false)
            }
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let data = String(parts[2]).data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = o["t"] as? String, !title.isEmpty else { return nil }
            let p = BrowserPayload(title: Self.cleanTitle(title), artist: o["a"] as? String ?? "", album: o["al"] as? String ?? "",
                                   artwork: o["art"] as? String ?? "", duration: (o["d"] as? NSNumber)?.doubleValue ?? 0,
                                   position: (o["p"] as? NSNumber)?.doubleValue ?? 0, playing: o["pl"] as? Bool ?? false)
            return (BrowserTab(browser: browser, window: String(parts[0]), tab: String(parts[1])), p)
        }
    }

    /// Yalnızca başlık biliniyorsa: site adı atılır, "Şarkı • Sanatçı" biçimi ayrılır, çalıyor mu bilgisi sistemin
    /// ses bilgisinden gelir. Firefox'ta (adres bilinmediği için) başlığın bir müzik sitesine ait olması şarttır.
    static func fromTitle(_ raw: String, browser: String, window: String, tab: String, sounding: Bool,
                          requireSite: Bool) -> (BrowserTab, BrowserPayload)? {
        var t = raw
        for tail in [" — Mozilla Firefox", " – Mozilla Firefox", " - Mozilla Firefox", " — Firefox Developer Edition",
                     " — Mozilla Firefox Private Browsing", " — Zen Browser", " - Zen Browser"] where t.hasSuffix(tail) {
            t.removeLast(tail.count)
        }
        let markers = [" - YouTube Music", " | YouTube Music", " - YouTube", " | YouTube", " | Spotify", " | SoundCloud",
                       " | Apple Music", " | Deezer", " | TIDAL"]
        let site = markers.contains { t.hasSuffix($0) } || t.contains(" • ") || t.contains("Listen online for free on SoundCloud")
        if requireSite, !site { return nil }
        if let r = t.range(of: " | Listen online for free on SoundCloud") { t = String(t[..<r.lowerBound]) }
        t = cleanTitle(t)
        for bare in ["YouTube Music", "YouTube", "Spotify", "Spotify – Web Player", "Spotify - Web Player", "SoundCloud"] where t == bare { return nil }
        guard !t.isEmpty else { return nil }
        var title = t, artist = ""
        if let r = t.range(of: " • ") {
            title = String(t[..<r.lowerBound])
            artist = String(t[r.upperBound...])
        }
        return (BrowserTab(browser: browser, window: window, tab: tab),
                BrowserPayload(title: title, artist: artist, album: "", artwork: "", duration: 0, position: 0, playing: sounding, limited: true))
    }

    /// Media Session yoksa sekme başlığından site adı atılır.
    static func cleanTitle(_ t: String) -> String {
        var s = t
        for suffix in [" - YouTube Music", " | YouTube Music", " - YouTube", " | YouTube", " | Spotify", " | SoundCloud",
                       " | Apple Music", " | Deezer", " | TIDAL"] where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
        }
        if s.hasPrefix("("), let close = s.firstIndex(of: ")"), s[s.index(after: s.startIndex)..<close].allSatisfy(\.isNumber) {
            s = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)   // "(3) Şarkı" bildirim sayısı
        }
        return s
    }

    /// Birden çok sekme varsa çalan ve tam okunan önce gelir.
    static func pick(_ list: [(BrowserTab, BrowserPayload)]) -> (BrowserTab, BrowserPayload)? {
        list.first { $0.1.playing && !$0.1.limited } ?? list.first { $0.1.playing }
            ?? list.first { !$0.1.limited } ?? list.first
    }

    private func execute(_ src: String, key: String?) -> (String?, BrowserStatus?) {
        let script: NSAppleScript?
        if let key, let s = compiled[key] { script = s } else {
            script = NSAppleScript(source: src)
            if let key, let s = script { compiled[key] = s }
        }
        var err: NSDictionary?
        let out = script?.executeAndReturnError(&err)
        if let err {
            let n = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? ""
            if n == -1743 || n == -1744 { return (nil, .denied) }
            if msg.localizedCaseInsensitiveContains("javascript") { return (nil, .jsOff) }
            return ("", nil)   // pencere kapanırken vb. geçici hata
        }
        return (out?.stringValue, nil)
    }
}


/// O an ses çıkaran süreçlerin paket kimlikleri (macOS 14.2+, izin gerektirmez).
enum AudioActivity {
    static func playingBundles() -> Set<String>? {
        guard #available(macOS 14.2, *) else { return nil }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return nil }
        var out: Set<String> = []
        for id in ids {
            var running: UInt32 = 0
            var rs = UInt32(MemoryLayout<UInt32>.size)
            var ra = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput, mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &ra, 0, nil, &rs, &running) == noErr, running != 0 else { continue }
            var name: Unmanaged<CFString>?
            var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var na = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(id, &na, 0, nil, &ns, &name) == noErr, let b = name?.takeRetainedValue() as String? { out.insert(b) }
        }
        return out
    }
}

/// Bir uygulamanın pencere başlıkları; Erişilebilirlik izni yoksa nil.
enum WindowTitles {
    static func read(pid: pid_t) -> [String]? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.compactMap { w in
            var t: CFTypeRef?
            return AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success ? t as? String : nil
        }
    }
}

/// Klavyedeki medya tuşlarına basılmış gibi yapar; sayfa içi denetim yokken kullanılır (Erişilebilirlik izni ister).
enum MediaKeys {
    enum Key: Int { case playPause = 16, next = 17, previous = 18 }

    /// Sayfanın içine ulaşılamayan çalarlar için: önce sistemin "Şimdi Çalıyor" komutu (izin gerektirmez),
    /// o kabul edilmezse medya tuşu (Erişilebilirlik izni gerekir).
    static func control(_ key: Key) {
        let c: MediaRemote.Command = key == .playPause ? .toggle : key == .next ? .next : .previous
        if MediaRemote.shared.command(c) { return }
        if AXIsProcessTrusted() { press(key) }
    }

    static func press(_ key: Key) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (key.rawValue << 16) | ((down ? 0xa : 0xb) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                               context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
