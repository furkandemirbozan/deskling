import AppKit
import Carbon

/// Pano yöneticisini özel bir pano üzerinde dener: gerçek panoya ve gerçek geçmiş dosyasına dokunmaz,
/// öndeki uygulamaya ⌘V göndermez.
final class ClipboardCheck {
    private var failures = 0
    private let fm = FileManager.default
    private let board = NSPasteboard(name: NSPasteboard.Name("robo-pano-\(UUID().uuidString)"))
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("robo-pano-\(UUID().uuidString).json")
    private lazy var store = ClipboardStore(pasteboard: board, fileURL: file)
    private lazy var panel = ClipboardPanelController(store: store)

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    private func after(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }

    private func copy(_ s: String, extra: [String] = [], rtf: Data? = nil) {
        board.clearContents()
        if let rtf { board.setData(rtf, forType: .rtf) }
        board.setString(s, forType: .string)
        for t in extra { board.setString("", forType: NSPasteboard.PasteboardType(t)) }
        store.poll()
    }

    func run() {
        after(60) { print("PANO_ZAMAN_ASIMI"); exit(2) }
        classify()
        capture()
        panelChecks()
    }

    private func classify() {
        let k = ClipClassifier.kind
        check("bağlantılar tanınır", k("https://example.com/a?b=1") == .link && k("www.apple.com") == .link && k("mailto:a@b.co") == .link)
        check("renk kodları tanınır", ["#1E90FF", "#fff", "#11223344", "rgb(30, 144, 255)", "rgba(0,0,0,0.5)", "hsl(210, 100%, 56%)"].allSatisfy { k($0) == .color })
        let code = "func merhaba(_ ad: String) -> String {\n    return \"Merhaba \\(ad)\"\n}"
        check("kod parçası tanınır", k(code) == .code && k("const x = await fetch(url);\nconsole.log(x);") == .code)
        check("düz yazı metin sayılır", k("Merhaba dünya, bugün hava çok güzel.") == .text && k("git status") == .text && k("#hashtag") == .text)
        let c = ClipColor.parse("#1E90FF")
        check("HEX, RGB ve HSL birbirine çevrilir", c?.rgb == "rgb(30, 144, 255)" && c?.hsl == "hsl(210, 100%, 56%)", "\(c?.rgb ?? "") \(c?.hsl ?? "")")
        check("kısa HEX açılır", ClipColor.parse("#fff")?.hex == "#FFFFFF")
        check("HSL'den RGB'ye çevrilir", ClipColor.parse("hsl(0, 100%, 50%)")?.hex == "#FF0000")
    }

    private func capture() {
        store.frontApp = { NSRunningApplication.current }
        copy("ilk kayıt")
        copy("https://example.com")
        check("kopyalanan metin kaydedilir", store.items.count == 2 && store.items[0].kind == .link)
        check("kaynak uygulama kaydedilir", store.items[0].appName != nil && store.items[0].appPath != nil)
        copy("ilk kayıt")
        check("aynı metin yeniden kopyalanınca en üste çıkar, kopya açılmaz", store.items.count == 2 && store.items[0].text == "ilk kayıt")
        copy("gizli parola 1234", extra: ["org.nspasteboard.ConcealedType"])
        copy("geçici", extra: ["org.nspasteboard.TransientType"])
        check("parola yöneticisinin gizli kopyaları kaydedilmez", !store.items.contains { $0.text.contains("parola") || $0.text == "geçici" })
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/dosya.txt") as NSURL])
        store.poll()
        check("Finder'da dosya kopyalamak geçmişe girmez", store.items.count == 2)

        let attr = NSAttributedString(string: "Kalın yazı", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let rtf = attr.rtf(from: NSRange(location: 0, length: attr.length))
        copy("Kalın yazı", rtf: rtf)
        let rich = store.items[0]
        check("biçimli metnin biçimi saklanır", rich.rtf != nil)
        store.write(rich, plain: true)
        check("düz metin yapıştırmada biçim bırakılır", board.data(forType: .rtf) == nil && board.string(forType: .string) == "Kalın yazı")
        store.write(rich, plain: false)
        check("normal yapıştırmada biçim korunur", board.data(forType: .rtf) != nil)
        let count = store.items.count
        store.poll()
        check("kendi yazdığımız kayıt yeniden kaydedilmez", store.items.count == count)

        store.limit = 5
        store.togglePin(store.items.last!)
        for i in 0..<8 { copy("kayıt \(i)") }
        check("sınır aşılınca eskiler silinir, sabitlenen kalır", store.items.count == 6 && store.items.contains { $0.pinned }, "\(store.items.count)")
        store.save()
        let mode = (try? fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) ?? 0
        check("geçmiş yalnızca kullanıcının okuyabildiği dosyaya yazılır", mode == 0o600, String(mode, radix: 8))
        let again = ClipboardStore(pasteboard: board, fileURL: file)
        check("geçmiş uygulama yeniden açılınca geri gelir", again.items.map(\.text) == store.items.map(\.text) && again.items.contains { $0.pinned })
        again.clear(keepPinned: true)
        check("temizleyince yalnızca sabitlenenler kalır", again.items.count == 1 && again.items[0].pinned)
        check("arama Türkçe harflere duyarsızdır", ClipItem(text: "Güneşli gün", kind: .text, date: Date()).matches("gunesli"))
        check("renk aranınca renkler gelir", ClipItem(text: "#123456", kind: .color, date: Date()).matches("renk"))
    }

    private func panelChecks() {
        store.clear(keepPinned: false)
        store.limit = 200
        for s in ["üçüncü", "#FF8800", "birinci"] { copy(s) }
        panel.autoPaste = false
        NSApp.deactivate()
        after(0.3) { [self] in
        let wasActive = NSApp.isActive
        let front = NSWorkspace.shared.frontmostApplication
        panel.show()
        after(0.4) { [self] in
            let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
            check("pano penceresi açılır", panel.isOpen)
            if locked || front == nil {
                print("ATLANDI  klavye ve odak kontrolleri: ekran kilitli, kilitliyken macOS klavyeyi hiçbir pencereye vermez")
            } else {
                check("pano penceresi klavyeyi alır", panel.panel.isKeyWindow)
                check("pencere öndeki uygulamanın odağını çalmaz",
                      panel.panel.styleMask.contains(.nonactivatingPanel) && !wasActive
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier == front?.processIdentifier,
                      "öndeki: \(front?.localizedName ?? "-") → \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-")")
            }
            let f = panel.panel.frame
            check("pencere ekranın içinde açılır", NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(f) })
            panel.handle(key(kVK_DownArrow))
            check("aşağı ok sonraki kayda geçer", panel.state.selection == 1)
            panel.handle(key(kVK_Return))
            check("Enter seçili kaydı panoya yazar", board.string(forType: .string) == "#FF8800")
            after(1.2) { [self] in
                check("seçimden sonra pencere kapanır", !panel.isOpen)
                panel.show()
                panel.state.query = "üçü"
                check("arama listeyi süzer", panel.list.map(\.text) == ["üçüncü"])
                panel.handle(key(kVK_Escape))
                check("Esc pencereyi kapatır", !panel.isOpen)
                panel.show()
                panel.handle(key(kVK_ANSI_3, chars: "3", flags: .command))
                check("⌘3 üçüncü kaydı seçer", board.string(forType: .string) == "üçüncü")
                let combo = ClipShortcut(keyCode: UInt16(kVK_F19), modifiers: [.control, .option, .command], key: "F19")
                panel.setShortcut(combo)
                check("genel kısayol kaydedilir", panel.shortcutWorks)
                panel.setShortcut(nil)
                check("kısayol kaldırılır", !panel.shortcutWorks)
                check("varsayılan kısayol ⇧⌘V", ClipShortcut.standard.label == "⇧⌘V")
                try? fm.removeItem(at: file)
                board.releaseGlobally()
                print(failures == 0 ? "PANO_GECTI" : "PANO_KALDI \(failures)")
                exit(failures == 0 ? 0 : 1)
            }
        }
        }
    }

    private func key(_ code: Int, chars: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: panel.panel.windowNumber,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
    }
}
