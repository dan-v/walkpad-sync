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

    // For server communication - server uses UTC for date grouping
    static let yearMonthDayUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

// MARK: - Date-Based API Models (v2)

struct ActivityDatesResponse: Codable {
    let dates: [String] // YYYY-MM-DD format
}

struct AllSummariesResponse: Codable {
    let summaries: [DailySummary]
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
    }

    // Sync state (now tracked locally, not from server)
    var isSynced: Bool {
        SyncStateManager.shared.isSynced(date)
    }

    // Computed properties for display
    var dateDisplay: Date? {
        // Server now returns dates in user's local timezone
        // Parse as local date for display
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
        SyncStateManager.shared.getSyncedAtFormatted(for: date)
    }

    var syncedAtShort: String? {
        SyncStateManager.shared.getSyncedAtShort(for: date)
    }

    var dayOfWeek: String {
        guard let dateObj = dateDisplay else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: dateObj)
    }

    var isToday: Bool {
        // Server returns dates in user's local timezone
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
    let distanceTotal: Int64?  // Cumulative (for debugging)
    let caloriesTotal: Int64?  // Cumulative (for debugging)
    let stepsTotal: Int64?     // Cumulative (for debugging)
    let distanceDelta: Int64?  // Delta since last sample (USE THIS!)
    let caloriesDelta: Int64?  // Delta since last sample (USE THIS!)
    let stepsDelta: Int64?     // Delta since last sample (USE THIS!)

    var id: Int64 { timestamp }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case speed
        case distanceTotal = "distance_total"
        case caloriesTotal = "calories_total"
        case stepsTotal = "steps_total"
        case distanceDelta = "distance_delta"
        case caloriesDelta = "calories_delta"
        case stepsDelta = "steps_delta"
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

