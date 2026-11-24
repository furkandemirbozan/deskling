import SwiftUI

/// Denetim panelindeki Ada sekmesi.
struct IslandTab: View {
    @ObservedObject var island: IslandManager
    @ObservedObject var settings: IslandSettings
    @ObservedObject var media: NowPlaying

    init(island: IslandManager) {
        self.island = island
        settings = island.settings
        media = island.media
    }

    var body: some View {
        Form {
            Section {
                Toggle("Dinamik Ada", isOn: $settings.enabled)
                Text(screenInfo).font(.caption).foregroundStyle(.secondary)
            }
            Section("Davranış") {
                Toggle("Fare çentiğe gelince açılsın", isOn: $settings.hoverOpen)
                LabeledContent("Açılma gecikmesi") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.hoverDelay, in: IslandSettings.hoverDelayRange, step: 0.05)
                        Text(String(format: "%.2f sn", settings.hoverDelay)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                .disabled(!settings.hoverOpen)
                Toggle("Açılırken dokunsal geri bildirim", isOn: $settings.haptics)
                Toggle("İkinci etkinlik ayrı baloncukta", isOn: $settings.secondary)
                Toggle("Tam ekran uygulamalarda gizlensin", isOn: $settings.hideFullscreen)
                Toggle("Çentiksiz ekranda da göster", isOn: $settings.noNotch)
                Toggle("Zamanlayıcı bitince ses çal", isOn: $settings.timerSound)
            }
            .disabled(!settings.enabled)
            Section("Etkinlikler") {
                ForEach(IslandFeature.allCases) { f in
                    Toggle(isOn: Binding(get: { settings.isOn(f) }, set: { settings.set(f, $0) })) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.title)
                                Text(f.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: f.symbol) }
                    }
                }
            }
            .disabled(!settings.enabled)
            Section("Dene") {
                HStack(spacing: 8) {
                    Button("Adayı aç") { island.expand(page: .home) }
                    Button("1 dk zamanlayıcı") { island.startTimer(minutes: 1) }
                    Button("Şarj göster") {
                        let s = island.power ?? PowerState(percent: 80, charging: true, plugged: true)
                        island.show(.power(PowerState(percent: s.percent, charging: true, plugged: true), .plugged), seconds: 3)
                    }
                }
                .disabled(!settings.enabled)
                Text("Müzik, Spotify ya da tarayıcıyı ilk kez okuduğunda macOS, Deskling'in o uygulamayı yönetmesine izin isteyecek. Tarayıcıda YouTube Music, YouTube, Spotify, SoundCloud, Apple Music ve Deezer sekmeleri okunur; diğer sekmelere bakılmaz. Chrome, Brave, Edge, Vivaldi, Opera, Arc ve Safari'de \"Apple Events'ten JavaScript'e izin ver\" açıksa kapak, süre ve konum da gelir; kapalıysa yalnızca sekme başlığı okunur. Firefox'ta pencere başlığı Erişilebilirlik izniyle okunur.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(media.browserHints, id: \.self) { hint in
                    Label("Tarayıcı müziği için bir kez aç: \(hint)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if media.needsAccessibility {
                    Button("Firefox ve medya tuşları için Erişilebilirlik izni iste") { Paster.requestAccess() }
                }
                if media.browserStatus.values.contains(.denied) {
                    Label("Tarayıcıyı okuma izni reddedildi. Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon → Deskling altından açabilirsin.",
                          systemImage: "hand.raised.fill").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var screenInfo: String {
        let g = island.geometry
        if !island.hasScreen { return "Çentikli ekran bulunamadı. Çentiksiz ekranda göstermek için aşağıdaki ayarı aç." }
        return g.hasNotch ? "Çentik bulundu: \(Int(g.notch.width)) × \(Int(g.notch.height)) pt. Ada çentiğin içinden açılır."
                          : "Bu ekranda çentik yok; ada menü çubuğunun ortasında durur."
    }
}
