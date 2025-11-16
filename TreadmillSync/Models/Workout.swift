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
    let totalSteps: Int64?
    let avgSpeed: Double?
    let maxSpeed: Double?
    let totalCalories: Int64?
    let samplesUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case workoutUuid = "workout_uuid"
        case startTime = "start_time"
        case endTime = "end_time"
        case totalDuration = "total_duration"
        case totalDistance = "total_distance"
        case totalSteps = "total_steps"
        case avgSpeed = "avg_speed"
        case maxSpeed = "max_speed"
        case totalCalories = "total_calories"
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
    let distance: Int64?
    let calories: Int64?
    let steps: Int64? // cumulative step count

    enum CodingKeys: String, CodingKey {
        case timestamp
        case speed
        case distance
        case calories
        case steps = "cadence" // Backend uses 'cadence' column for steps
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

// MARK: - Live Workout Data

struct LiveWorkoutResponse: Codable {
    let workout: Workout?
    let currentMetrics: LiveWorkoutMetrics?
    let recentSamples: [WorkoutSample]

    enum CodingKeys: String, CodingKey {
        case workout
        case currentMetrics = "current_metrics"
        case recentSamples = "recent_samples"
    }
}

struct LiveWorkoutMetrics: Codable {
    let currentSpeed: Double?
    let distanceSoFar: Int64?
    let stepsSoFar: Int64?
    let caloriesSoFar: Int64?

    enum CodingKeys: String, CodingKey {
        case currentSpeed = "current_speed"
        case distanceSoFar = "distance_so_far"
        case stepsSoFar = "steps_so_far"
        case caloriesSoFar = "calories_so_far"
    }

    var speedFormatted: String {
        guard let speed = currentSpeed else { return "0.0" }
        let mph = speed * 2.23694 // m/s to mph
        return String(format: "%.1f", mph)
    }

    var distanceFormatted: String {
        guard let meters = distanceSoFar else { return "0.00" }
        let miles = Double(meters) / 1609.34
        return String(format: "%.2f", miles)
    }

    var stepsFormatted: String {
        guard let steps = stepsSoFar else { return "0" }
        return "\(steps)"
    }

    var caloriesFormatted: String {
        guard let cal = caloriesSoFar else { return "0" }
        return "\(cal)"
    }
}
