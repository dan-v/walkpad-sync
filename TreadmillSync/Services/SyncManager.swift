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
            for workout in pending {
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
                    // Continue with next workout even if one fails
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
        // TODO: Show user notification or toast
        print("Successfully synced \(count) workout(s) to Health")
    }
}
