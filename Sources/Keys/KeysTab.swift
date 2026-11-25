import SwiftUI

/// Denetim panelindeki Klavye sekmesi.
struct KeysTab: View {
    @ObservedObject var keys: KeySoundCenter
    @State private var tryText = ""
    @State private var localMonitor: Any?

    var body: some View {
        Form {
            Section {
                Toggle("Klavye sesleri", isOn: $keys.enabled)
                if keys.enabled && !keys.permission {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Tuşları duyabilmek için macOS'un Giriş İzleme izni gerekiyor. Deskling yalnızca hangi tuşa basıldığını anlar; yazdığını okumaz, saklamaz.",
                              systemImage: "keyboard.badge.ellipsis")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Giriş İzleme izni ver") { keys.requestPermission() }
                    }
                }
                if keys.enabled && keys.permission && !keys.listening {
                    Label("İzin var ama tuş dinleme başlatılamadı. Deskling'i menüden kapatıp yeniden açmayı dene.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else if keys.enabled && keys.listening {
                    Label("Tuşlar dinleniyor.", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                if keys.enabled && keys.muteWithMic && keys.micActive {
                    Label("Mikrofon kullanılıyor; sesler şimdilik sustu.", systemImage: "mic.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Ses düzeyi") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $keys.volume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                TextField("Burada yazıp deneyebilirsin", text: $tryText)
            }

            Section {
                ForEach(keys.packs) { p in PackRow(pack: p, selected: p.id == keys.selectedID) { keys.select(p.id) } preview: {
                    if p.id == keys.selectedID { keys.preview() } else { keys.select(p.id, turnOn: false) }
                } }
            } header: {
                HStack {
                    Text("Ses paketleri (\(keys.packs.count))")
                    Spacer()
                    if keys.loading { ProgressView().controlSize(.small) }
                }
            }

            Section("Paket klasörü") {
                Text(keys.folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Mechvibes'tan indirdiğin zip'leri bu klasöre at; Deskling kendiliğinden okur. Zip'ler olduğu gibi kalır, Deskling kendi kopyasını açar.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Finder'da aç") { keys.revealFolder() }
                    Button("Değiştir…") { chooseFolder() }
                    Button("Yeniden oku") { keys.rescan() }
                    Spacer()
                    Button("Mechvibes'ta paket bul") { NSWorkspace.shared.open(URL(string: "https://mechvibes.com/sound-packs?sort=downloads")!) }
                }
                .controlSize(.small)
                if keys.duplicates > 0 {
                    Label("Aynı paketin \(keys.duplicates) kopyası atlandı; her paket bir kez listelenir.", systemImage: "square.on.square")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(keys.problems, id: \.self) { p in
                    Label(p, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Ayarlar") {
                Toggle("Tuşu bırakınca da ses çıksın", isOn: $keys.release)
                Toggle("Stereo: sol tuşlar soldan, sağdakiler sağdan", isOn: $keys.stereo)
                Toggle("Doğal çeşitlilik (her basış biraz farklı)", isOn: $keys.variation)
                Toggle("Mikrofon kullanılırken sustur", isOn: $keys.muteWithMic)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: startTrying)
        .onDisappear(perform: stopTrying)
    }

    /// İzin olmasa da panelde yazarken sesler duyulsun.
    private func startTrying() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { e in
            if !keys.listening, !e.isARepeat || e.type == .keyUp, let code = KeyCodes.mac[e.keyCode] {
                keys.play(code, down: e.type == .keyDown)
            }
            return e
        }
    }

    private func stopTrying() {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        localMonitor = nil
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = keys.folder.deletingLastPathComponent()
        p.prompt = "Seç"
        if p.runModal() == .OK, let u = p.url { keys.setFolder(u) }
    }
}

private struct PackRow: View {
    let pack: SoundPackInfo
    let selected: Bool
    var choose: () -> Void
    var preview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pack.name).lineLimit(1)
                    if pack.builtin { badge("Dahili", .blue) }
                    if let l = pack.licenseTitle { badge(l, l == "Kişisel kullanım" ? .orange : .green) }
                }
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button(action: preview) { Image(systemName: "play.circle") }.buttonStyle(.borderless).help("Dinle")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: choose)
    }

    private var detail: String {
        var parts: [String] = []
        if !pack.author.isEmpty { parts.append(pack.author) }
        if pack.builtin { parts.append(pack.description) } else { parts.append("\(pack.keyCount) tuş") }
        if pack.hasRelease { parts.append("bırakma sesi var") }
        return parts.joined(separator: " · ")
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(c.opacity(0.16))).foregroundStyle(c)
    }
}
