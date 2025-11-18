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
}

// MARK: - API Response Models

struct PendingWorkoutsResponse: Codable {
    let workouts: [Workout]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case workouts
        case hasMore = "has_more"
    }
}

struct Workout: Codable, Identifiable {
    let id: Int64
    let workoutUuid: String
    let startTime: String
    let endTime: String?
    let totalDuration: Int64?
    let totalDistance: Int64?
    let avgSpeed: Double?
    let maxSpeed: Double?
    let avgIncline: Double?
    let maxIncline: Double?
    let totalCalories: Int64?
    let avgHeartRate: Int64?
    let maxHeartRate: Int64?
    let samplesUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case workoutUuid = "workout_uuid"
        case startTime = "start_time"
        case endTime = "end_time"
        case totalDuration = "total_duration"
        case totalDistance = "total_distance"
        case avgSpeed = "avg_speed"
        case maxSpeed = "max_speed"
        case avgIncline = "avg_incline"
        case maxIncline = "max_incline"
        case totalCalories = "total_calories"
        case avgHeartRate = "avg_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case samplesUrl = "samples_url"
    }

    // Computed properties for display
    var start: Date? {
        DateFormatters.iso8601.date(from: startTime)
    }

    var end: Date? {
        guard let endTime = endTime else { return nil }
        return DateFormatters.iso8601.date(from: endTime)
    }

    var durationFormatted: String {
        guard let duration = totalDuration else { return "N/A" }
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var distanceFormatted: String {
        guard let meters = totalDistance else { return "N/A" }
        let miles = Double(meters) / 1609.34
        return String(format: "%.2f mi", miles)
    }

    var caloriesFormatted: String {
        guard let calories = totalCalories else { return "N/A" }
        return "\(calories) kcal"
    }

    var dateFormatted: String {
        guard let start = start else { return "Unknown" }
        return DateFormatters.display.string(from: start)
    }
}

struct SamplesResponse: Codable {
    let samples: [WorkoutSample]
}

struct WorkoutSample: Codable, Identifiable {
    var id: String { timestamp }

    let timestamp: String
    let speed: Double?
    let incline: Double?
    let distance: Int64?
    let heartRate: Int64?
    let calories: Int64?
    let cadence: Int64?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case speed
        case incline
        case distance
        case heartRate = "heart_rate"
        case calories
        case cadence
    }

    var date: Date? {
        DateFormatters.iso8601.date(from: timestamp)
    }
}

struct ConfirmSyncRequest: Codable {
    let deviceId: String
    let healthkitUuid: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case healthkitUuid = "healthkit_uuid"
    }
}

struct RegisterRequest: Codable {
    let deviceId: String
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
    }
}
