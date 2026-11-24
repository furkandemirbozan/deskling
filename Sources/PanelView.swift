import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case found = "Bulunanlar", history = "Geçmiş", ports = "Portlar", settings = "Ayarlar"
    var id: String { rawValue }
}

struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $model.panelTab) {
                ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch model.panelTab {
                case .found: FoundTab(model: model)
                case .history: HistoryTab(model: model)
                case .ports: PortsTab(dev: model.dev)
                case .settings: SettingsTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let m = model.message {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(m).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.message = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Kapat")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
        }
        .frame(minWidth: 440, idealWidth: 460, minHeight: 560, idealHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: RobotArt.appIcon(54))
                .resizable()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.statusTitle).font(.title3.weight(.semibold))
                HStack(spacing: 10) {
                    Label("%\(model.battery)", systemImage: batterySymbol)
                        .foregroundStyle(model.battery < 20 ? Color.red : Color.secondary)
                    Text(model.statusDetail).foregroundStyle(.secondary)
                }
                .font(.callout)
                .monospacedDigit()
            }
            Spacer()
            if model.busy {
                Button { model.togglePause() } label: {
                    Image(systemName: model.paused ? "play.fill" : "pause.fill").frame(width: 18, height: 18)
                }
                .help(model.paused ? "Devam et" : "Duraklat")
                Button { model.goHome() } label: {
                    Image(systemName: "house.fill").frame(width: 18, height: 18)
                }
                .help("Görevi bitir ve istasyona dön")
            }
        }
        .controlSize(.large)
        .padding(16)
    }

    private var batterySymbol: String {
        switch model.battery {
        case 76...: return "battery.100"
        case 40...: return "battery.75"
        case 15...: return "battery.25"
        default: return "battery.0"
        }
    }
}

// MARK: - Bulunanlar

struct FoundTab: View {
    @ObservedObject var model: AppModel

    private var selectable: [Shot] { model.visibleShots.filter { !model.protected.contains($0.id) } }
    private var count: Int { model.selected.count }

    var body: some View {
        VStack(spacing: 0) {
            if model.visibleShots.isEmpty {
                empty
            } else {
                HStack {
                    Text("\(model.visibleShots.count) ekran görüntüsü").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(count == selectable.count ? "Seçimi kaldır" : "Tümünü seç") {
                        model.selected = count == selectable.count ? [] : Set(selectable.map(\.id))
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleShots) { shot in
                            ShotRow(model: model, shot: shot)
                            Divider().padding(.leading, 104)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Demoyu izle") { model.runDemo() }
                    .disabled(model.busy)
                    .help("Sahte kartlarla gösterim yapar, dosyalarına dokunmaz")
                Button("Toz haznesini aç") { model.openCollection() }
                Spacer()
                Button {
                    model.cleanSelected()
                } label: {
                    Text(count > 0 ? "\(count) görüntüyü topla" : "Topla").frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .disabled(count == 0 || model.busy)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(12)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Masaüstü tertemiz").font(.headline)
            Text("Yeni ekran görüntüsü alındığında burada görünür.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ShotRow: View {
    @ObservedObject var model: AppModel
    let shot: Shot

    private var isProtected: Bool { model.protected.contains(shot.id) }
    private var isOn: Binding<Bool> {
        Binding(get: { model.selected.contains(shot.id) },
                set: { if $0 { model.selected.insert(shot.id) } else { model.selected.remove(shot.id) } })
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: isOn).labelsHidden().disabled(isProtected)
            Group {
                if let img = model.thumbs[shot.id] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 58, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(shot.name).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { model.toggleProtect(shot) } label: {
                Image(systemName: isProtected ? "lock.fill" : "lock.open")
                    .foregroundStyle(isProtected ? Color.orange : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isProtected ? "Korumayı kaldır" : "Koru: robot bu dosyaya dokunmaz")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .opacity(isProtected ? 0.6 : 1)
    }

    private var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: shot.size, countStyle: .file)
        let date = shot.created.formatted(.relative(presentation: .named).locale(Locale(identifier: "tr_TR")))
        return "\(date) · \(size) · \(shot.evidence.rawValue)"
    }
}

// MARK: - Geçmiş

struct HistoryTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.history.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "clock").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("Henüz temizlik yapılmadı").font(.headline)
                Text("Taşınan her dosya burada listelenir ve geri alınabilir.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.history) { r in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).lineLimit(1).truncationMode(.middle)
                                Text(r.date.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "tr_TR"))))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if r.restored {
                                Text("Geri alındı").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("Geri al") { model.restore(r) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }
}

// MARK: - Ayarlar

struct SettingsTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Temizleme", selection: $model.mode) {
                    ForEach(CleanMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if model.mode == .automatic {
                    Stepper("En az \(model.minAge) dakikalık görüntüler", value: $model.minAge, in: 1...1440, step: 5)
                    Text("Bu süreyi dolduran ve kilitli olmayan görüntüler sorulmadan toz haznesine toplanır.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Hız") {
                    Slider(value: $model.speed, in: 120...480, step: 20)
                }
                Stepper("Hazne: \(model.capacity) görüntü", value: $model.capacity, in: 1...10)
            }
            Section("Kar") {
                Toggle("Kar yağsın", isOn: $model.snowEnabled)
                LabeledContent("Yoğunluk") {
                    Slider(value: $model.snowIntensity, in: 0...1)
                }
                .disabled(!model.snowEnabled)
                LabeledContent("Birikme sınırı") {
                    Slider(value: $model.snowLimit, in: 0.4...1.6)
                }
                .disabled(!model.snowEnabled)
                Toggle("Kar küreme aracı", isOn: $model.snowPlowEnabled)
                    .disabled(!model.snowEnabled)
                Toggle("Fareyle kar topu yapılsın", isOn: $model.snowSculpt)
                    .disabled(!model.snowEnabled)
                if model.snowSculpt, model.snowEnabled {
                    Text("Biriken karı sol tıkla tutup sürükle, top büyüsün. Topları üst üste koy, kardan adam olsun. Sağ tıkla süsle.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Kara delik") {
                Toggle("Kara deliği göster", isOn: $model.holeEnabled)
                Toggle("İşlemden sonra orijinali Çöp Sepeti'ne taşı", isOn: $model.holeTrashOriginal)
                    .disabled(!model.holeEnabled)
                Picker("Görsel biçimi", selection: $model.holeImageFormat) {
                    ForEach(HoleSettings.Format.allCases, id: \.rawValue) { f in
                        Text(f == .webp && HoleTools.cwebp == nil ? "WebP (cwebp gerekli)" : f.title).tag(f.rawValue)
                    }
                }
                .disabled(!model.holeEnabled)
                Picker("Kalite", selection: $model.holeQuality) {
                    ForEach(HoleSettings.Quality.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(!model.holeEnabled)
                Toggle("Fotoğraflardan konum bilgisini sil", isOn: $model.holeStripLocation)
                    .disabled(!model.holeEnabled)
                Text("Görsel, PDF ve video bırak: sıkışır, birden çok PDF birleşir. Klasör ZIP olur, JSON düzenlenir, CSV JSON'a dönüşür. Shift ile arşiv açılır, PDF sayfalara ayrılır, görseller PDF olur, videonun sesi ayrılır ya da sessiz kısa video GIF olur. Option ile Çöp Sepeti'ne gider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ClipboardSettings(model: model, store: model.clipboard)
            Section("Halı") {
                Toggle("Halıyı göster", isOn: $model.rugVisible)
                LabeledContent("Boyut") {
                    HStack(spacing: 10) {
                        Slider(value: $model.rugScale, in: RugView.scaleRange, step: 0.1)
                        Text("%\(Int((model.rugScale * 100).rounded()))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!model.rugVisible)
            }
            Section {
                Toggle("Mac açılınca başlat", isOn: $model.launchAtLogin)
                Toggle("Çarptığı simgeleri itsin", isOn: $model.bumpIcons)
                Toggle("Sesler", isOn: $model.sounds)
            }
        }
        .formStyle(.grouped)
    }
}

/// Ayarlar sekmesindeki Pano bölümü.
struct ClipboardSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: ClipboardStore
    @State private var trusted = Paster.trusted

    var body: some View {
        Section("Pano") {
            Toggle("Pano geçmişini tut", isOn: $model.clipEnabled)
            LabeledContent("Kısayol") {
                HStack(spacing: 8) {
                    if !model.clipShortcutWorks {
                        Label("Başka bir uygulama kullanıyor", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.caption)
                    }
                    ShortcutRecorder(shortcut: $model.clipShortcut) { model.onShortcutRecording?($0) }
                }
            }
            .disabled(!model.clipEnabled)
            Stepper("En fazla \(model.clipLimit) kayıt", value: $model.clipLimit, in: 50...1000, step: 50)
                .disabled(!model.clipEnabled)
            LabeledContent("Otomatik yapıştırma") {
                if trusted {
                    Label("Açık", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("İzin ver") { Paster.requestAccess() }
                }
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in trusted = Paster.trusted }
            HStack {
                Text("\(store.items.count) kayıt").foregroundStyle(.secondary)
                Spacer()
                Button("Geçmişi temizle") { store.clear(keepPinned: true) }
                    .disabled(store.items.isEmpty)
                    .help("Sabitlenen kayıtlar kalır")
            }
            Text("Parola yöneticilerinin gizli işaretlediği kopyalar kaydedilmez. Geçmiş yalnızca bu Mac'te, yalnızca senin okuyabildiğin bir dosyada tutulur. Otomatik yapıştırma için Erişilebilirlik izni gerekir; izin yoksa seçtiğin kayıt panoya kopyalanır.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
