import AppKit

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }

    static func == (a: ShelfItem, b: ShelfItem) -> Bool { a.url == b.url }
}

/// Çentiğe sürüklenen dosyaların listesi. Dosyalar taşınmaz ve kopyalanmaz; raf yalnızca yollarını hatırlar.
final class ShelfStore: ObservableObject {
    static let limit = 30
    static let key = "islandShelf"
    @Published private(set) var items: [ShelfItem] = []
    private let store: UserDefaults?

    init(store: UserDefaults?) {
        self.store = store
        let paths = store?.stringArray(forKey: Self.key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { ShelfItem(url: $0) }
    }

    /// Var olan dosyaları rafın başına ekler; aynısı yeniden gelirse öne çıkar. Eklenen yeni dosya sayısını döner.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for raw in urls.reversed() {
            let url = raw.standardizedFileURL
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { continue }
            if let i = items.firstIndex(where: { $0.url == url }) {
                items.insert(items.remove(at: i), at: 0)
            } else {
                items.insert(ShelfItem(url: url), at: 0)
                added += 1
            }
        }
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        save()
        return added
    }

    /// Yalnızca raftan kaldırır; dosyaya dokunmaz.
    func remove(_ item: ShelfItem) {
        items.removeAll { $0.url == item.url }
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Bu arada silinen ya da taşınan dosyalar raftan düşer.
    func prune() {
        let before = items.count
        items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        if items.count != before { save() }
    }

    private func save() { store?.set(items.map(\.url.path), forKey: Self.key) }

    // MARK: Eylemler

    static func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }
    static func reveal(_ items: [ShelfItem]) { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url)) }

    static func airDrop(_ items: [ShelfItem]) {
        guard !items.isEmpty, let s = NSSharingService(named: .sendViaAirDrop) else { return }
        let urls = items.map(\.url)
        if s.canPerform(withItems: urls) { s.perform(withItems: urls) }
    }

    static func icon(_ item: ShelfItem) -> NSImage {
        let i = NSWorkspace.shared.icon(forFile: item.url.path)
        i.size = NSSize(width: 64, height: 64)
        return i
    }
}
