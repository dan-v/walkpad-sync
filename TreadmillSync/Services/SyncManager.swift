import Foundation
import SwiftUI
import Combine

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
    @Published var liveWorkout: Workout? {
        didSet {
            if let workout = liveWorkout {
                print("🔄 SyncManager.liveWorkout updated to: \(workout.id)")
            } else {
                print("🔄 SyncManager.liveWorkout cleared (nil)")
            }
        }
    }

    private var apiClient: APIClient {
        APIClient(config: serverConfig)
    }

    private let healthKitManager = HealthKitManager.shared
    private var webSocketManager: WebSocketManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupWebSocket()

        Task {
            await checkConnection()
            await loadWorkouts()
        }
    }

    private func setupWebSocket() {
        webSocketManager = WebSocketManager(serverConfig: serverConfig)

        // Subscribe to WebSocket events
        webSocketManager?.eventPublisher
            .sink { [weak self] event in
                Task { @MainActor in
                    await self?.handleWebSocketEvent(event)
                }
            }
            .store(in: &cancellables)

        // Sync live workout state
        webSocketManager?.$currentLiveWorkout
            .assign(to: &$liveWorkout)

        // Start WebSocket connection
        webSocketManager?.connect()
    }

    private func handleWebSocketEvent(_ event: WorkoutEvent) async {
        switch event {
        case .workoutStarted(let workout):
            print("📡 WebSocket: Workout started - \(workout.id)")
            liveWorkout = workout

        case .workoutSample(let workoutId, _):
            print("📡 WebSocket: Sample received for workout \(workoutId)")
            // Samples are handled by live workout views

        case .workoutCompleted(let workout):
            print("📡 WebSocket: Workout completed - \(workout.id)")
            liveWorkout = nil
            // Reload workouts to show the new completed workout
            await loadWorkouts()

        case .workoutFailed(let workoutId, let reason):
            print("📡 WebSocket: Workout \(workoutId) failed - \(reason)")
            liveWorkout = nil

        case .connectionStatus(let connected):
            print("📡 WebSocket: Server status - \(connected ? "connected" : "disconnected")")
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

        // Reconnect WebSocket with new config
        webSocketManager?.disconnect()
        webSocketManager = WebSocketManager(serverConfig: config)
        setupWebSocket()

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
        } catch is CancellationError {
            // Ignore task cancellation errors
            return
        } catch let error as URLError where error.code == .cancelled {
            // Ignore URLSession cancellation errors
            return
        } catch {
            syncError = error
        }
    }

    // MARK: - Live Workout

    func fetchLiveWorkout() async -> LiveWorkoutResponse? {
        guard isConnected else { return nil }

        do {
            return try await apiClient.fetchLiveWorkout()
        } catch {
            // Log error for debugging
            print("❌ Failed to fetch live workout: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("  Type mismatch: expected \(type)")
                    print("  Context: \(context.debugDescription)")
                    print("  Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    print("  Value not found: \(type)")
                    print("  Context: \(context.debugDescription)")
                case .keyNotFound(let key, let context):
                    print("  Key not found: \(key.stringValue)")
                    print("  Context: \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("  Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("  Unknown decoding error")
                }
            }
            return nil
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

        } catch is CancellationError {
            // Ignore task cancellation errors
        } catch let error as URLError where error.code == .cancelled {
            // Ignore URLSession cancellation errors
        } catch {
            syncError = error
        }

        isSyncing = false
    }

    func performBackgroundSync() async {
        // Background sync is more conservative
        await performSync()
    }

    // MARK: - Individual Workout Actions

    func syncWorkout(_ workout: Workout) async {
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil
        syncSuccessMessage = nil

        do {
            // Skip workouts that are incomplete (no end time)
            guard workout.endTime != nil else {
                syncError = NSError(
                    domain: "SyncManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot sync in-progress workout"]
                )
                isSyncing = false
                return
            }

            // Skip workouts with no meaningful data
            if (workout.totalDistance ?? 0) == 0 && (workout.totalCalories ?? 0) == 0 {
                syncError = NSError(
                    domain: "SyncManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot sync workout with no distance or calories"]
                )
                isSyncing = false
                return
            }

            // Fetch samples
            let samples = try await apiClient.fetchWorkoutSamples(workoutId: workout.id)

            // Save to HealthKit
            let healthKitUUID = try await healthKitManager.saveWorkout(workout, samples: samples)

            // Confirm sync with server
            try await apiClient.confirmSync(workoutId: workout.id, healthKitUUID: healthKitUUID)

            // Reload workouts to update list
            await loadWorkouts()

            syncSuccessMessage = "Successfully synced workout to Apple Health"

        } catch is CancellationError {
            // Ignore task cancellation errors
        } catch let error as URLError where error.code == .cancelled {
            // Ignore URLSession cancellation errors
        } catch {
            syncError = NSError(
                domain: "SyncManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to sync workout: \(error.localizedDescription)"]
            )
        }

        isSyncing = false
    }

    func deleteWorkout(_ workout: Workout) async {
        do {
            try await apiClient.deleteWorkout(workoutId: workout.id)

            // Reload workouts to update list
            await loadWorkouts()

        } catch is CancellationError {
            // Ignore task cancellation errors
        } catch let error as URLError where error.code == .cancelled {
            // Ignore URLSession cancellation errors
        } catch {
            syncError = NSError(
                domain: "SyncManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete workout: \(error.localizedDescription)"]
            )
        }
    }

    // MARK: - Notifications

    private func showSuccessNotification(count: Int) {
        let message = count == 1
            ? "Successfully synced 1 workout to Apple Health"
            : "Successfully synced \(count) workouts to Apple Health"
        syncSuccessMessage = message
    }
}
