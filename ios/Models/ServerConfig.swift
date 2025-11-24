import Foundation

extension Notification.Name {
    static let serverConfigDidChange = Notification.Name("serverConfigDidChange")
}

struct ServerConfig: Codable {
    var host: String
    var port: Int
    var useHTTPS: Bool

    static let `default` = ServerConfig(
        host: "localhost",
        port: 8080,
        useHTTPS: false
    )

    var baseURL: String {
        let scheme = useHTTPS ? "https" : "http"
        return "\(scheme)://\(host):\(port)"
    }

    // UserDefaults storage
    static let storageKey = "serverConfig"

    static func load() -> ServerConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func saveAndNotify() {
        save()
        NotificationCenter.default.post(name: .serverConfigDidChange, object: nil)
    }
}
