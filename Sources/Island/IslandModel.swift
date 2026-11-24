import AppKit
import Combine

/// AppModel'in ada tarafı: Pomodoro, robot ve pano olayları adaya iletilir.
extension AppModel {
    func connectIsland() {
        let island = self.island
        island.pomoEnabled = { [weak self] in self?.pomoEnabled ?? false }
        island.pomoDrink = { [weak self] in self?.pomoDrink ?? .tea }
        pomoListeners.append { [weak island] in island?.objectWillChange.send() }
        pomoTransitionListeners.append { [weak self, weak island] t in
            guard let self, let island, self.pomoEnabled,
                  let msg = PomodoroAlerts.message(for: t, done: self.pomo.cycleDone == 0 ? self.pomoCycle : self.pomo.cycleDone,
                                                   durations: self.pomoDurations) else { return }
            island.pomoTransition(t, title: msg.title, body: msg.body)
        }
        clipboard.onCapture = { [weak island] item in
            island?.show(.clipboard(item.kind, item.preview), seconds: 1.8)
        }
        // Robot görevdeyken kulakta kalan sayı; görev bitince kaç görüntü toplandığı.
        var historyAtStart = history.count
        $busy.combineLatest($statusTitle, $statusDetail)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self, weak island] busy, title, detail in
                guard let self, let island else { return }
                let wasBusy = island.robot != nil
                if busy, !wasBusy { historyAtStart = self.history.count }
                island.setRobot(busy: busy, title: title, detail: detail)
                if !busy, wasBusy {
                    // Geçmiş görev bitince yazılır; bir sonraki döngüde sayılır.
                    DispatchQueue.main.async { island.robotFinished(collected: self.history.count - historyAtStart) }
                }
            }
            .store(in: &islandBag)
    }
}
