import SwiftUI

/// Fare bardağın üstüne gelince beliren yarı saydam mini kontrol çubuğu.
struct DrinkControlBar: View {
    @ObservedObject var pomo: PomodoroManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(pomo.clockText)
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 92, alignment: .leading)
                Spacer(minLength: 0)
                BarButton(symbol: pomo.running ? "pause.fill" : "play.fill",
                          help: pomo.phase == .idle ? "Odak başlat" : pomo.running ? "Duraklat" : "Devam et", prominent: true) {
                    pomo.toggle()
                }
                BarButton(symbol: "arrow.counterclockwise", help: "Sıfırla") { pomo.reset() }
                    .disabled(pomo.phase == .idle)
                BarButton(symbol: "forward.end.fill", help: pomo.phase == .focus ? "Molaya geç" : "Atla") { pomo.skip() }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(width: DrinkController.barSize.width - 4, height: DrinkController.barSize.height - 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
            .frame(width: DrinkController.barSize.width, height: DrinkController.barSize.height)
        }
    }

    private var subtitle: String {
        switch pomo.phase {
        case .idle: return "Hazır · bugün \(pomo.todayDone)"
        case .focus: return (pomo.running ? "Odak" : "Duraklatıldı") + " · \(pomo.cycleDone + 1)/\(pomo.durations.cycle)"
        case .shortBreak, .longBreak: return pomo.running ? pomo.phase.title : "Mola duraklatıldı"
        }
    }
}

private struct BarButton: View {
    let symbol: String
    let help: String
    var prominent = false
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 14 : 12, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.primary.opacity(prominent ? (hover ? 0.22 : 0.15) : (hover ? 0.14 : 0.06))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
        .onHover { hover = $0 }
    }
}
