import Foundation

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
}

// Device ID management
extension UserDefaults {
    private static let deviceIDKey = "deviceID"

    static var deviceID: String {
        if let existing = standard.string(forKey: deviceIDKey) {
            return existing
        }

        // Generate stable device ID on first launch
        let newID = UUID().uuidString
        standard.set(newID, forKey: deviceIDKey)
        return newID
    }
}
