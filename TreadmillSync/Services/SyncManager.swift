import Foundation
import SwiftUI

@MainActor
class SyncManager: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?
    @Published var serverConfig = ServerConfig.load()
    @Published var isConnected = false
    @Published var pendingCount: Int = 0
    @Published var syncSuccessMessage: String?

    private var apiClient: APIClient {
        APIClient(config: serverConfig)
    }

    private let healthKitManager = HealthKitManager.shared

    init() {
        Task {
            await loadWorkouts()
            await checkConnection()
        }
    }

    // MARK: - Connection

    func checkConnection() async {
        do {
            isConnected = try await apiClient.checkConnection()
        } catch {
            isConnected = false
        }
    }

    func updateServerConfig(_ config: ServerConfig) async {
        serverConfig = config
        config.save()
        await checkConnection()
        await loadWorkouts()
    }

    // MARK: - Load Workouts

    func loadWorkouts() async {
        guard isConnected else { return }

        do {
            // Register device on first load
            try await apiClient.registerDevice()

            // Fetch pending workouts
            let pending = try await apiClient.fetchPendingWorkouts()
            workouts = pending
            pendingCount = pending.count
        } catch {
            syncError = error
        }
    }

    // MARK: - Sync

    func syncIfNeeded() async {
        // Only auto-sync if it's been more than 10 minutes
        if let lastSync = lastSyncDate,
           Date().timeIntervalSince(lastSync) < 600 {
            return
        }

        await performSync()
    }

    func performSync() async {
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil
        syncSuccessMessage = nil

        do {
            // Check connection first
            await checkConnection()
            guard isConnected else {
                throw APIError.networkError
            }

            // Fetch pending workouts
            let pending = try await apiClient.fetchPendingWorkouts()
            workouts = pending
            pendingCount = pending.count

            // Sync each workout to HealthKit
            var successCount = 0
            var failedWorkouts: [(Int64, Error)] = []
            var skippedWorkouts: [Int64] = []

            for workout in pending {
                // Skip workouts that are incomplete (no end time)
                guard workout.endTime != nil else {
                    print("⚠️ Skipping workout \(workout.id): still in progress (no end time)")
                    skippedWorkouts.append(workout.id)
                    continue
                }

                // Skip workouts with no meaningful data (zero distance and zero calories)
                // HealthKit rejects these as invalid
                if (workout.totalDistance ?? 0) == 0 && (workout.totalCalories ?? 0) == 0 {
                    print("⚠️ Skipping workout \(workout.id): no distance or calories recorded")
                    skippedWorkouts.append(workout.id)
                    continue
                }

                do {
                    // Fetch samples
                    let samples = try await apiClient.fetchWorkoutSamples(workoutId: workout.id)

                    // Save to HealthKit
                    let healthKitUUID = try await healthKitManager.saveWorkout(workout, samples: samples)

                    // Confirm sync with server
                    try await apiClient.confirmSync(workoutId: workout.id, healthKitUUID: healthKitUUID)

                    successCount += 1
                } catch {
                    print("Failed to sync workout \(workout.id): \(error)")
                    failedWorkouts.append((workout.id, error))
                    // Continue with next workout even if one fails
                }
            }

            // Report skipped workouts
            if !skippedWorkouts.isEmpty {
                let skippedIds = skippedWorkouts.map { "\($0)" }.joined(separator: ", ")
                print("ℹ️ Skipped in-progress workouts: \(skippedIds)")
            }

            // Report failures if any
            if !failedWorkouts.isEmpty {
                let failedIds = failedWorkouts.map { "\($0.0)" }.joined(separator: ", ")
                print("⚠️ Failed to sync workouts: \(failedIds)")

                // Show detailed error for first failure
                if let firstError = failedWorkouts.first {
                    syncError = NSError(
                        domain: "SyncManager",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Failed to sync workout \(firstError.0): \(firstError.1.localizedDescription)"
                        ]
                    )
                }
            }

            // Reload to get updated list
            await loadWorkouts()

            lastSyncDate = Date()

            // Show success notification
            if successCount > 0 {
                showSuccessNotification(count: successCount)
            }

        } catch {
            syncError = error
        }

        isSyncing = false
    }

    func performBackgroundSync() async {
        // Background sync is more conservative
        await performSync()
    }

    // MARK: - Notifications

    private func showSuccessNotification(count: Int) {
        let message = count == 1
            ? "Successfully synced 1 workout to Apple Health"
            : "Successfully synced \(count) workouts to Apple Health"
        syncSuccessMessage = message
    }
}
