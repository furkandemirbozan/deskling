import SwiftUI

/// Denetim panelindeki Portlar sekmesi: dinlenen portlar ve Docker konteynerleri.
struct PortsTab: View {
    @ObservedObject var dev: DevCenter
    @State private var query = ""
    @State private var confirm: ListeningPort?

    private var ports: [ListeningPort] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return dev.visiblePorts }
        return dev.visiblePorts.filter {
            String($0.port).contains(q) || $0.displayName.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q)
        }
    }

    private var containers: [DockerContainer] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return dev.containers }
        return dev.containers.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.image.localizedCaseInsensitiveContains(q) || $0.ports.contains { String($0).contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Port, uygulama ya da konteyner ara", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
                Toggle("Sistem", isOn: $dev.showSystem)
                    .toggleStyle(.checkbox)
                    .help("macOS servislerinin portlarını da göster (\(dev.hiddenSystemCount))")
                Button { dev.refresh() } label: {
                    if dev.loading { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
                    else { Image(systemName: "arrow.clockwise").frame(width: 16, height: 16) }
                }
                .buttonStyle(.borderless)
                .help("Yenile")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Dinlenen portlar", count: ports.count)
                    if ports.isEmpty {
                        placeholder(dev.updated == nil ? "Portlar taranıyor…" : (query.isEmpty ? "Şu an dinlenen bir port yok." : "Eşleşen port yok."))
                    }
                    ForEach(ports) { p in
                        PortRow(dev: dev, port: p) { confirm = p }
                        Divider().padding(.leading, 16)
                    }
                    sectionHeader("Docker", count: dev.docker == .ready ? containers.count : nil)
                    dockerSection
                }
            }
            Divider()
            HStack {
                if let note = dev.note {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(note).font(.caption).lineLimit(2)
                    Spacer()
                    Button { dev.note = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                } else {
                    Text(dev.updated.map { "Son tarama \(Self.time.string(from: $0))" } ?? " ")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Text("Sekme açıkken 4 saniyede bir yenilenir").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
        .onAppear { dev.activate() }
        .onDisappear { dev.deactivate() }
        .confirmationDialog(confirm.map { "\($0.displayName) kapatılsın mı?" } ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            if let p = confirm {
                Button("Kapat", role: .destructive) { dev.kill(p) }
            }
        } message: {
            Text("Bu bir macOS servisi. Kapatırsan macOS onu genellikle yeniden başlatır.")
        }
    }

    @ViewBuilder private var dockerSection: some View {
        switch dev.docker {
        case .unknown:
            placeholder("Docker kontrol ediliyor…")
        case .notInstalled:
            placeholder("Docker kurulu değil.")
        case .notRunning(let reason):
            HStack {
                Image(systemName: "shippingbox").foregroundStyle(.secondary)
                Text(reason).foregroundStyle(.secondary)
                Spacer()
                Button("Docker'ı başlat") { dev.openDocker() }
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        case .ready:
            if containers.isEmpty { placeholder(query.isEmpty ? "Konteyner yok." : "Eşleşen konteyner yok.") }
            ForEach(containers) { c in
                ContainerRow(dev: dev, container: c)
                Divider().padding(.leading, 16)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let count { Text("\(count)").font(.caption).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

struct PortRow: View {
    @ObservedObject var dev: DevCenter
    let port: ListeningPort
    let confirmSystem: () -> Void

    private var icon: NSImage {
        if let path = port.appPath { return NSWorkspace.shared.icon(forFile: path) }
        return NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(":\(String(port.port))")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 66, alignment: .leading)
            Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(port.displayName).font(.callout.weight(.medium)).lineLimit(1)
                    Text(port.localOnly ? "yalnızca bu Mac" : "ağa açık")
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(port.localOnly ? Color.green.opacity(0.15) : Color.orange.opacity(0.18)))
                        .foregroundStyle(port.localOnly ? Color.green : Color.orange)
                        .help(port.localOnly ? "Yalnızca bu bilgisayardan bağlanılabilir" : "Aynı ağdaki başka cihazlar da bağlanabilir")
                }
                Text(port.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button { dev.open(port.port) } label: { Image(systemName: "safari") }
                .buttonStyle(.borderless)
                .help("http://localhost:\(String(port.port)) adresini tarayıcıda aç")
            if dev.working.contains(port.id) {
                ProgressView().controlSize(.small).frame(width: 18)
            } else if dev.stubborn.contains(port.id) {
                Button("Zorla kapat") { dev.kill(port, force: true) }
                    .controlSize(.small)
                    .tint(.red)
            } else {
                Button { port.isSystem ? confirmSystem() : dev.kill(port) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(port.killable ? Color.red.opacity(0.85) : Color.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!port.killable)
                .help(port.killable ? "Portu boşalt: \(port.displayName) kapatılır" : "Bu süreç başka bir kullanıcıya ait")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .help(port.hint)
        .contextMenu {
            Button("Tarayıcıda aç") { dev.open(port.port) }
            Button("Adresi kopyala") { dev.copyURL(port.port) }
            if port.cwd != nil { Button("Klasörü Finder'da göster") { dev.reveal(port) } }
            Divider()
            Button("Kapat") { port.isSystem ? confirmSystem() : dev.kill(port) }.disabled(!port.killable)
            Button("Zorla kapat") { dev.kill(port, force: true) }.disabled(!port.killable)
        }
    }
}

struct ContainerRow: View {
    @ObservedObject var dev: DevCenter
    let container: DockerContainer

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(container.running ? Color.green : Color.secondary.opacity(0.5)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(container.name).font(.callout.weight(.medium)).lineLimit(1)
                    if let project = container.project {
                        Text(project).font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }
                Text("\(container.image) · \(container.status)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            ForEach(container.ports.prefix(3), id: \.self) { port in
                Button(":\(String(port))") { dev.open(port) }
                    .buttonStyle(.link)
                    .font(.system(.caption, design: .monospaced))
                    .disabled(!container.running)
                    .help("http://localhost:\(String(port)) adresini aç")
            }
            if dev.working.contains(container.id) {
                ProgressView().controlSize(.small).frame(width: 18)
            } else {
                Button { dev.toggle(container) } label: {
                    Image(systemName: container.running ? "stop.fill" : "play.fill")
                        .foregroundStyle(container.running ? Color.red.opacity(0.85) : Color.green)
                }
                .buttonStyle(.borderless)
                .help(container.running ? "Konteyneri durdur" : "Konteyneri başlat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
