import HealthKit

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    private lazy var typesToWrite: Set<HKSampleType> = {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]

        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distanceType)
        }
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energyType)
        }
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepType)
        }

        return types
    }()

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: typesToWrite, read: [])
    }

    // MARK: - Delete Existing Workouts

    /// Delete any existing workouts for a specific date to prevent duplicates
    private func deleteExistingWorkouts(for date: String) async throws {
        print("🗑️ Checking for existing workouts on \(date)")

        // Parse the date string to get start/end of day
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        guard let dayStart = formatter.date(from: date) else {
            print("❌ Failed to parse date: \(date)")
            return
        }

        let calendar = Calendar.current
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            print("❌ Failed to calculate day end")
            return
        }

        print("🔍 Querying workouts from \(dayStart) to \(dayEnd)")

        // Query for workouts in this date range
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)

        // Create a query to find existing workouts
        let workouts = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    print("❌ Query error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = samples as? [HKWorkout] ?? []
                print("📊 Found \(workouts.count) existing workouts")
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }

        // Delete all found workouts
        if !workouts.isEmpty {
            print("🗑️ Deleting \(workouts.count) existing workouts")
            try await healthStore.delete(workouts)
            print("✅ Deleted successfully")
        } else {
            print("ℹ️ No existing workouts to delete")
        }
    }

    // MARK: - Save Workout from Date

    func saveWorkout(
        date: String,
        samples: [TreadmillSample],
        distanceMeters: Int64,
        calories: Int64,
        steps: Int64
    ) async throws {
        guard let firstSample = samples.first,
              let lastSample = samples.last else {
            throw HealthKitError.invalidData
        }

        // Delete any existing workouts for this date first (prevents duplicates)
        try await deleteExistingWorkouts(for: date)

        let startDate = firstSample.date
        let endDate = lastSample.date

        // Create workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .indoor

        // Create workout builder
        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        // Begin workout collection
        try await builder.beginCollection(at: startDate)

        // Add samples to builder
        var workoutSamples: [HKSample] = []

        // Process samples to create deltas (HealthKit wants changes, not cumulative values)
        var lastDistance: Int64 = 0
        var lastCalories: Int64 = 0
        var lastSteps: Int64 = 0

        for sample in samples {
            let sampleDate = sample.date

            // Distance delta
            if let distanceTotal = sample.distanceTotal, distanceTotal > lastDistance {
                let delta = distanceTotal - lastDistance
                if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                    let quantity = HKQuantity(unit: .meter(), doubleValue: Double(delta))
                    let distanceSample = HKQuantitySample(
                        type: distanceType,
                        quantity: quantity,
                        start: sampleDate,
                        end: sampleDate
                    )
                    workoutSamples.append(distanceSample)
                }
                lastDistance = distanceTotal
            }

            // Energy delta
            if let caloriesTotal = sample.caloriesTotal, caloriesTotal > lastCalories {
                let delta = caloriesTotal - lastCalories
                if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                    let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(delta))
                    let energySample = HKQuantitySample(
                        type: energyType,
                        quantity: quantity,
                        start: sampleDate,
                        end: sampleDate
                    )
                    workoutSamples.append(energySample)
                }
                lastCalories = caloriesTotal
            }

            // Steps delta
            if let stepsTotal = sample.stepsTotal, stepsTotal > lastSteps {
                let delta = stepsTotal - lastSteps
                if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
                    let quantity = HKQuantity(unit: .count(), doubleValue: Double(delta))
                    let stepSample = HKQuantitySample(
                        type: stepType,
                        quantity: quantity,
                        start: sampleDate,
                        end: sampleDate
                    )
                    workoutSamples.append(stepSample)
                }
                lastSteps = stepsTotal
            }
        }

        // Add samples to workout
        if !workoutSamples.isEmpty {
            try await builder.addSamples(workoutSamples)
        }

        // End collection and finish workout
        try await builder.endCollection(at: endDate)
        _ = try await builder.finishWorkout()
    }
}

// MARK: - Errors

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case invalidData
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .invalidData:
            return "Invalid workout data"
        case .authorizationDenied:
            return "HealthKit authorization was denied"
        }
    }
}
