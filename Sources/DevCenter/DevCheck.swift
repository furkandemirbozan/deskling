import AppKit

/// Port tarayıcısını kendi açtığı geçici bir sunucuyla dener. Docker konteynerlerine dokunmaz, yalnızca listeler.
final class DevCheck {
    private var failures = 0

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "GEÇTİ  " : "KALDI  ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
        if !ok { failures += 1 }
    }

    private func after(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }

    func run() {
        after(90) { print("PORT_ZAMAN_ASIMI"); exit(2) }
        offline()
        live()
    }

    private func offline() {
        let sample = """
        p501
        cnode
        u\(getuid())
        f20
        n*:3000
        f21
        n[::1]:3000
        p77
        cpostgres
        u\(getuid())
        f5
        n127.0.0.1:5432
        f6
        n[::1]:5432
        p88
        cControlCenter
        u\(getuid())
        f9
        n*:5000
        p1
        claunchd
        u0
        f3
        n*:22
        """
        let ports = PortScanner.parse(sample)
        check("lsof çıktısı okunur", ports.map(\.port) == [22, 3000, 5000, 5432], ports.map { String($0.port) }.joined(separator: ","))
        let node = ports.first { $0.port == 3000 }
        check("IPv4 ve IPv6 kaydı tek satırda birleşir", node?.hosts == ["*", "[::1]"])
        check("her yere açık port ağa açık sayılır", node?.localOnly == false)
        check("yalnızca 127.0.0.1 ve ::1 dinleyen port yerel sayılır", ports.first { $0.port == 5432 }?.localOnly == true)
        let root = ports.first { $0.port == 22 }
        check("başka kullanıcının süreci kapatılamaz ve sistem sayılır", root?.killable == false && root?.isSystem == true)
        check("AirPlay Alıcısı için ipucu verilir", ports.first { $0.port == 5000 }.map { $0.detail.contains("AirPlay") && $0.hint.contains("Sistem Ayarları") } == true)
        let me = ListeningPort(pid: getpid(), port: 1, hosts: ["*"], command: "x", uid: getuid())
        check("uygulama kendini kapatamaz", !me.killable)
        check("uzun komut kısaltılır",
              PortScanner.shortCommand("/usr/local/bin/node /tmp/proje/node_modules/.bin/vite --port 3000") == "node vite --port 3000")

        let docker = """
        {"ID":"aaa111","Names":"web-db","Image":"postgres:17","State":"running","Status":"Up 2 hours","Ports":"127.0.0.1:55432->5432/tcp","Labels":"com.docker.compose.project=demo,com.docker.compose.service=db"}
        {"ID":"bbb222","Names":"cache","Image":"redis:7","State":"exited","Status":"Exited (0) 3 days ago","Ports":"","Labels":""}
        {"ID":"ccc333","Names":"api","Image":"node:22","State":"running","Status":"Up 5 minutes","Ports":"0.0.0.0:8080->80/tcp, :::8080->80/tcp, 0.0.0.0:9229->9229/tcp","Labels":""}
        """
        let containers = DockerService.parse(docker)
        check("Docker listesi okunur, çalışanlar önce gelir", containers.map(\.name) == ["api", "web-db", "cache"])
        check("Docker port eşlemeleri okunur", containers.first?.ports == [8080, 9229] && containers[1].ports == [55432])
        check("Compose proje adı okunur", containers[1].project == "demo" && containers[2].project == nil)
        check("Docker yoksa kurulu değil denir", DockerService.list(binary: nil).0 == .notInstalled)
        check("Docker kapalıysa çökmez", { if case .notRunning = DockerService.list(binary: "/usr/bin/false").0 { return true }; return false }())
    }

    /// Geçici bir sunucu açar, tarayıcının onu bulduğunu ve kapatabildiğini doğrular.
    private func live() {
        let port = Int.random(in: 41000...48000)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        server.arguments = ["-l", "127.0.0.1", String(port)]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        server.standardInput = Pipe()
        do { try server.run() } catch { check("deneme sunucusu açılır", false); finish(); return }
        let dev = DevCenter()
        var opened: URL?
        dev.openURL = { opened = $0 }
        after(0.8) { [self] in
            let t0 = CFAbsoluteTimeGetCurrent()
            dev.refresh { [self] in
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                let found = dev.ports.first { $0.port == port }
                check("açılan port listede görünür", found?.pid == server.processIdentifier, "\(dev.ports.count) port, \(ms) ms")
                check("portu kullanan uygulama adı bulunur", found?.displayName == "nc", found?.displayName ?? "-")
                check("yerel port yerel olarak işaretlenir ve kapatılabilir", found?.localOnly == true && found?.killable == true)
                check("tarama hızlıdır", ms < 3000, "\(ms) ms")
                dev.open(port)
                check("tarayıcıda açma doğru adresi verir", opened?.absoluteString == "http://localhost:\(port)")
                switch dev.docker {
                case .ready: check("Docker konteynerleri listelenir", true, "\(dev.containers.count) konteyner")
                case .notRunning(let r): check("Docker kapalı olduğu söylenir", true, r)
                case .notInstalled: check("Docker kurulu değil denir", true)
                case .unknown: check("Docker durumu belirlenir", false)
                }
                guard let found else { server.terminate(); finish(); return }
                dev.kill(found)
                after(2.5) { [self] in
                    check("tek tıkla port boşaltılır", !server.isRunning && !dev.ports.contains { $0.port == port }, dev.note ?? "")
                    if server.isRunning { server.terminate() }
                    finish()
                }
            }
        }
    }

    private func finish() {
        print(failures == 0 ? "PORT_GECTI" : "PORT_KALDI \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
