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

    /// Bellek ve diski yarım dakikada bir yoklar; sıkışınca adada uyarı belirir.
    func startHealthWatch() {
        guard healthTimer == nil else { return }
        let tick = { [weak self] in
            guard let self else { return }
            let memory = self.memory
            DispatchQueue.global(qos: .utility).async {
                let stats = MemoryStats.read(), volume = VolumeInfo.read()
                // Bellek sıkışıksa hangi uygulamaların kapatılabileceğini de hesapla.
                let tight = stats.map { $0.pressure >= 2 || $0.usedFraction >= 0.9 } ?? false
                let apps = tight ? MemoryCenter.liveApps() : nil
                let playing = tight ? (AudioActivity.playingBundles() ?? []) : []
                DispatchQueue.main.async {
                    if let apps { memory.apply(stats: stats, apps: apps, playing: playing) }
                    self.island.setHealth(HealthRules.evaluate(memory: stats, volume: volume, suggested: memory.suggested))
                }
            }
        }
        let t = Timer(timeInterval: 30, repeats: true) { _ in tick() }
        RunLoop.main.add(t, forMode: .common)
        healthTimer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { tick() }
        island.onHealthAction = { [weak self] kind in
            guard let self else { return }
            switch kind {
            case .memory:
                if self.memory.suggested.isEmpty { self.openPanel(.disk, page: "memory") } else { self.memory.quit(self.memory.suggested) }
            case .disk:
                self.openPanel(.disk, page: "disk")
                if !self.disk.scanned, self.disk.scanning == nil { self.disk.scan() }
            }
        }
    }

    func openPanel(_ tab: PanelTab, page: String? = nil) {
        if let page { UserDefaults.standard.set(page, forKey: "diskTabPage") }
        panelTab = tab
        onNeedsPanel?()
    }
}
