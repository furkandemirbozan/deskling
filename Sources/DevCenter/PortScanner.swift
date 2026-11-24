import Foundation

/// Komut çalıştırır; takılırsa süre dolunca durdurur. Çıktılar kilitlenmesin diye ayrı ayrı okunur.
enum Shell {
    struct Output {
        let status: Int32
        let out: String
        let err: String
    }

    static var path: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/usr/local/bin", "/opt/homebrew/bin", "\(home)/.docker/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
    }

    static func run(_ tool: String, _ args: [String], timeout: Double = 8) -> Output? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        group.wait()
        p.waitUntilExit()
        killer.cancel()
        return Output(status: p.terminationStatus, out: String(decoding: outData, as: UTF8.self), err: String(decoding: errData, as: UTF8.self))
    }
}

/// Bir sürecin dinlediği TCP portu.
struct ListeningPort: Identifiable, Hashable {
    let pid: Int32
    let port: Int
    var hosts: [String]
    var command: String
    var uid: uid_t
    var executable = ""
    var commandLine = ""
    var cwd: String?
    var appName: String?
    var appPath: String?

    var id: String { "\(pid)-\(port)" }

    /// Yalnızca bu Mac'ten mi erişilir, yoksa ağdaki başka cihazlar da bağlanabilir mi?
    var localOnly: Bool {
        hosts.allSatisfy { $0.hasPrefix("127.") || $0 == "[::1]" || $0 == "localhost" }
    }

    var isSystem: Bool {
        uid != getuid() || executable.hasPrefix("/System/") || executable.hasPrefix("/usr/libexec/") || executable.hasPrefix("/usr/sbin/")
    }

    var killable: Bool { uid == getuid() && pid != getpid() && pid > 1 }

    var displayName: String {
        if let appName { return appName }
        if !executable.isEmpty { return URL(fileURLWithPath: executable).lastPathComponent }
        return command
    }

    /// Klasör ve kısaltılmış komut; macOS servisleri için ne işe yaradığı.
    var detail: String {
        if isAirPlay { return "AirPlay Alıcısı (macOS servisi)" }
        var parts: [String] = []
        if let cwd, cwd != "/", cwd != FileManager.default.homeDirectoryForCurrentUser.path {
            parts.append(URL(fileURLWithPath: cwd).lastPathComponent)
        }
        let short = PortScanner.shortCommand(commandLine)
        if !short.isEmpty, short != displayName { parts.append(short) }
        parts.append("PID \(pid)")
        return parts.joined(separator: " · ")
    }

    var url: URL { URL(string: "http://localhost:\(port)")! }

    var isAirPlay: Bool { command == "ControlCenter" && (port == 5000 || port == 7000) }

    /// Satırın üstünde beklerken görünen açıklama.
    var hint: String {
        if isAirPlay { return "macOS'un AirPlay Alıcısı bu portu tutar. Boşaltmak için: Sistem Ayarları > Genel > AirDrop ve Handoff > AirPlay Alıcısı'nı kapat." }
        return commandLine.isEmpty ? displayName : commandLine
    }
}

enum PortScanner {
    static let lsof = "/usr/sbin/lsof"

    /// `lsof -F pcun` çıktısını okur; aynı sürecin IPv4 ve IPv6 kayıtları tek satırda birleşir.
    static func parse(_ text: String) -> [ListeningPort] {
        var found: [String: ListeningPort] = [:]
        var order: [String] = []
        var pid: Int32 = 0, cmd = "", uid: uid_t = 0
        for raw in text.split(separator: "\n") {
            guard let field = raw.first else { continue }
            let value = String(raw.dropFirst())
            switch field {
            case "p": pid = Int32(value) ?? 0
            case "c": cmd = value
            case "u": uid = uid_t(value) ?? 0
            case "n":
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                let host = String(value[..<colon])
                let key = "\(pid)-\(port)"
                if var existing = found[key] {
                    if !existing.hosts.contains(host) { existing.hosts.append(host) }
                    found[key] = existing
                } else {
                    found[key] = ListeningPort(pid: pid, port: port, hosts: [host], command: cmd, uid: uid)
                    order.append(key)
                }
            default: break
            }
        }
        return order.compactMap { found[$0] }.sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }
    }

    /// Örnek: "/usr/local/bin/node /x/node_modules/.bin/vite --port 3000" → "node vite --port 3000"
    static func shortCommand(_ line: String) -> String {
        let tokens = line.split(separator: " ").prefix(5).map { t -> String in
            t.hasPrefix("/") ? URL(fileURLWithPath: String(t)).lastPathComponent : String(t)
        }
        let joined = tokens.joined(separator: " ")
        return joined.count > 48 ? String(joined.prefix(47)) + "…" : joined
    }

    /// Dinlenen portları bulur, süreçlerin tam yolunu, komutunu ve çalıştığı klasörü ekler.
    static func scan() -> [ListeningPort] {
        guard let out = Shell.run(lsof, ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcun"]) else { return [] }
        var ports = parse(out.out)
        let pids = Array(Set(ports.map(\.pid))).map(String.init).joined(separator: ",")
        guard !pids.isEmpty else { return [] }

        var exe: [Int32: String] = [:], line: [Int32: String] = [:], cwd: [Int32: String] = [:]
        if let r = Shell.run("/bin/ps", ["-ww", "-o", "pid=,comm=", "-p", pids]) { exe = pairs(r.out) }
        if let r = Shell.run("/bin/ps", ["-ww", "-o", "pid=,command=", "-p", pids]) { line = pairs(r.out) }
        if let r = Shell.run(lsof, ["-a", "-d", "cwd", "-Fpn", "-p", pids]) {
            var current: Int32 = 0
            for raw in r.out.split(separator: "\n") {
                if raw.hasPrefix("p") { current = Int32(raw.dropFirst()) ?? 0 }
                if raw.hasPrefix("n") { cwd[current] = String(raw.dropFirst()) }
            }
        }
        for i in ports.indices {
            ports[i].executable = exe[ports[i].pid] ?? ""
            ports[i].commandLine = line[ports[i].pid] ?? ""
            ports[i].cwd = cwd[ports[i].pid]
        }
        return ports
    }

    private static func pairs(_ text: String) -> [Int32: String] {
        var out: [Int32: String] = [:]
        for raw in text.split(separator: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard let space = t.firstIndex(of: " "), let pid = Int32(t[..<space]) else { continue }
            out[pid] = t[space...].trimmingCharacters(in: .whitespaces)
        }
        return out
    }
}

// MARK: - Docker

struct DockerContainer: Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    let state: String
    let status: String
    let ports: [Int]
    let project: String?

    var running: Bool { state == "running" }
}

enum DockerState: Equatable {
    case unknown
    case notInstalled
    case notRunning(String)
    case ready
}

enum DockerService {
    static var binary: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "\(home)/.docker/bin/docker",
                "/Applications/Docker.app/Contents/Resources/bin/docker"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func parse(_ text: String) -> [DockerContainer] {
        text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = o["ID"] as? String else { return nil }
            let labels = (o["Labels"] as? String) ?? ""
            var project: String?
            if let r = labels.range(of: "com.docker.compose.project=") {
                project = String(labels[r.upperBound...].prefix { $0 != "," })
            }
            return DockerContainer(id: id, name: (o["Names"] as? String) ?? id, image: (o["Image"] as? String) ?? "",
                                   state: (o["State"] as? String) ?? "", status: (o["Status"] as? String) ?? "",
                                   ports: hostPorts((o["Ports"] as? String) ?? ""), project: project)
        }
        .sorted { $0.running != $1.running ? $0.running : $0.name < $1.name }
    }

    /// "0.0.0.0:6379->6379/tcp, :::6379->6379/tcp" → [6379]
    static func hostPorts(_ s: String) -> [Int] {
        var out: [Int] = []
        for part in s.components(separatedBy: ",") {
            guard let arrow = part.range(of: "->") else { continue }
            let left = part[..<arrow.lowerBound]
            guard let colon = left.lastIndex(of: ":"), let port = Int(left[left.index(after: colon)...]) else { continue }
            if !out.contains(port) { out.append(port) }
        }
        return out
    }

    static func list(binary: String? = binary) -> (DockerState, [DockerContainer]) {
        guard let binary else { return (.notInstalled, []) }
        guard let r = Shell.run(binary, ["ps", "-a", "--format", "{{json .}}"], timeout: 8) else {
            return (.notRunning("Docker komutu çalıştırılamadı"), [])
        }
        guard r.status == 0 else {
            let err = r.err.lowercased()
            let reason = err.contains("daemon") || err.contains("connect") ? "Docker Desktop kapalı" : r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            return (.notRunning(reason), [])
        }
        return (.ready, parse(r.out))
    }

    /// Hata olursa açıklamasını döndürür.
    static func setRunning(_ c: DockerContainer, _ on: Bool, binary: String? = binary) -> String? {
        guard let binary else { return "Docker kurulu değil" }
        guard let r = Shell.run(binary, [on ? "start" : "stop", c.id], timeout: 40) else { return "Docker komutu çalıştırılamadı" }
        return r.status == 0 ? nil : r.err.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
