import SwiftUI

/// Açık ada: üst sırada sayfalar ve durum, altında seçili sayfa.
struct ExpandedView: View {
    @ObservedObject var m: IslandManager
    @ObservedObject var media: NowPlaying
    @ObservedObject var pomo: PomodoroManager
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(IslandPage.allCases) { p in
                    if p != .shelf || m.settings.isOn(.shelf) { tab(p) }
                }
                Spacer(minLength: m.geometry.notch.width + 16)
                status
            }
            .frame(height: m.geometry.notch.height)
            .padding(.horizontal, 22)
            Group {
                switch m.page {
                case .home: HomePage(m: m, media: media, pomo: pomo)
                case .timer: TimerPage(m: m)
                case .shelf: ShelfPage(m: m, shelf: shelf)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
    }

    private func tab(_ p: IslandPage) -> some View {
        let on = m.page == p
        return Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { m.page = p } } label: {
            HStack(spacing: 4) {
                Image(systemName: p.symbol).font(.system(size: 11, weight: .semibold))
                if on { Text(p.title).font(.system(size: 11, weight: .semibold, design: .rounded)) }
                if p == .shelf, !shelf.items.isEmpty, !on {
                    Text("\(shelf.items.count)").font(.system(size: 9, weight: .bold)).monospacedDigit()
                }
            }
            .foregroundStyle(on ? Color.black : IslandColors.dim)
            .padding(.horizontal, on ? 9 : 7).padding(.vertical, 4)
            .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(p.title)
    }

    private var status: some View {
        HStack(spacing: 9) {
            if let p = m.power {
                HStack(spacing: 4) {
                    Text("%\(p.percent)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    BatteryGlyph(percent: p.percent, charging: p.plugged, width: 21)
                }
            }
            TimelineView(.periodic(from: .now, by: 10)) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Button { m.onOpenSettings() } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 11)).foregroundStyle(IslandColors.dim)
            }
            .buttonStyle(.plain)
            .help("Ada ayarları")
        }
        .foregroundStyle(IslandColors.dim)
    }
}

// MARK: - Şimdi

private struct HomePage: View {
    @ObservedObject var m: IslandManager
    @ObservedObject var media: NowPlaying
    @ObservedObject var pomo: PomodoroManager

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if m.settings.isOn(.media) {
                MediaCard(m: m, media: media).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ClockCard(m: m).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(spacing: 10) {
                if m.pomoEnabled(), m.settings.isOn(.pomodoro) {
                    PomodoroTile(m: m, pomo: pomo)
                } else {
                    BatteryTile(m: m)
                }
                if m.settings.isOn(.timer) { TimerTile(m: m) } else { StopwatchTile(m: m) }
            }
            .frame(width: 214)
        }
    }
}

private struct MediaCard: View {
    @ObservedObject var m: IslandManager
    @ObservedObject var media: NowPlaying

    var body: some View {
        if let t = media.track {
            let accent = Color(nsColor: media.accent)
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    ArtworkView(media: media, size: 96, radius: 18)
                        .shadow(color: accent.opacity(0.35), radius: 12, y: 4)
                    AppBadge(bundleID: t.appBundleID).offset(x: 5, y: 5)
                }
                .onTapGesture { media.openApp() }
                .help("\(t.appName) uygulamasını aç")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(t.title).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1)
                        Spacer(minLength: 4)
                        EqualizerView(color: accent, playing: t.playing, bars: 4, height: 12)
                    }
                    Text(t.artist.isEmpty ? t.album : t.artist).font(.system(size: 12)).foregroundStyle(IslandColors.dim).lineLimit(1)
                    Scrubber(media: media, track: t, color: accent).padding(.top, 4)
                    HStack(spacing: 18) {
                        Spacer(minLength: 0)
                        controlButton("backward.fill", 15) { media.previous() }
                        controlButton(t.playing ? "pause.fill" : "play.fill", 24) { media.togglePlay() }
                        controlButton("forward.fill", 15) { media.next() }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 1)
                    if m.settings.isOn(.volume) {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.fill").font(.system(size: 9))
                            ThinSlider(value: Double(m.volume), color: .white.opacity(0.85), onChange: { m.setVolume(Float($0)) })
                            Image(systemName: "speaker.wave.3.fill").font(.system(size: 9))
                        }
                        .foregroundStyle(IslandColors.dim)
                    }
                }
            }
        } else {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(IslandColors.tile)
                    Image(systemName: "music.note").font(.system(size: 34, weight: .semibold)).foregroundStyle(Color.white.opacity(0.35))
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Şu an bir şey çalmıyor").font(.system(size: 14, weight: .semibold, design: .rounded))
                    if media.needsAccessibility {
                        Text("Firefox'ta çalanı görmek için Deskling'e Erişilebilirlik izni ver.")
                            .font(.system(size: 11)).foregroundStyle(IslandColors.timer).fixedSize(horizontal: false, vertical: true)
                    } else if let hint = media.browserHints.first {
                        Text("Kapak ve süre için bir kez şu ayarı aç: \(hint)")
                            .font(.system(size: 11)).foregroundStyle(IslandColors.timer).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Müzik, Spotify ya da tarayıcıda YouTube Music gibi bir sitede şarkı başlatınca kapağı ve denetimleri burada görünür.")
                            .font(.system(size: 11)).foregroundStyle(IslandColors.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        if media.needsAccessibility { PillButton(title: "İzin ver", fill: IslandColors.timer, text: .black) { Paster.requestAccess() } }
                        if NowPlaying.installed(.music) { PillButton(title: "Müzik", fill: IslandColors.tile) { NowPlaying.open(.music) } }
                        if NowPlaying.installed(.spotify) { PillButton(title: "Spotify", fill: IslandColors.tile) { NowPlaying.open(.spotify) } }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func controlButton(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .frame(width: size + 16, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AppBadge: View {
    let bundleID: String?

    var body: some View {
        if let id = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.5), radius: 3)
        }
    }
}

private struct Scrubber: View {
    @ObservedObject var media: NowPlaying
    let track: TrackInfo
    let color: Color
    @State private var preview: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let e = preview.map { $0 * track.duration } ?? track.elapsed(ctx.date)
            VStack(spacing: 2) {
                if track.duration > 0 {
                    ThinSlider(value: e / track.duration, color: color, onChange: { preview = $0 },
                               onCommit: { f in media.seek(to: f * track.duration); preview = nil })
                }
                HStack {
                    Text(IslandFormat.clock(e))
                    Spacer()
                    if track.duration > 0 { Text("-" + IslandFormat.clock(track.duration - e)) }
                }
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(IslandColors.dim)
            }
        }
    }
}

private struct ClockCard: View {
    @ObservedObject var m: IslandManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(IslandColors.dim)
                Text(ctx.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct Tile<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IslandColors.tile))
    }
}

private struct PomodoroTile: View {
    @ObservedObject var m: IslandManager
    @ObservedObject var pomo: PomodoroManager

    var body: some View {
        Tile {
            HStack(spacing: 10) {
                DrinkGlyph(kind: m.pomoDrink(), pomo: pomo, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pomo.isPaused ? "\(pomo.phase.title) · durdu" : pomo.phase.title)
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(IslandColors.dim).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(pomo.clockText).font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(pomo.phase.isBreak ? IslandColors.rest : pomo.phase == .idle ? .white : IslandColors.focus)
                    }
                }
                Spacer(minLength: 0)
                RoundIconButton(symbol: pomo.running ? "pause.fill" : "play.fill", size: 30,
                                fill: (pomo.phase.isBreak ? IslandColors.rest : IslandColors.focus).opacity(0.28),
                                tint: pomo.phase.isBreak ? IslandColors.rest : IslandColors.focus,
                                help: pomo.phase == .idle ? "Odak başlat" : pomo.running ? "Duraklat" : "Devam et") { pomo.toggle() }
                if pomo.phase != .idle {
                    RoundIconButton(symbol: "forward.end.fill", size: 26, help: pomo.phase == .focus ? "Molaya geç" : "Atla") { pomo.skip() }
                }
            }
        }
    }
}

private struct BatteryTile: View {
    @ObservedObject var m: IslandManager

    var body: some View {
        Tile {
            HStack(spacing: 10) {
                BatteryGlyph(percent: m.power?.percent ?? 100, charging: m.power?.plugged ?? false, width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.power?.plugged == true ? (m.power?.charging == true ? "Şarj oluyor" : "Prize takılı") : "Pil")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(IslandColors.dim)
                    Text(m.power.map { "%\($0.percent)" } ?? "—")
                        .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct TimerTile: View {
    @ObservedObject var m: IslandManager

    var body: some View {
        Tile {
            if let c = m.countdown {
                HStack(spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        HStack(spacing: 10) {
                            ProgressRing(progress: 1 - c.progress(ctx.date), color: IslandColors.timer, width: 3.2).frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.running ? "Zamanlayıcı" : "Zamanlayıcı · durdu").font(.system(size: 10.5, weight: .medium)).foregroundStyle(IslandColors.dim)
                                Text(IslandFormat.clock(c.remaining(ctx.date), roundUp: true))
                                    .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(IslandColors.timer)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    RoundIconButton(symbol: c.running ? "pause.fill" : "play.fill", size: 30, fill: IslandColors.timer.opacity(0.28),
                                    tint: IslandColors.timer, help: c.running ? "Duraklat" : "Devam et") { m.toggleTimer() }
                    RoundIconButton(symbol: "xmark", size: 26, help: "İptal et") { m.cancelTimer() }
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Zamanlayıcı").font(.system(size: 10.5, weight: .medium)).foregroundStyle(IslandColors.dim)
                    HStack(spacing: 6) {
                        ForEach([1, 5, 10, 25], id: \.self) { n in
                            PresetChip(minutes: n) { m.startTimer(minutes: n) }
                        }
                    }
                }
            }
        }
    }
}

private struct StopwatchTile: View {
    @ObservedObject var m: IslandManager

    var body: some View {
        Tile {
            HStack {
                TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                    Text(IslandFormat.clock(m.stopwatch.elapsed(ctx.date), tenths: true))
                        .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Spacer()
                RoundIconButton(symbol: m.stopwatch.running ? "pause.fill" : "play.fill", size: 30) { m.toggleStopwatch() }
            }
        }
    }
}

private struct PresetChip: View {
    let minutes: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(minutes >= 60 ? "\(minutes / 60) sa" : "\(minutes) dk")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandColors.timer)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(Capsule().fill(IslandColors.timer.opacity(hover ? 0.32 : 0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("\(minutes) dakikalık zamanlayıcı başlat")
    }
}

// MARK: - Zamanlayıcı ve kronometre

private struct TimerPage: View {
    @ObservedObject var m: IslandManager

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            countdown.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            stopwatch.frame(width: 212, alignment: .topLeading)
        }
    }

    @ViewBuilder private var countdown: some View {
        if let c = m.countdown {
            HStack(spacing: 18) {
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    ZStack {
                        ProgressRing(progress: 1 - c.progress(ctx.date), color: IslandColors.timer, width: 7)
                        VStack(spacing: 0) {
                            Text(IslandFormat.clock(c.remaining(ctx.date), roundUp: true))
                                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                            Text(IslandFormat.minutes(c.total)).font(.system(size: 10)).foregroundStyle(IslandColors.dim)
                        }
                    }
                    .frame(width: 128, height: 128)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        RoundIconButton(symbol: c.running ? "pause.fill" : "play.fill", size: 40, fill: IslandColors.timer.opacity(0.28),
                                        tint: IslandColors.timer, help: c.running ? "Duraklat" : "Devam et") { m.toggleTimer() }
                        RoundIconButton(symbol: "xmark", size: 40, help: "İptal et") { m.cancelTimer() }
                    }
                    HStack(spacing: 6) {
                        PillButton(title: "+1 dk", fill: IslandColors.tile) { m.addToTimer(60) }
                        PillButton(title: "+5 dk", fill: IslandColors.tile) { m.addToTimer(300) }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Text("Zamanlayıcı").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(IslandColors.dim)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach([1, 3, 5, 10, 15, 25, 45, 60], id: \.self) { n in
                        PresetChip(minutes: n) { m.startTimer(minutes: n) }
                    }
                }
                HStack(spacing: 8) {
                    RoundIconButton(symbol: "minus", size: 26) { m.settings.customMinutes = max(1, m.settings.customMinutes - 1) }
                    Text("\(m.settings.customMinutes) dk").font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(minWidth: 52)
                    RoundIconButton(symbol: "plus", size: 26) {
                        m.settings.customMinutes = min(IslandSettings.minutesRange.upperBound, m.settings.customMinutes + 1)
                    }
                    Spacer()
                    PillButton(title: "Başlat", fill: IslandColors.timer, text: .black) { m.startTimer(minutes: m.settings.customMinutes) }
                }
            }
        }
    }

    private var stopwatch: some View {
        let s = m.stopwatch
        return VStack(alignment: .leading, spacing: 8) {
            Text("Kronometre").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(IslandColors.dim)
            TimelineView(.periodic(from: .now, by: s.running ? 0.05 : 60)) { ctx in
                Text(IslandFormat.clock(s.elapsed(ctx.date), tenths: true))
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            }
            HStack(spacing: 10) {
                RoundIconButton(symbol: s.running ? "flag.fill" : "arrow.counterclockwise", size: 34,
                                help: s.running ? "Tur" : "Sıfırla") { m.lapOrReset() }
                    .disabled(!s.active)
                    .opacity(s.active ? 1 : 0.4)
                RoundIconButton(symbol: s.running ? "pause.fill" : "play.fill", size: 34,
                                fill: (s.running ? IslandColors.low : IslandColors.rest).opacity(0.28),
                                tint: s.running ? IslandColors.low : IslandColors.rest, help: s.running ? "Durdur" : "Başlat") { m.toggleStopwatch() }
            }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(s.laps.prefix(2).enumerated()), id: \.offset) { i, lap in
                    HStack {
                        Text("Tur \(s.laps.count - i)")
                        Spacer()
                        Text(IslandFormat.clock(lap, tenths: true))
                    }
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(IslandColors.dim)
                }
            }
        }
    }
}

// MARK: - Raf

private struct ShelfPage: View {
    static let visible = 6
    @ObservedObject var m: IslandManager
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        if shelf.items.isEmpty {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(m.dropTargeted ? Color.accentColor : Color.white.opacity(0.25))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(m.dropTargeted ? Color.accentColor.opacity(0.12) : Color.clear))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 26)).foregroundStyle(IslandColors.dim)
                        Text("Dosyaları çentiğe sürükleyip bırak").font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Dosyalar taşınmaz; raf yalnızca yerlerini hatırlar. Buradan istediğin yere sürükleyebilirsin.")
                            .font(.system(size: 11)).foregroundStyle(IslandColors.dim).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 30)
                )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Sığan kadarı gösterilir; fazlası Finder'da açılır.
                HStack(spacing: 8) {
                    ForEach(shelf.items.prefix(Self.visible)) { item in ShelfTile(item: item, shelf: shelf) }
                    if shelf.items.count > Self.visible {
                        Button { ShelfStore.reveal(Array(shelf.items.dropFirst(Self.visible))) } label: {
                            Text("+\(shelf.items.count - Self.visible)").font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(width: 54, height: 92)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(IslandColors.tile))
                        }
                        .buttonStyle(.plain)
                        .help("Kalan dosyaları Finder'da göster")
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("\(shelf.items.count) dosya").font(.system(size: 11)).foregroundStyle(IslandColors.dim)
                    Spacer()
                    PillButton(title: "AirDrop", fill: IslandColors.tile) { ShelfStore.airDrop(shelf.items) }
                    PillButton(title: "Finder'da göster", fill: IslandColors.tile) { ShelfStore.reveal(shelf.items) }
                    PillButton(title: "Rafı boşalt", fill: IslandColors.tile) { shelf.clear() }
                }
            }
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: ShelfStore.icon(item)).resizable().frame(width: 50, height: 50)
            Text(item.name).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                .frame(width: 78, height: 26, alignment: .top)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(hover ? 0.12 : 0.06)))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain).padding(4).help("Raftan kaldır (dosya silinmez)")
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { ShelfStore.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Aç") { ShelfStore.open(item) }
            Button("Finder'da Göster") { ShelfStore.reveal([item]) }
            Button("AirDrop ile Gönder") { ShelfStore.airDrop([item]) }
            Divider()
            Button("Raftan Kaldır") { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}
