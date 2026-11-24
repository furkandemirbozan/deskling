import SwiftUI
import UniformTypeIdentifiers

enum IslandColors {
    static let focus = Color(red: 1, green: 0.58, blue: 0.22)
    static let rest = Color(red: 0.36, green: 0.88, blue: 0.5)
    static let timer = Color(red: 1, green: 0.62, blue: 0.16)
    static let charge = Color(red: 0.32, green: 0.9, blue: 0.42)
    static let low = Color(red: 1, green: 0.32, blue: 0.3)
    static let dim = Color.white.opacity(0.55)
    static let tile = Color.white.opacity(0.075)
}

/// Çentikten aşağı uzanan siyah şekil: üst köşeler ekran kenarına yumuşakça karışır, alt köşeler yuvarlaktır.
struct IslandShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let f = min(flare, r.width / 4), rad = min(radius, (r.width - 2 * f) / 2, r.height - f)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + f, y: r.minY + f), control: CGPoint(x: r.minX + f, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + f, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + f + rad, y: r.maxY), control: CGPoint(x: r.minX + f, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - f - rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - f, y: r.maxY - rad), control: CGPoint(x: r.maxX - f, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - f, y: r.minY + f))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - f, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandRootView: View {
    @ObservedObject var m: IslandManager
    @ObservedObject var media: NowPlaying
    @ObservedObject var pomo: PomodoroManager
    @ObservedObject var shelf: ShelfStore

    /// Galeri çiziminde AppKit'e dayanan bırakma alanı eklenmez.
    var interactive = true

    init(manager: IslandManager, interactive: Bool = true) {
        self.interactive = interactive
        m = manager
        media = manager.media
        pomo = manager.pomo
        shelf = manager.shelf
    }

    private static let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        let d = m.display
        let size = IslandLayout.size(d, m.geometry)
        let flare = IslandLayout.flare(d)
        let radius = IslandLayout.radius(d)
        let secondary = m.secondary
        HStack(alignment: .top, spacing: IslandLayout.bubbleGap) {
            if secondary != nil { Color.clear.frame(width: m.geometry.notch.height, height: 1) }   // ortalamayı korur
            ZStack(alignment: .top) {
                IslandShape(flare: flare, radius: radius)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(d.isLarge ? 0.5 : 0), radius: 18, y: 8)
                IslandContent(m: m, media: media, pomo: pomo, shelf: shelf, display: d)
                    .padding(.horizontal, flare)
                    .id(d.key)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(Self.spring.delay(0.06)),
                                            removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            .frame(width: size.width + 2 * flare, height: size.height)
            .clipShape(IslandShape(flare: flare, radius: radius))
            .overlay(dropHalo(d, flare: flare, radius: radius))
            .contentShape(IslandShape(flare: flare, radius: radius))
            .onTapGesture {
                if case .compact(.live(.health)) = d { m.showHealthAlert() }
                else if case .compact = d { m.expand() } else if d == .closed { m.expand() }
            }
            if let s = secondary {
                SecondaryBubble(m: m, media: media, pomo: pomo, activity: s)
                    .frame(width: m.geometry.notch.height, height: m.geometry.notch.height)
                    .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
            }
        }
        .frame(width: IslandLayout.canvas.width, height: IslandLayout.canvas.height, alignment: .top)
        .opacity(d == .hidden ? 0 : 1)
        .animation(Self.spring, value: d)
        .animation(Self.spring, value: secondary)
        .environment(\.colorScheme, .dark)
        .modifier(DropArea(m: m, on: interactive))
    }

    @ViewBuilder private func dropHalo(_ d: IslandDisplay, flare: CGFloat, radius: CGFloat) -> some View {
        if m.dropTargeted, d == .expanded {
            IslandShape(flare: flare, radius: radius)
                .stroke(Color.accentColor.opacity(0.9), lineWidth: 2)
        }
    }
}

private struct DropArea: ViewModifier {
    let m: IslandManager
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { m.dropTargeted }, set: { v in
                m.dropTargeted = v
                if v { m.expand(page: .shelf) }
            })) { m.handleDrop($0) }
        } else {
            content
        }
    }
}

/// Şeklin içindeki içerik; her durum kendi yerleşimini çizer.
private struct IslandContent: View {
    @ObservedObject var m: IslandManager
    @ObservedObject var media: NowPlaying
    @ObservedObject var pomo: PomodoroManager
    @ObservedObject var shelf: ShelfStore
    let display: IslandDisplay

    var body: some View {
        switch display {
        case .hidden, .closed:
            Color.clear
        case .compact(let c):
            CompactView(m: m, media: media, pomo: pomo, content: c)
        case .expanded:
            ExpandedView(m: m, media: media, pomo: pomo, shelf: shelf)
        case .alert:
            AlertView(m: m)
        }
    }
}

// MARK: - Kulaklar

private struct CompactView: View {
    @ObservedObject var m: IslandManager
    @ObservedObject var media: NowPlaying
    @ObservedObject var pomo: PomodoroManager
    let content: CompactContent

    var body: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: m.geometry.notch.width)
            trailing
        }
        .padding(.horizontal, 11)
        .frame(height: m.geometry.notch.height)
        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leading: some View {
        switch content {
        case .live(.media):
            ArtworkView(media: media, size: 21, radius: 5)
        case .live(.pomodoro):
            HStack(spacing: 5) {
                DrinkGlyph(kind: m.pomoDrink(), pomo: pomo, size: 17)
                if pomo.isPaused { Image(systemName: "pause.fill").font(.system(size: 9)).foregroundStyle(IslandColors.dim) }
            }
        case .live(.timer):
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                ProgressRing(progress: 1 - (m.countdown?.progress(ctx.date) ?? 0), color: IslandColors.timer, width: 2.6)
                    .frame(width: 16, height: 16)
            }
        case .live(.stopwatch):
            Image(systemName: "stopwatch.fill").foregroundStyle(IslandColors.timer)
        case .live(.robot):
            Image(nsImage: RobotArt.appIcon(22)).resizable().frame(width: 20, height: 20)
        case .live(.hole):
            HoleGlyph(size: 18)
        case .live(.health):
            if let w = m.visibleHealth {
                Image(systemName: w.symbol).foregroundStyle(HealthColors.color(w.level))
            }
        case .transient(let t):
            TransientLeading(kind: t)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch content {
        case .live(.media):
            EqualizerView(color: Color(nsColor: media.accent), playing: media.track?.playing == true)
        case .live(.pomodoro):
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(pomo.clockText).foregroundStyle(pomo.phase.isBreak ? IslandColors.rest : IslandColors.focus)
            }
        case .live(.timer):
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                Text(IslandFormat.clock(m.countdown?.remaining(ctx.date) ?? 0, roundUp: true))
                    .foregroundStyle(m.countdown?.running == true ? IslandColors.timer : IslandColors.dim)
            }
        case .live(.stopwatch):
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(IslandFormat.clock(m.stopwatch.elapsed(ctx.date)))
                    .foregroundStyle(m.stopwatch.running ? IslandColors.timer : IslandColors.dim)
            }
        case .live(.robot):
            Text(m.robot?.short ?? "").font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.55, green: 0.82, blue: 1))
        case .live(.hole):
            HStack(spacing: 5) {
                ProgressRing(progress: Double(m.hole?.percent ?? 0) / 100, color: HoleGlyph.tint, width: 2.4).frame(width: 14, height: 14)
                Text("%\(m.hole?.percent ?? 0)").foregroundStyle(HoleGlyph.tint)
            }
        case .live(.health):
            if let w = m.visibleHealth {
                Text(w.short).foregroundStyle(HealthColors.color(w.level))
            }
        case .transient(let t):
            TransientTrailing(kind: t)
        }
    }
}

private struct TransientLeading: View {
    let kind: IslandTransientKind

    var body: some View {
        switch kind {
        case .power(let s, let e):
            HStack(spacing: 4) {
                Image(systemName: e == .low ? "battery.25" : e == .unplugged ? "powerplug.fill" : "bolt.fill")
                Text(e == .plugged ? "Şarj" : e == .unplugged ? "Pil" : e == .full ? "Dolu" : "Zayıf")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(e == .low ? IslandColors.low : s.plugged ? IslandColors.charge : .white)
        case .volume(let v, let muted):
            Image(systemName: muted || v <= 0.001 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                .frame(width: 22, alignment: .leading)
        case .device(let o):
            Image(systemName: o.symbol).font(.system(size: 15))
        case .clipboard(let k, _):
            Image(systemName: k.symbol).foregroundStyle(Color(red: 0.5, green: 0.78, blue: 1))
        case .robot:
            Image(nsImage: RobotArt.appIcon(22)).resizable().frame(width: 20, height: 20)
        case .shelf:
            Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(Color(red: 0.5, green: 0.78, blue: 1))
        case .hole(_, let ok):
            if ok { HoleGlyph(size: 18) } else { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(HealthColors.color(.critical)) }
        }
    }
}

private struct TransientTrailing: View {
    let kind: IslandTransientKind

    var body: some View {
        switch kind {
        case .power(let s, let e):
            HStack(spacing: 5) {
                Text("%\(s.percent)").foregroundStyle(e == .low ? IslandColors.low : .white)
                BatteryGlyph(percent: s.percent, charging: s.plugged, width: 24)
            }
        case .volume(let v, _):
            LevelBar(value: Double(v), color: .white).frame(width: 52, height: 5)
        case .device(let o):
            Text(o.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 106, alignment: .trailing)
        case .clipboard:
            Text("Kopyalandı").font(.system(size: 12, weight: .semibold, design: .rounded))
        case .robot(let text):
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                .foregroundStyle(Color(red: 0.55, green: 0.82, blue: 1))
        case .shelf(let n):
            Text("+\(n) rafta").font(.system(size: 12, weight: .semibold, design: .rounded))
        case .hole(let text, _):
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .trailing)
                .foregroundStyle(HoleGlyph.tint)
        }
    }
}

/// Ayrı baloncuk: ikinci etkinliğin simgesi.
private struct SecondaryBubble: View {
    @ObservedObject var m: IslandManager
    @ObservedObject var media: NowPlaying
    @ObservedObject var pomo: PomodoroManager
    let activity: LiveActivity

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            switch activity {
            case .media:
                ArtworkView(media: media, size: 20, radius: 10)
            case .pomodoro:
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ProgressRing(progress: 1 - pomo.progress, color: pomo.phase.isBreak ? IslandColors.rest : IslandColors.focus, width: 2.4)
                        .frame(width: 21, height: 21)
                        .overlay(DrinkGlyph(kind: m.pomoDrink(), pomo: pomo, size: 11))
                }
            case .timer:
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    ProgressRing(progress: 1 - (m.countdown?.progress(ctx.date) ?? 0), color: IslandColors.timer, width: 2.4)
                        .frame(width: 21, height: 21)
                }
            case .stopwatch:
                Image(systemName: "stopwatch.fill").font(.system(size: 13)).foregroundStyle(IslandColors.timer)
            case .robot:
                Image(nsImage: RobotArt.appIcon(22)).resizable().frame(width: 19, height: 19)
            case .hole:
                ProgressRing(progress: Double(m.hole?.percent ?? 0) / 100, color: HoleGlyph.tint, width: 2.4)
                    .frame(width: 21, height: 21).overlay(HoleGlyph(size: 10))
            case .health:
                Image(systemName: m.visibleHealth?.symbol ?? "exclamationmark.triangle.fill").font(.system(size: 12))
                    .foregroundStyle(HealthColors.color(m.visibleHealth?.level ?? .warning))
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            if activity == .health { m.showHealthAlert() } else { m.expand(page: activity == .timer || activity == .stopwatch ? .timer : .home) }
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Uyarı

private struct AlertView: View {
    @ObservedObject var m: IslandManager
    @State private var pulse = false

    var body: some View {
        if let a = m.alert {
            let tint: Color = {
                if case .pomodoro(let p) = a.kind { return p.isBreak ? IslandColors.rest : IslandColors.focus }
                if case .health(_, let level) = a.kind { return HealthColors.color(level) }
                return IslandColors.timer
            }()
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.22))
                    Circle().stroke(tint.opacity(pulse ? 0 : 0.6), lineWidth: 2).scaleEffect(pulse ? 1.45 : 1)
                    Image(systemName: a.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.title).font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(a.body).font(.system(size: 12)).foregroundStyle(IslandColors.dim).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if case .timer = a.kind {
                    PillButton(title: "+5 dk", fill: Color.white.opacity(0.14)) { m.snooze(minutes: 5) }
                }
                if case .health = a.kind {
                    PillButton(title: "Sonra", fill: Color.white.opacity(0.14)) { m.snoozeHealth() }
                    PillButton(title: a.action ?? "Aç", fill: tint, text: .black) { m.performHealthAction() }
                } else {
                    PillButton(title: "Tamam", fill: tint, text: .black) { m.dismissAlert() }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.top, m.geometry.notch.height + 4)
            .padding(.bottom, 16)
            .onAppear { withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true } }
        }
    }
}

// MARK: - Küçük parçalar

enum HealthColors {
    static func color(_ l: HealthWarning.Level) -> Color {
        l == .critical ? Color(red: 1, green: 0.36, blue: 0.33) : Color(red: 1, green: 0.72, blue: 0.22)
    }
}

/// Küçük kara delik: dönen mor halka.
struct HoleGlyph: View {
    static let tint = Color(red: 0.76, green: 0.62, blue: 1)
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let angle = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * 180
            ZStack {
                Circle().fill(AngularGradient(colors: [Self.tint, Color(red: 0.35, green: 0.18, blue: 0.75), Self.tint.opacity(0.2), Self.tint],
                                              center: .center))
                    .rotationEffect(.degrees(angle))
                Circle().fill(Color.black).padding(size * 0.28)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ArtworkView: View {
    @ObservedObject var media: NowPlaying
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let img = media.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(nsColor: media.accent), Color(nsColor: media.accent).opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Çalarken oynayan ince çubuklar; duraklayınca alçalır.
struct EqualizerView: View {
    let color: Color
    let playing: Bool
    var bars = 4
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.2) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule().fill(color).frame(width: 2.8, height: playing ? level(i, t) : 3)
                }
            }
            .frame(height: height)
        }
    }

    private func level(_ i: Int, _ t: Double) -> CGFloat {
        let d = Double(i)
        let v = abs(sin(t * (4.3 + d * 1.9) + d * 1.7)) * (0.55 + 0.45 * abs(sin(t * 1.7 + d * 2.3)))
        return max(3, height * CGFloat(0.22 + 0.78 * v))
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var width: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: width)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct LevelBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(color).frame(width: max(g.size.height, g.size.width * min(1, max(0, value))))
            }
        }
    }
}

struct BatteryGlyph: View {
    let percent: Int
    let charging: Bool
    var width: CGFloat = 26

    var body: some View {
        let h = width * 0.48
        let color: Color = charging ? IslandColors.charge : percent <= 20 ? IslandColors.low : .white
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: h * 0.3).stroke(Color.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: h * 0.2).fill(color)
                    .frame(width: max(2, (width - 4) * CGFloat(percent) / 100))
                    .padding(2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: h * 0.72, weight: .black))
                        .foregroundStyle(.black.opacity(0.75)).frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: h)
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.45)).frame(width: 1.6, height: h * 0.4)
        }
    }
}

/// İçeceğin menü çubuğu silueti; odakta seviyesi sayaçla iner.
struct DrinkGlyph: View {
    let kind: DrinkKind
    @ObservedObject var pomo: PomodoroManager
    let size: CGFloat

    var body: some View {
        Image(nsImage: DrinkIcons.menuIcon(kind, fill: pomo.phase == .focus ? 1 - pomo.progress * 0.92 : 1))
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(pomo.phase.isBreak ? IslandColors.rest : IslandColors.focus)
            .frame(width: size, height: size)
    }
}

struct PillButton: View {
    let title: String
    let fill: Color
    var text: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(text)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct RoundIconButton: View {
    let symbol: String
    var size: CGFloat = 30
    var fill: Color = IslandColors.tile
    var tint: Color = .white
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(fill.opacity(hover ? 1 : 0.85)))
                .scaleEffect(hover ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help)
    }
}

/// İnce, sürüklenebilir çubuk: parça konumu ve ses düzeyi için.
struct ThinSlider: View {
    let value: Double
    var color: Color = .white
    var onChange: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }
    @State private var drag: Double?
    @State private var hover = false

    var body: some View {
        GeometryReader { g in
            let v = drag ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(color).frame(width: max(0, g.size.width * min(1, max(0, v))))
            }
            .frame(height: hover || drag != nil ? 7 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    let f = min(1, max(0, e.location.x / max(1, g.size.width)))
                    drag = f
                    onChange(f)
                }
                .onEnded { e in
                    let f = min(1, max(0, e.location.x / max(1, g.size.width)))
                    onCommit(f)
                    drag = nil
                })
        }
        .frame(height: 12)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
