import Foundation

// MARK: - Cached Formatters

private enum DateFormatters {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let yearMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // Use local timezone for display purposes
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

// MARK: - Date-Based API Models (v2)

struct ActivityDatesResponse: Codable {
    let dates: [String] // YYYY-MM-DD format
}

struct DailySummary: Codable, Identifiable {
    let date: String // YYYY-MM-DD
    let totalSamples: Int64
    let durationSeconds: Int64
    let distanceMeters: Int64
    let calories: Int64
    let steps: Int64
    let avgSpeed: Double // m/s
    let maxSpeed: Double
    let isSynced: Bool
    let syncedAt: Int64? // Unix timestamp when synced (nil if not synced)

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date
        case totalSamples = "total_samples"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case calories
        case steps
        case avgSpeed = "avg_speed"
        case maxSpeed = "max_speed"
        case isSynced = "is_synced"
        case syncedAt = "synced_at"
    }

    // Computed properties for display
    var dateDisplay: Date? {
        DateFormatters.yearMonthDay.date(from: date)
    }

    var dateFormatted: String {
        guard let dateObj = dateDisplay else { return date }
        return DateFormatters.dateOnly.string(from: dateObj)
    }

    var durationFormatted: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var distanceFormatted: String {
        let miles = Double(distanceMeters) / 1609.34
        return String(format: "%.2f mi", miles)
    }

    var caloriesFormatted: String {
        return "\(calories) kcal"
    }

    var stepsFormatted: String {
        return "\(steps)"
    }

    var avgSpeedFormatted: String {
        let mph = avgSpeed * 2.23694 // m/s to mph
        return String(format: "%.1f mph", mph)
    }

    var syncedAtFormatted: String? {
        guard let syncedAt = syncedAt else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(syncedAt))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Synced " + formatter.localizedString(for: date, relativeTo: Date())
    }

    var syncedAtShort: String? {
        guard let syncedAt = syncedAt else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(syncedAt))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var dayOfWeek: String {
        guard let dateObj = dateDisplay else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: dateObj)
    }

    var isToday: Bool {
        let calendar = Calendar.current
        let todayStr = DateFormatters.yearMonthDay.string(from: Date())
        return date == todayStr
    }
}

struct SamplesResponse: Codable {
    let date: String
    let samples: [TreadmillSample]
}

struct TreadmillSample: Codable, Identifiable {
    let timestamp: Int64 // Unix epoch
    let speed: Double?
    let distanceTotal: Int64?
    let caloriesTotal: Int64?
    let stepsTotal: Int64?

    var id: Int64 { timestamp }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case speed
        case distanceTotal = "distance_total"
        case caloriesTotal = "calories_total"
        case stepsTotal = "steps_total"
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

struct SyncedDatesResponse: Codable {
    let syncedDates: [HealthSync]

    enum CodingKeys: String, CodingKey {
        case syncedDates = "synced_dates"
    }
}

struct HealthSync: Codable {
    let syncDate: String // YYYY-MM-DD
    let syncedAt: Int64 // Unix timestamp

    enum CodingKeys: String, CodingKey {
        case syncDate = "sync_date"
        case syncedAt = "synced_at"
    }
}
