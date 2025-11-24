import Foundation

enum UnitPreference: String, Codable, CaseIterable {
    case imperial
    case metric

    var distanceUnit: String {
        switch self {
        case .imperial: return "mi"
        case .metric: return "km"
        }
    }

    var speedUnit: String {
        switch self {
        case .imperial: return "mph"
        case .metric: return "km/h"
        }
    }

    // Convert meters to preferred distance unit
    func formatDistance(_ meters: Int64) -> String {
        switch self {
        case .imperial:
            let miles = Double(meters) / 1609.34
            return String(format: "%.2f mi", miles)
        case .metric:
            let km = Double(meters) / 1000.0
            return String(format: "%.2f km", km)
        }
    }

    // Convert m/s to preferred speed unit
    func formatSpeed(_ metersPerSecond: Double) -> String {
        switch self {
        case .imperial:
            let mph = metersPerSecond * 2.23694
            return String(format: "%.1f mph", mph)
        case .metric:
            let kmh = metersPerSecond * 3.6
            return String(format: "%.1f km/h", kmh)
        }
    }

    static let storageKey = "unitPreference"

    static func load() -> UnitPreference {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let preference = UnitPreference(rawValue: raw) else {
            return .imperial // Default
        }
        return preference
    }

    func save() {
        UserDefaults.standard.set(self.rawValue, forKey: Self.storageKey)
    }
}
