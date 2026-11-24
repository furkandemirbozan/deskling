import SwiftUI

/// Denetim panelindeki Odak sekmesi: sayaç, içecek seçimi, süreler, görünüm ve davranış.
struct PomodoroTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var pomo: PomodoroManager

    var body: some View {
        Form {
            Section {
                Toggle("Pomodoro", isOn: $model.pomoEnabled)
                if model.pomoEnabled {
                    TimerCard(pomo: pomo, drink: model.pomoDrink, cycle: model.pomoCycle)
                    Toggle("İçecek masaüstünde dursun", isOn: $model.pomoShowDrink)
                }
            }
            Section("İçecek") {
                HStack(spacing: 10) {
                    ForEach(DrinkKind.allCases) { k in
                        DrinkCard(kind: k, selected: model.pomoDrink == k) { model.pomoDrink = k }
                    }
                }
                .padding(.vertical, 4)
            }
            .disabled(!model.pomoEnabled)
            Section("Süreler") {
                Stepper("Odak: \(model.pomoFocus) dk", value: $model.pomoFocus, in: PomoLimits.focus, step: 5)
                Stepper("Kısa mola: \(model.pomoShort) dk", value: $model.pomoShort, in: PomoLimits.shortBreak)
                Stepper("Uzun mola: \(model.pomoLong) dk", value: $model.pomoLong, in: PomoLimits.longBreak, step: 5)
                Stepper("Uzun mola her \(model.pomoCycle) odakta bir", value: $model.pomoCycle, in: PomoLimits.cycle)
            }
            .disabled(!model.pomoEnabled)
            Section("Görünüm") {
                LabeledContent("Boyut") {
                    HStack(spacing: 10) {
                        Slider(value: $model.pomoScale, in: PomoLimits.scale, step: 0.05)
                        Text("%\(Int((model.pomoScale * 100).rounded()))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Menü çubuğunda kalan süre", isOn: $model.pomoMenuTimer)
                Picker("Animasyon", selection: $model.pomoEffects) {
                    ForEach(DrinkEffects.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .disabled(!model.pomoEnabled)
            Section("Davranış") {
                Toggle("Sesli uyarı", isOn: $model.pomoSound)
                Toggle("Bildirim göster", isOn: $model.pomoNotify)
                Toggle("Odak sırasında ekranı uyanık tut", isOn: $model.pomoKeepAwake)
                Toggle("Odak sırasında karı ve robotu duraklat", isOn: $model.pomoQuietFocus)
                Toggle("Molada robot ekran görüntülerini toplasın", isOn: $model.pomoCleanOnBreak)
                Text("Molada robot yalnızca odak sırasında masaüstüne düşen ekran görüntülerini toplar. Kilitlediğin ya da halının altına sakladığın dosyalara dokunmaz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!model.pomoEnabled)
        }
        .formStyle(.grouped)
    }
}

/// Kalan süre, aşama, seans noktaları ve düğmeler.
private struct TimerCard: View {
    @ObservedObject var pomo: PomodoroManager
    let drink: DrinkKind
    let cycle: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 16) {
                Image(nsImage: DrinkIcons.menuIcon(drink, fill: pomo.phase == .focus ? 1 - pomo.progress * 0.92 : 1))
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(pomo.phase.isBreak ? Color.green : Color.accentColor)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pomo.clockText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    HStack(spacing: 6) {
                        Text(pomo.isPaused ? "\(pomo.phase.title) · duraklatıldı" : pomo.phase.title)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            ForEach(0..<cycle, id: \.self) { i in
                                Circle()
                                    .fill(i < pomo.cycleDone ? Color.accentColor : Color.secondary.opacity(0.25))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .help("Bu döngüde \(pomo.cycleDone)/\(cycle) seans")
                    }
                    .font(.callout)
                }
                Spacer()
                Button { pomo.toggle() } label: {
                    Image(systemName: pomo.running ? "pause.fill" : "play.fill").frame(width: 18, height: 18)
                }
                .help(pomo.phase == .idle ? "Odak başlat" : pomo.running ? "Duraklat" : "Devam et")
                Button { pomo.reset() } label: { Image(systemName: "arrow.counterclockwise").frame(width: 18, height: 18) }
                    .help("Sıfırla")
                    .disabled(pomo.phase == .idle)
                Button { pomo.skip() } label: { Image(systemName: "forward.end.fill").frame(width: 18, height: 18) }
                    .help(pomo.phase == .focus ? "Molaya geç" : "Atla")
            }
            .controlSize(.large)
            .padding(.vertical, 4)
        }
    }
}

/// Temanın kendi çiziminden üretilmiş seçim kartı.
private struct DrinkCard: View {
    let kind: DrinkKind
    let selected: Bool
    let action: () -> Void

    private static var images: [DrinkKind: NSImage] = [:]

    private var image: NSImage {
        if let i = Self.images[kind] { return i }
        let i = DrinkArt.thumbnail(kind, size: CGSize(width: 88, height: 120))
        Self.images[kind] = i
        return i
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 96)
                    .padding(.top, 2)
                Text(kind.shortTitle)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(kind.title)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
