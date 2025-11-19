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

        return types
    }()

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: typesToWrite, read: [])
    }

    // MARK: - Save Workout

    func saveWorkout(
        _ workout: Workout,
        samples: [WorkoutSample]
    ) async throws -> UUID {
        guard let startDate = workout.start,
              let endDate = workout.end else {
            print("❌ Workout \(workout.id): Missing start or end date")
            throw HealthKitError.invalidData
        }

        print("📝 Syncing workout \(workout.id): \(startDate) to \(endDate)")
        print("   Duration: \(workout.totalDuration ?? 0)s, Distance: \(workout.totalDistance ?? 0)m, Samples: \(samples.count)")

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
        do {
            try await builder.beginCollection(at: startDate)
            print("✅ Collection started")
        } catch {
            print("❌ Failed to begin collection: \(error)")
            throw error
        }

        // Create workout samples (distance points, energy, etc.)
        var workoutSamples: [HKSample] = []

        for sample in samples {
            guard let sampleDate = sample.date else { continue }

            // Distance samples (cumulative)
            if let distance = sample.distance, distance > 0,
               let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: Double(distance))
                let distanceSample = HKQuantitySample(
                    type: distanceType,
                    quantity: distanceQuantity,
                    start: sampleDate,
                    end: sampleDate
                )
                workoutSamples.append(distanceSample)
            }

            // Energy samples (cumulative)
            if let calories = sample.calories, calories > 0,
               let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(calories))
                let energySample = HKQuantitySample(
                    type: energyType,
                    quantity: energyQuantity,
                    start: sampleDate,
                    end: sampleDate
                )
                workoutSamples.append(energySample)
            }
        }

        // Add samples to builder
        if !workoutSamples.isEmpty {
            do {
                try await builder.addSamples(workoutSamples)
                print("✅ Added \(workoutSamples.count) samples to builder")
            } catch {
                print("❌ Failed to add samples: \(error)")
                throw error
            }
        } else {
            print("⚠️ No samples to add")
        }

        // Add metadata
        do {
            try await builder.addMetadata([HKMetadataKeyIndoorWorkout: true])
            print("✅ Metadata added")
        } catch {
            print("❌ Failed to add metadata: \(error)")
            throw error
        }

        // End workout collection
        do {
            try await builder.endCollection(at: endDate)
            print("✅ Collection ended")
        } catch {
            print("❌ Failed to end collection: \(error)")
            throw error
        }

        // Finish the workout and get the result
        print("🏁 Finishing workout...")
        let finishedWorkout: HKWorkout?
        do {
            finishedWorkout = try await builder.finishWorkout()
        } catch {
            print("❌ Failed to finish workout: \(error)")
            throw error
        }

        guard let finishedWorkout = finishedWorkout else {
            print("❌ finishWorkout() returned nil (workout rejected by HealthKit)")
            throw HealthKitError.invalidData
        }

        print("✅ Workout saved successfully! UUID: \(finishedWorkout.uuid)")
        return finishedWorkout.uuid
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .invalidData:
            return "Invalid workout data"
        }
    }
}
