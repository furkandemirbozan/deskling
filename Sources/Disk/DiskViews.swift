import SwiftUI

/// Denetim panelindeki Disk sekmesi: disk analizi ve bellek.
struct DiskTab: View {
    @ObservedObject var disk: DiskCenter
    @ObservedObject var memory: MemoryCenter
    @AppStorage("diskTabPage") private var page = "disk"

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Label("Disk", systemImage: "internaldrive").tag("disk")
                Label("Bellek", systemImage: "memorychip").tag("memory")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.bottom, 8)
            Divider()
            if page == "memory" { MemoryPage(memory: memory) } else { DiskPage(disk: disk) }
        }
    }
}

// MARK: - Disk

struct DiskPage: View {
    @ObservedObject var disk: DiskCenter
    /// Görüntü almak için kaydırmasız çizilebilir (ImageRenderer kaydırma görünümünü çizmez).
    var scrolls = true
    @State private var filter: DiskVerdict? = nil
    @State private var confirm: [DiskItem]?
    @State private var highlight: String?

    var body: some View {
        Group {
            if scrolls {
                ScrollViewReader { proxy in ScrollView { content(proxy) } }
            } else {
                content(nil)
            }
        }
        .onAppear { disk.refreshVolume() }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Çöp Kutusu'na taşı", role: .destructive) { if let c = confirm { disk.moveToTrash(c) }; confirm = nil }
            Button("Vazgeç", role: .cancel) { confirm = nil }
        } message: {
            Text(confirmMessage)
        }
    }

    private func content(_ proxy: ScrollViewProxy?) -> some View {
                VStack(alignment: .leading, spacing: 14) {
                    VolumeBar(disk: disk)
                    if !disk.scanned && disk.scanning == nil {
                        startCard
                    } else {
                        overview
                        if let k = disk.selectedKind, let list = disk.items[k] {
                            detail(k, list, proxy: proxy)
                        }
                    }
                    if let n = disk.note {
                        Label(n, systemImage: "info.circle.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
    }

    private var confirmTitle: String {
        guard let c = confirm else { return "" }
        return c.count == 1 ? "\"\(c[0].name)\" Çöp Kutusu'na taşınsın mı?" : "\(c.count) öğe Çöp Kutusu'na taşınsın mı?"
    }

    private var confirmMessage: String {
        guard let c = confirm else { return "" }
        let size = DiskFormat.bytes(c.reduce(0) { $0 + $1.size })
        let names = c.prefix(6).map(\.name).joined(separator: ", ") + (c.count > 6 ? " ve \(c.count - 6) tane daha" : "")
        return "\(names)\n\nToplam \(size). Kalıcı olarak silinmez; Çöp Kutusu'ndan geri alabilirsin. Yer, Çöp Kutusu boşaltılınca açılır."
    }

    private var startCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.pie.fill").font(.system(size: 34)).foregroundStyle(.tint)
            Text("Diskte neyin yer kapladığını bul").font(.headline)
            Text("Uygulamalar, önbellekler, indirilenler ve büyük dosyalar taranır. Her biri için ne zaman kullanıldığına, ne zamandır durduğuna ve yeniden oluşturulabilir olup olmadığına bakılır. Tarama hiçbir şeyi silmez.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { disk.scan() } label: { Label("Diski tara", systemImage: "magnifyingglass").frame(minWidth: 140) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("İlk taramada macOS İndirilenler ve Belgeler klasörleri için izin isteyebilir.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    private var overview: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                DonutChart(slices: disk.kinds.map { k in DonutChart.Slice(id: k.rawValue, value: Double(disk.total(k)), color: k.color) },
                           selected: disk.selectedKind?.rawValue) { id in
                    withAnimation(.easeOut(duration: 0.2)) { disk.selectedKind = DiskKind(rawValue: id) }
                }
                .frame(width: 150, height: 150)
                VStack(spacing: 1) {
                    if let s = disk.scanning {
                        ProgressView().controlSize(.small)
                        Text(s.title).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(DiskFormat.bytes(disk.totalRemovable)).font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(DiskVerdict.remove.color)
                        Text("silinebilir").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Spacer()
                    Text("Kaplayan").foregroundStyle(.secondary)
                    Text("Silinebilir").foregroundStyle(DiskVerdict.remove.color)
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 5)
                ForEach(DiskKind.allCases) { k in
                    legendRow(k)
                }
                HStack(spacing: 8) {
                    Button { disk.scan() } label: { Label(disk.scanning == nil ? "Yeniden tara" : "Taranıyor…", systemImage: "arrow.clockwise") }
                        .disabled(disk.scanning != nil)
                    if disk.scanning != nil { Button("Durdur") { disk.cancel() } }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private func legendRow(_ k: DiskKind) -> some View {
        let total = disk.total(k), rem = disk.removable(k)
        let has = disk.items[k] != nil
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { disk.selectedKind = k }
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(k.color).frame(width: 9, height: 9)
                Text(k.title).font(.caption).fontWeight(disk.selectedKind == k ? .semibold : .regular)
                Spacer(minLength: 4)
                if !has { Text("…").font(.caption).foregroundStyle(.tertiary) }
                else {
                    Text(DiskFormat.bytes(total)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if rem > 0 {
                        Text(DiskFormat.bytes(rem)).font(.caption2).monospacedDigit().foregroundStyle(DiskVerdict.remove.color)
                            .help("Silinebilir")
                    }
                }
            }
            .padding(.vertical, 2).padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(disk.selectedKind == k ? k.color.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(total == 0)
        .opacity(has && total == 0 ? 0.45 : 1)
    }

    @ViewBuilder
    private func detail(_ k: DiskKind, _ all: [DiskItem], proxy: ScrollViewProxy?) -> some View {
        let list = filter.map { f in all.filter { $0.verdict == f } } ?? all
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(k.title, systemImage: k.symbol).font(.headline).foregroundStyle(k.color)
                Spacer()
                Picker("", selection: $filter) {
                    Text("Tümü").tag(DiskVerdict?.none)
                    ForEach(DiskVerdict.allCases.reversed(), id: \.self) { v in Text(v.title).tag(Optional(v)) }
                }
                .labelsHidden().frame(width: 130).controlSize(.small)
            }
            Text(k.detail).font(.caption).foregroundStyle(.secondary)
            // Parça parça: her öğe kapladığı yer kadar, kararının rengiyle.
            PieceBar(items: list, highlight: highlight) { item in
                highlight = item.id
                withAnimation { proxy?.scrollTo(item.id, anchor: .center) }
            } reveal: { disk.show([$0]) } trash: { confirm = [$0] }
            .frame(height: 30)
            verdictSummary(all)
            HStack(spacing: 8) {
                Button("Önerilenleri seç") { disk.selectRecommended(in: k) }
                    .disabled(!all.contains { $0.verdict == .remove && $0.canTrash })
                if !disk.selection.isEmpty { Button("Seçimi temizle") { disk.selection = [] } }
                Spacer()
                let sel = disk.selectedItems
                Button(role: .destructive) { confirm = sel } label: {
                    Label(sel.isEmpty ? "Seçilenleri sil" : "\(sel.count) öğeyi sil · \(DiskFormat.bytes(sel.reduce(0) { $0 + $1.size }))",
                          systemImage: "trash")
                }
                .disabled(sel.isEmpty || disk.working)
            }
            .controlSize(.small)
            if list.isEmpty {
                Text(all.isEmpty ? "Bu bölümde yer kaplayan bir şey bulunmadı." : "Bu filtreye uyan öğe yok.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            LazyVStack(spacing: 0) {
                ForEach(list) { item in
                    DiskRow(item: item, selected: disk.selection.contains(item.id), highlighted: highlight == item.id,
                            toggle: { disk.toggle(item) }, reveal: { disk.show([item]) }, trash: { confirm = [item] })
                        .id(item.id)
                    Divider()
                }
            }
            if k == .trash, let t = all.first {
                Button { disk.show([t]) } label: { Label("Çöp Kutusu'nu Finder'da aç", systemImage: "trash") }.controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.035)))
    }

    private func verdictSummary(_ all: [DiskItem]) -> some View {
        HStack(spacing: 12) {
            ForEach(DiskVerdict.allCases.reversed(), id: \.self) { v in
                let s = all.filter { $0.verdict == v }.reduce(Int64(0)) { $0 + $1.size }
                HStack(spacing: 4) {
                    Circle().fill(v.color).frame(width: 7, height: 7)
                    Text("\(v.title) \(DiskFormat.bytes(s))").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Diskin tamamı: kullanılan, temizlenebilir ve boş alan.
struct VolumeBar: View {
    @ObservedObject var disk: DiskCenter

    var body: some View {
        if let v = disk.volume {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Macintosh HD").font(.headline)
                    Spacer()
                    Text("\(DiskFormat.bytes(v.available)) boş · \(DiskFormat.bytes(v.total))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    let w = g.size.width
                    let scale = v.total > 0 ? w / CGFloat(v.total) : 0
                    let kinds = disk.kinds
                    let scanned = kinds.reduce(Int64(0)) { $0 + disk.total($1) }
                    let other = max(0, v.used - scanned)
                    HStack(spacing: 1) {
                        ForEach(kinds) { k in
                            Rectangle().fill(k.color).frame(width: max(1, CGFloat(disk.total(k)) * scale))
                                .help("\(k.title): \(DiskFormat.bytes(disk.total(k)))")
                                .onTapGesture { disk.selectedKind = k }
                        }
                        Rectangle().fill(Color.secondary.opacity(0.55)).frame(width: max(0, CGFloat(other) * scale))
                            .help("Sistem ve diğer: \(DiskFormat.bytes(other))")
                        Rectangle().fill(Color.primary.opacity(0.08))
                            .help("Boş: \(DiskFormat.bytes(v.available))")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 16)
                HStack(spacing: 10) {
                    legend(Color.secondary.opacity(0.55), "Sistem ve diğer")
                    legend(Color.primary.opacity(0.12), "Boş")
                    if v.purgeable > 0 {
                        Text("\(DiskFormat.bytes(v.purgeable)) macOS'un gerektiğinde kendisi boşalttığı alan")
                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8); Text(t).font(.caption2).foregroundStyle(.secondary) }
    }
}

/// Bölümleri gösteren halka grafik; dilimlere tıklanabilir.
struct DonutChart: View {
    struct Slice: Identifiable { let id: String; let value: Double; let color: Color }
    let slices: [Slice]
    let selected: String?
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        GeometryReader { g in
            let total = max(slices.reduce(0) { $0 + $1.value }, 1)
            let side = min(g.size.width, g.size.height)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.07), lineWidth: side * 0.17).padding(side * 0.09)
                ForEach(Array(slices.enumerated()), id: \.element.id) { idx, s in
                    let start = slices.prefix(idx).reduce(0) { $0 + $1.value } / total
                    let end = start + s.value / total
                    let on = selected == s.id
                    Ring(start: start, end: end, thickness: on ? 0.27 : 0.2)
                        .fill(s.color.opacity(selected == nil || on ? 1 : 0.55))
                        .onTapGesture { onSelect(s.id) }
                }
            }
            .frame(width: side, height: side)
        }
    }

    struct Ring: Shape {
        var start: Double
        var end: Double
        var thickness: CGFloat
        var animatableData: AnimatablePair<Double, Double> {
            get { AnimatablePair(start, end) }
            set { start = newValue.first; end = newValue.second }
        }

        func path(in rect: CGRect) -> Path {
            let r = min(rect.width, rect.height) / 2
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let inner = r * (1 - thickness)
            let gap = end - start > 0.01 ? 0.004 : 0
            let a0 = Angle(degrees: (start + gap) * 360 - 90), a1 = Angle(degrees: (end - gap) * 360 - 90)
            var p = Path()
            p.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: false)
            p.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
            p.closeSubpath()
            return p
        }
    }
}

/// Bir bölümün öğelerini kapladıkları yer kadar genişlikte parçalara böler.
struct PieceBar: View {
    let items: [DiskItem]
    let highlight: String?
    var select: (DiskItem) -> Void
    var reveal: (DiskItem) -> Void
    var trash: (DiskItem) -> Void
    static let maxPieces = 24

    var body: some View {
        GeometryReader { g in
            let shown = Array(items.sorted { $0.size > $1.size }.prefix(Self.maxPieces))
            let rest = items.count > shown.count ? items.sorted { $0.size > $1.size }.dropFirst(Self.maxPieces).reduce(Int64(0)) { $0 + $1.size } : 0
            let total = CGFloat(max(1, shown.reduce(Int64(0)) { $0 + $1.size } + rest))
            let spacing: CGFloat = 2
            let usable = g.size.width - spacing * CGFloat(shown.count + (rest > 0 ? 1 : 0))
            HStack(spacing: spacing) {
                ForEach(shown) { item in
                    let w = max(4, usable * CGFloat(item.size) / total)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(item.verdict.color.gradient)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary, lineWidth: highlight == item.id ? 2 : 0))
                        .overlay(alignment: .leading) {
                            if w > 70 {
                                Text(item.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 4)
                            }
                        }
                        .frame(width: w)
                        .help("\(item.name) · \(DiskFormat.bytes(item.size)) · \(item.verdict.title)")
                        .onTapGesture { select(item) }
                        .contextMenu {
                            Button("Finder'da göster") { reveal(item) }
                            if item.canTrash { Button("Çöp Kutusu'na taşı…") { trash(item) } }
                        }
                }
                if rest > 0 {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.35))
                        .help("Diğer \(items.count - shown.count) öğe · \(DiskFormat.bytes(rest))")
                }
            }
        }
    }
}

struct DiskRow: View {
    let item: DiskItem
    let selected: Bool
    let highlighted: Bool
    var toggle: () -> Void
    var reveal: () -> Void
    var trash: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(!item.canTrash)
                .opacity(item.canTrash ? 1 : 0.25)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    VerdictBadge(verdict: item.verdict)
                }
                Text(item.reasons.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 6)
            Text(DiskFormat.bytes(item.size)).font(.callout).monospacedDigit()
            Button(action: reveal) { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless).help("Finder'da göster")
            Button(action: trash) { Image(systemName: "trash") }.buttonStyle(.borderless).help("Çöp Kutusu'na taşı")
                .disabled(!item.canTrash).opacity(item.canTrash ? 1 : 0.25)
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(highlighted ? Color.accentColor.opacity(0.12) : .clear))
        .contextMenu {
            Button("Finder'da göster", action: reveal)
            if item.canTrash { Button("Çöp Kutusu'na taşı…", action: trash) }
        }
    }
}

struct VerdictBadge: View {
    let verdict: DiskVerdict
    var title: String? = nil
    var symbol: String? = nil
    var body: some View {
        Label(title ?? verdict.title, systemImage: symbol ?? verdict.symbol)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(verdict.color.opacity(0.18)))
            .foregroundStyle(verdict.color)
            .fixedSize()
    }
}

// MARK: - Bellek

struct MemoryPage: View {
    @ObservedObject var memory: MemoryCenter
    var scrolls = true
    @State private var confirm: [AppMemory]?

    var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .onAppear { if scrolls { memory.activate() } }
        .onDisappear { if scrolls { memory.deactivate() } }
        .alert(confirm.map { $0.count == 1 ? "\($0[0].name) kapatılsın mı?" : "\($0.count) uygulama kapatılsın mı?" } ?? "",
               isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Kapat", role: .destructive) { if let c = confirm { memory.quit(c) }; confirm = nil }
            Button("Vazgeç", role: .cancel) { confirm = nil }
        } message: {
            if let c = confirm {
                Text(c.map(\.name).joined(separator: ", ") + "\n\nYaklaşık \(DiskFormat.bytes(Int64(c.reduce(0) { $0 + $1.footprint })) ) bellek boşalır.")
            }
        }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 14) {
                if let s = memory.stats { MemoryBar(stats: s) } else { ProgressView().frame(maxWidth: .infinity) }
                actions
                if let n = memory.note { Label(n, systemImage: "info.circle.fill").font(.caption).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Açık uygulamalar").font(.headline).padding(.bottom, 6)
                    ForEach(memory.apps) { a in
                        MemoryRow(app: a) { confirm = [a] }
                        Divider()
                    }
                }
                Text("macOS boş belleği dosya önbelleği olarak kullanır; \"dolu\" görünmesi kendi başına sorun değildir. Bilgisayarı asıl rahatlatan, uzun süredir kullanmadığın ağır uygulamaları kapatmaktır. Uygulamalar nazikçe kapatılır; kaydedilmemiş belge varsa uygulama sana sorar.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(16)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            let s = memory.suggested
            Button { confirm = s } label: {
                Label(s.isEmpty ? "Kapatılacak ağır uygulama yok" : "Belleği temizle · \(s.count) uygulama, \(DiskFormat.bytes(Int64(memory.suggestedBytes)))",
                      systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(s.isEmpty)
            Button { memory.purge() } label: {
                if memory.purging { ProgressView().controlSize(.small) } else { Label("Önbelleği boşalt", systemImage: "wind") }
            }
            .help("macOS'un purge aracıyla dosya önbelleğini boşaltır; yönetici parolası sorulur. Etkisi geçicidir.")
            .disabled(memory.purging)
        }
        .controlSize(.small)
    }
}

struct MemoryBar: View {
    let stats: MemoryStats

    var body: some View {
        let parts: [(String, UInt64, Color)] = [
            ("Uygulamalar", stats.app, Color(red: 0.25, green: 0.52, blue: 0.96)),
            ("Kablolu", stats.wired, Color(red: 0.93, green: 0.42, blue: 0.30)),
            ("Sıkıştırılmış", stats.compressed, Color(red: 0.98, green: 0.72, blue: 0.20)),
            ("Önbellek", stats.cached, Color(red: 0.55, green: 0.70, blue: 0.85)),
        ]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bellek").font(.headline)
                Text(stats.pressureTitle).font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(pressureColor.opacity(0.18))).foregroundStyle(pressureColor)
                Spacer()
                Text("\(DiskFormat.bytes(Int64(stats.used))) / \(DiskFormat.bytes(Int64(stats.total)))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { g in
                let scale = stats.total > 0 ? g.size.width / CGFloat(stats.total) : 0
                HStack(spacing: 1) {
                    ForEach(parts, id: \.0) { p in
                        Rectangle().fill(p.2).frame(width: max(0, CGFloat(p.1) * scale)).help("\(p.0): \(DiskFormat.bytes(Int64(p.1)))")
                    }
                    Rectangle().fill(Color.primary.opacity(0.08)).help("Boş: \(DiskFormat.bytes(Int64(stats.free)))")
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 16)
            HStack(spacing: 10) {
                ForEach(parts, id: \.0) { p in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(p.2).frame(width: 8, height: 8)
                        Text("\(p.0) \(DiskFormat.bytes(Int64(p.1)))").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if stats.swapUsed > 0 {
                Text("Takas: \(DiskFormat.bytes(Int64(stats.swapUsed))) diske yazılmış. Bu büyüdükçe bilgisayar yavaşlar.")
                    .font(.caption2).foregroundStyle(stats.swapUsed > 2 << 30 ? .orange : .secondary)
            }
        }
    }

    private var pressureColor: Color {
        switch stats.pressure {
        case 4: return DiskVerdict.remove.color
        case 2: return DiskVerdict.review.color
        default: return DiskVerdict.keep.color
        }
    }
}

struct MemoryRow: View {
    let app: AppMemory
    var quit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let img = NSRunningApplication(processIdentifier: app.pid)?.icon { Image(nsImage: img).resizable() }
                else { Image(systemName: "app") }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).lineLimit(1)
                    VerdictBadge(verdict: app.verdict, title: app.verdict == .remove ? "Kapatılabilir" : nil,
                                 symbol: app.verdict == .remove ? "xmark.circle.fill" : nil)
                }
                Text(app.reasons.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(DiskFormat.bytes(Int64(app.footprint))).font(.callout).monospacedDigit()
            Button("Kapat", action: quit).controlSize(.small).disabled(app.verdict == .keep)
        }
        .padding(.vertical, 5)
    }
}
