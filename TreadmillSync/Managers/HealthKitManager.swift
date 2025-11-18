//
//  HealthKitManager.swift
//  TreadmillSync
//
//  Enhanced HealthKit integration with rich metadata and workout segments
//

import HealthKit
import Foundation
import Observation

/// Workout statistics for display
struct WorkoutStats: Equatable {
    let duration: String
    let steps: Int
    let distance: Double
    let calories: Int

    var formattedSummary: String {
        "\(duration) walk • \(steps) steps • \(String(format: "%.1f", distance)) mi • \(calories) cal"
    }
}

/// Manages HealthKit workout sessions and data collection
@Observable
@MainActor
class HealthKitManager {

    // MARK: - Singleton

    static let shared = HealthKitManager()

    // MARK: - Published State

    private(set) var isAuthorized = false
    private(set) var isWorkoutActive = false
    private(set) var lastErrorDescription: String?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutStartDate: Date?
    private var lastSampleDate: Date?
    private var lastSyncedData = TreadmillData()

    // MARK: - Initialization

    private init() {}

    // MARK: - Authorization

    /// Request HealthKit authorization
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        print("\n📋 Requesting HealthKit authorization...")

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: [])
            isAuthorized = true
            lastErrorDescription = nil
            print("✅ HealthKit authorized")
        } catch {
            lastErrorDescription = error.localizedDescription
            print("❌ HealthKit authorization failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Daily Workout Save

    /// Save accumulated daily session as a single workout
    func saveDailyWorkout(from session: DailySession) async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        guard session.totalSteps > 0 else {
            throw HealthKitError.custom("No treadmill data to save yet")
        }

        // Validate session data before saving
        try validateSession(session)

        print("\n💾 Saving daily workout to HealthKit...")
        print("  📊 Steps: \(session.totalSteps)")
        print("  📏 Distance: \(String(format: "%.2f", session.totalDistanceMiles)) mi")
        print("  🔥 Calories: \(session.totalCalories)")
        print("  ⏱️ Duration: \(session.formattedDuration)")

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        let start = session.startDate
        let end = session.lastUpdated ?? start

        try await builder.beginCollection(at: start)

        var samples: [HKQuantitySample] = []

        // Add steps sample
        if session.totalSteps > 0 {
            let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
            let quantity = HKQuantity(unit: .count(), doubleValue: Double(session.totalSteps))
            samples.append(HKQuantitySample(type: stepType, quantity: quantity, start: start, end: end))
        }

        // Add distance sample (convert miles to meters)
        if session.totalDistanceMiles > 0 {
            let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let meters = session.totalDistanceMiles * 1609.34
            let quantity = HKQuantity(unit: .meter(), doubleValue: meters)
            samples.append(HKQuantitySample(type: distType, quantity: quantity, start: start, end: end))
        }

        // Add calories sample
        if session.totalCalories > 0 {
            let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(session.totalCalories))
            samples.append(HKQuantitySample(type: calType, quantity: quantity, start: start, end: end))
        }

        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        // Add rich metadata
        let metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: true,
            "TreadmillModel": "LifeSpan TR1200B",
            "WorkoutType": "Desk Walking",
            "SessionCount": session.activitySegments.count,
            "AppVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]

        builder.metadata = metadata

        // Add workout segments for each activity period
        for segment in session.activitySegments {
            let workoutSegment = HKWorkoutActivity(
                workoutConfiguration: configuration,
                start: segment.startTime,
                end: segment.endTime,
                metadata: [
                    "SegmentSteps": segment.steps,
                    "SegmentDistance": segment.distanceMiles,
                    "SegmentCalories": segment.calories
                ]
            )
            builder.add(workoutSegment)
        }

        try await builder.endCollection(at: end)
        let workoutResult = try await builder.finishWorkout()

        print("✅ Workout saved to HealthKit")

        if workoutResult != nil {
            let stats = WorkoutStats(
                duration: session.formattedDuration,
                steps: session.totalSteps,
                distance: session.totalDistanceMiles,
                calories: session.totalCalories
            )
            await notifyWorkoutCompleted(stats: stats)
        }
    }

    // MARK: - Live Workout Session (Optional - for real-time tracking)

    /// Start a live workout session
    func startWorkout() async throws {
        guard !isWorkoutActive else {
            print("⚠️ Workout already in progress")
            return
        }

        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        print("\n🏃 Starting live workout session...")

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession = session

            let builder = session.associatedWorkoutBuilder()
            workoutBuilder = builder

            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            let startDate = Date()
            workoutStartDate = startDate

            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            lastSyncedData = TreadmillData()
            lastSampleDate = startDate
            lastErrorDescription = nil

            isWorkoutActive = true
            print("✅ Live workout session started")
        } catch {
            lastErrorDescription = error.localizedDescription
            print("❌ Failed to start workout: \(error.localizedDescription)")
            throw error
        }
    }

    /// Add treadmill data samples to live workout
    func addWorkoutData(_ data: TreadmillData) async throws {
        guard let builder = workoutBuilder,
              let startDate = workoutStartDate,
              isWorkoutActive else {
            return
        }

        var samples: [HKQuantitySample] = []
        let now = Date()
        let sampleStart = lastSampleDate ?? startDate

        // Add step count delta
        if let stepDelta = delta(current: data.steps, previous: lastSyncedData.steps),
           stepDelta > 0 {
            let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
            let stepQuantity = HKQuantity(unit: .count(), doubleValue: Double(stepDelta))
            let stepSample = HKQuantitySample(
                type: stepType,
                quantity: stepQuantity,
                start: sampleStart,
                end: now
            )
            samples.append(stepSample)
        }

        // Add distance delta (convert miles to meters)
        if let distanceDelta = delta(current: data.distance, previous: lastSyncedData.distance),
           distanceDelta > 0 {
            let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let meters = distanceDelta * 1609.34
            let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: meters)
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: distanceQuantity,
                start: sampleStart,
                end: now
            )
            samples.append(distanceSample)
        }

        // Add calories delta
        if let calorieDelta = delta(current: data.calories, previous: lastSyncedData.calories),
           calorieDelta > 0 {
            let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            let calorieQuantity = HKQuantity(
                unit: .kilocalorie(),
                doubleValue: Double(calorieDelta)
            )
            let calorieSample = HKQuantitySample(
                type: calorieType,
                quantity: calorieQuantity,
                start: sampleStart,
                end: now
            )
            samples.append(calorieSample)
        }

        if !samples.isEmpty {
            try await builder.addSamples(samples)
            lastSampleDate = now
            print("  ✅ Added \(samples.count) samples to live workout")
        }

        lastSyncedData = data
        lastErrorDescription = nil
    }

    /// End live workout session
    func endWorkout() async throws {
        guard let session = workoutSession,
              let builder = workoutBuilder,
              isWorkoutActive else {
            return
        }

        print("\n⏹️ Ending live workout session...")

        let endDate = Date()

        do {
            session.end()
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()

            print("✅ Live workout saved to HealthKit")
            lastErrorDescription = nil

            if let startDate = workoutStartDate, let workout = workout {
                let duration = endDate.timeIntervalSince(startDate)
                let hours = Int(duration) / 3600
                let minutes = (Int(duration) % 3600) / 60
                let seconds = Int(duration) % 60

                let durationString: String
                if hours > 0 {
                    durationString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
                } else {
                    durationString = String(format: "%d:%02d", minutes, seconds)
                }

                let stats = await extractWorkoutStats(from: workout, duration: durationString)
                await notifyWorkoutCompleted(stats: stats)
            }
        } catch {
            lastErrorDescription = error.localizedDescription
            print("❌ Failed to finish workout: \(error.localizedDescription)")
            throw error
        }

        workoutSession = nil
        workoutBuilder = nil
        workoutStartDate = nil
        lastSampleDate = nil
        lastSyncedData = TreadmillData()
        isWorkoutActive = false
    }

    // MARK: - Private Helpers

    private func extractWorkoutStats(from workout: HKWorkout, duration: String) async -> WorkoutStats {
        let steps = workout.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .mile()) ?? 0
        let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0

        return WorkoutStats(
            duration: duration,
            steps: Int(steps),
            distance: distance,
            calories: Int(calories)
        )
    }

    private func notifyWorkoutCompleted(stats: WorkoutStats) async {
        NotificationCenter.default.post(
            name: .workoutCompleted,
            object: stats
        )
    }

    private func validateSession(_ session: DailySession) throws {
        // Validate workout duration is reasonable (< 24 hours)
        guard let endDate = session.lastUpdated else {
            throw HealthKitError.custom("Invalid session - no end time")
        }

        let duration = endDate.timeIntervalSince(session.startDate)
        guard duration > 0 && duration < 86400 else { // 24 hours
            throw HealthKitError.custom("Invalid workout duration")
        }

        // Validate data values are reasonable
        let maxStepsPerHour: Double = 10000
        let hoursElapsed = duration / 3600.0
        let maxExpectedSteps = Int(maxStepsPerHour * hoursElapsed * 2) // 2x buffer

        guard session.totalSteps <= maxExpectedSteps else {
            throw HealthKitError.custom("Step count seems unreasonably high - please check data")
        }

        guard session.totalDistanceMiles <= 100 else { // 100 miles in one day is unreasonable for walking
            throw HealthKitError.custom("Distance seems unreasonably high - please check data")
        }

        guard session.totalCalories <= 10000 else { // 10k calories in one workout is unreasonable
            throw HealthKitError.custom("Calorie count seems unreasonably high - please check data")
        }

        // Validate segment times
        for (index, segment) in session.activitySegments.enumerated() {
            guard segment.endTime > segment.startTime else {
                throw HealthKitError.custom("Invalid segment #\(index + 1) - end time before start time")
            }

            let segmentDuration = segment.endTime.timeIntervalSince(segment.startTime)
            guard segmentDuration < 43200 else { // 12 hours
                throw HealthKitError.custom("Segment #\(index + 1) duration is unreasonably long")
            }

            // Ensure segment is within workout bounds
            guard segment.startTime >= session.startDate && segment.endTime <= endDate else {
                throw HealthKitError.custom("Segment #\(index + 1) is outside workout time range")
            }
        }

        print("✅ Session validation passed")
    }

    private func delta<T: Numeric & Comparable>(current: T?, previous: T?) -> T? {
        guard let current else { return nil }
        guard let previous else { return current }
        let change = current - previous
        return change < 0 ? current : change  // Handle resets
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit authorization required"
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let workoutCompleted = Notification.Name("workoutCompleted")
}
