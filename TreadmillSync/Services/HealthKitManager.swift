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
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRateType)
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
            throw HealthKitError.invalidData
        }

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

        // Create workout samples (heart rate, distance points, etc.)
        var workoutSamples: [HKSample] = []

        for sample in samples {
            guard let sampleDate = sample.date else { continue }

            // Heart rate samples
            if let hr = sample.heartRate, hr > 0,
               let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let hrQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(hr))
                let hrSample = HKQuantitySample(
                    type: heartRateType,
                    quantity: hrQuantity,
                    start: sampleDate,
                    end: sampleDate
                )
                workoutSamples.append(hrSample)
            }

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
            try await builder.addSamples(workoutSamples)
        }

        // Add metadata
        try await builder.addMetadata([HKMetadataKeyIndoorWorkout: true])

        // End workout collection
        try await builder.endCollection(at: endDate)

        // Finish the workout and get the result
        let finishedWorkout = try await builder.finishWorkout()

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
