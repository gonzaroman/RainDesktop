import AppKit

/// Pregunta a GitHub cuál es la última versión publicada y avisa si hay una más nueva.
///
/// Es la única conexión que hace la app: una petición a la API pública de GitHub, sin cookies ni caché,
/// que no envía nada del usuario. La instalación sigue siendo manual (botón «Descargar»).
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String
        let url: URL
        let notes: String
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed
    }

    @Published private(set) var state: State = .idle
    /// Se llama en el hilo principal cada vez que cambia el estado (para el puntito del icono).
    var onChange: ((State) -> Void)?

    /// Si está activado, comprueba solo al arrancar y una vez al día.
    var automatic = true {
        didSet { if automatic && !oldValue { checkIfDue() } }
    }

    private static let endpoint = URL(string: "https://api.github.com/repos/gonzaroman/RainDesktop/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    /// Tiempo mínimo entre comprobaciones automáticas.
    private static let interval: TimeInterval = 20 * 3600

    /// Versión instalada. `--pretend-version 0.9` la sustituye para probar el aviso.
    let currentVersion: String = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--pretend-version"), i + 1 < args.count { return args[i + 1] }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }()

    private var timer: Timer?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Empieza las comprobaciones automáticas: a los 10 s de arrancar y luego cada 6 h si toca.
    func start() {
        guard !StudioMode.isActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func checkIfDue() {
        guard automatic, !StudioMode.isActive else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        // Con `--pretend-version` se comprueba siempre, para poder probarlo.
        let pretending = CommandLine.arguments.contains("--pretend-version")
        guard pretending || Date().timeIntervalSince(last) >= Self.interval else { return }
        check()
    }

    /// Comprueba ahora mismo (botón «Buscar ahora»).
    func check() {
        guard !StudioMode.isActive, state != .checking else { return }
        set(.checking)

        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RainDesktop/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, _ in
            let release = Self.parse(data: data, response: response)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let release else {
                    self.set(.failed)
                    return
                }
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                let newer = Self.compare(release.version, self.currentVersion) == .orderedDescending
                self.set(newer ? .available(release) : .upToDate)
            }
        }.resume()
    }

    private func set(_ new: State) {
        guard new != state else { return }
        state = new
        onChange?(new)
    }

    private static func parse(data: Data?, response: URLResponse?) -> Release? {
        guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String,
              let page = json["html_url"] as? String, let url = URL(string: page) else { return nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return Release(version: version, url: url, notes: json["body"] as? String ?? "")
    }

    /// Compara versiones por partes numéricas: 1.10 > 1.9 y 1.0 == 1.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
