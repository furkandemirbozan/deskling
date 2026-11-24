import AppKit
import Carbon
import SwiftUI

/// Odağı çalmadan klavyeyi alabilen yüzer pencere.
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClipPanelState: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
    @Published var selection = 0
    @Published var toast: String?
    @Published var focusTick = 0
}

/// Pano geçmişi penceresi: kısayolla açılır, oklarla gezilir, Enter ile yapıştırılır.
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 470, height: 460)

    let store: ClipboardStore
    let panel: ClipPanel
    let state = ClipPanelState()
    /// Testlerde kapatılır: öndeki uygulamaya ⌘V gönderilmez.
    var autoPaste = true
    private(set) var shortcutWorks = false
    private var monitor: Any?
    private var hotKey: HotKey?

    init(store: ClipboardStore) {
        self.store = store
        panel = ClipPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        // Oluştururken verilen "etkinleştirmeyen pencere" ayarı pencere sunucusuna her zaman ulaşmaz; yeniden uygulanır.
        panel.styleMask.remove(.nonactivatingPanel)
        panel.styleMask.insert(.nonactivatingPanel)
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        let host = NSHostingView(rootView: ClipboardView(store: store, state: state, list: { [weak self] in self?.list ?? [] },
                                                          choose: { [weak self] i, plain in self?.choose(i, plain: plain) },
                                                          close: { [weak self] in self?.close() }))
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        panel.contentView = blur
    }

    // MARK: - Kısayol

    func setShortcut(_ s: ClipShortcut?) {
        hotKey = nil
        guard let s else { shortcutWorks = false; return }
        hotKey = HotKey(s) { [weak self] in self?.toggle() }
        shortcutWorks = hotKey != nil
    }

    // MARK: - Aç / kapat

    var isOpen: Bool { panel.isVisible }

    func toggle() { isOpen ? close() : show() }

    /// İmlecin yanında, ekranın içinde kalacak şekilde açılır; öndeki uygulama etkin kalır.
    func show() {
        state.query = ""
        state.selection = 0
        state.toast = nil
        let m = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame, s = Self.size
        let x = min(max(m.x - s.width / 2, v.minX + 8), v.maxX - s.width - 8)
        let y = min(max(m.y - s.height - 14, v.minY + 8), v.maxY - s.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        state.focusTick += 1
        installMonitor()
    }

    func close() {
        panel.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    // MARK: - Klavye

    var list: [ClipItem] {
        let found = store.items.filter { $0.matches(state.query) }
        return found.filter(\.pinned) + found.filter { !$0.pinned }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            return self.handle(e) ? nil : e
        }
    }

    /// Ok tuşları, Enter, ⇧Enter, Esc, ⌘1-9, ⌘⌫ ve ⌘P. Diğer tuşlar arama kutusuna gider.
    @discardableResult
    func handle(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch Int(e.keyCode) {
        case kVK_DownArrow: move(1); return true
        case kVK_UpArrow: move(-1); return true
        case kVK_Return, kVK_ANSI_KeypadEnter: choose(state.selection, plain: e.modifierFlags.contains(.shift)); return true
        case kVK_Escape: close(); return true
        case kVK_Delete where cmd:
            if state.selection < list.count { store.remove(list[state.selection]); state.selection = min(state.selection, max(0, list.count - 1)) }
            return true
        default: break
        }
        if cmd, let c = e.charactersIgnoringModifiers {
            if let n = Int(c), (1...9).contains(n) { choose(n - 1, plain: e.modifierFlags.contains(.shift)); return true }
            if c.lowercased() == "p", state.selection < list.count { store.togglePin(list[state.selection]); return true }
        }
        return false
    }

    func move(_ d: Int) {
        let n = list.count
        guard n > 0 else { return }
        state.selection = min(max(0, state.selection + d), n - 1)
    }

    /// Kaydı panoya yazar ve (izin varsa) öndeki uygulamaya yapıştırır.
    func choose(_ index: Int, plain: Bool) {
        let items = list
        guard index >= 0, index < items.count else { return }
        store.write(items[index], plain: plain)
        if autoPaste, Paster.trusted {
            close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Paster.pasteToFrontApp() }
        } else {
            state.toast = autoPaste ? "Panoya kopyalandı · ⌘V ile yapıştır" : (plain ? "Düz metin olarak kopyalandı" : "Panoya kopyalandı")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.close() }
        }
    }
}

// MARK: - Görünüm

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var state: ClipPanelState
    let list: () -> [ClipItem]
    let choose: (Int, Bool) -> Void
    let close: () -> Void
    @FocusState private var searching: Bool

    var body: some View {
        let items = list()
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Panoda ara (renk, link, kod…)", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searching)
                Text("\(items.count)").font(.callout).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            Divider()
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text(store.items.isEmpty ? "Henüz kopyalanan bir şey yok" : "Eşleşen kayıt yok").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                ClipRow(item: item, index: i, selected: i == state.selection)
                                    .id(item.id)
                                    .onTapGesture { choose(i, NSEvent.modifierFlags.contains(.shift)) }
                                    .contextMenu { menu(item, i) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: state.selection) { sel in
                        if sel < items.count { proxy.scrollTo(items[sel].id) }
                    }
                }
            }
            Divider()
            footer(items)
        }
        .onAppear { searching = true }
        .onChange(of: state.focusTick) { _ in searching = true }
    }

    @ViewBuilder private func menu(_ item: ClipItem, _ i: Int) -> some View {
        Button("Yapıştır") { choose(i, false) }
        Button("Düz metin olarak yapıştır") { choose(i, true) }
        if let c = ClipColor.parse(item.text) {
            Divider()
            Button("HEX olarak kopyala: \(c.hex)") { copy(c.hex) }
            Button("RGB olarak kopyala: \(c.rgb)") { copy(c.rgb) }
            Button("HSL olarak kopyala: \(c.hsl)") { copy(c.hsl) }
        }
        if item.kind == .link, let url = URL(string: item.text.hasPrefix("www.") ? "https://" + item.text : item.text) {
            Button("Tarayıcıda aç") { NSWorkspace.shared.open(url); close() }
        }
        Divider()
        Button(item.pinned ? "Sabitlemeyi kaldır" : "Sabitle") { store.togglePin(item) }
        Button("Sil") { store.remove(item) }
    }

    private func copy(_ text: String) {
        store.writeText(text)
        state.toast = "\(text) kopyalandı"
    }

    @ViewBuilder private func footer(_ items: [ClipItem]) -> some View {
        HStack(spacing: 10) {
            if let toast = state.toast {
                Label(toast, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
            } else if state.selection < items.count, let c = ClipColor.parse(items[state.selection].text) {
                Circle().fill(Color(nsColor: c.nsColor)).frame(width: 14, height: 14).overlay(Circle().stroke(.secondary.opacity(0.4)))
                ForEach([("HEX", c.hex), ("RGB", c.rgb), ("HSL", c.hsl)], id: \.0) { name, value in
                    Button(name) { copy(value) }.controlSize(.small).help(value)
                }
            } else if state.selection < items.count, items[state.selection].kind == .link {
                Button("Tarayıcıda aç") {
                    let t = items[state.selection].text
                    if let u = URL(string: t.hasPrefix("www.") ? "https://" + t : t) { NSWorkspace.shared.open(u); close() }
                }
                .controlSize(.small)
            }
            Spacer()
            if state.toast == nil {
                Text("↩ yapıştır  ⇧↩ düz metin  ⌘1–9  ⌘P sabitle  ⎋").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 34)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .short
        return f
    }()

    static func ago(_ date: Date) -> String {
        Date().timeIntervalSince(date) < 60 ? "şimdi" : relative.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                if let path = item.appPath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 26, height: 26)
                } else {
                    Image(systemName: "doc.on.clipboard").frame(width: 26, height: 26).foregroundStyle(.secondary)
                }
                if let c = ClipColor.parse(item.text) {
                    Circle().fill(Color(nsColor: c.nsColor)).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                        .offset(x: 3, y: 3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .font(item.kind == .code ? .system(.callout, design: .monospaced) : .callout)
                    .lineLimit(item.kind == .code ? 3 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Image(systemName: item.kind.symbol)
                    Text(item.kind.title)
                    if item.rtf != nil { Text("· biçimli") }
                    if let app = item.appName { Text("· \(app)").lineLimit(1) }
                    Text("· \(Self.ago(item.date))")
                    if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if index < 9 {
                Text("⌘\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.22) : Color.clear))
        .contentShape(Rectangle())
    }
}

/// Ayarlar sekmesindeki kısayol kaydedici: düğmeye bas, yeni tuş birleşimini gir.
struct ShortcutRecorder: View {
    @Binding var shortcut: ClipShortcut
    let onRecording: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Tuşlara bas… (⎋ vazgeç)" : shortcut.label) {
            recording ? stop() : start()
        }
        .font(.system(.body, design: .rounded).weight(.medium))
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        onRecording(true)   // kayıt sırasında eski kısayol pano penceresini açmasın
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if Int(e.keyCode) == kVK_Escape { stop(); return nil }
            if let s = ClipShortcut.from(e) { shortcut = s; stop() } else { NSSound.beep() }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; onRecording(false) }
    }
}
