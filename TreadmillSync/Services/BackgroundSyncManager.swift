import Foundation
import BackgroundTasks

class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    private let taskIdentifier = "com.treadmillsync.refresh"

    // Register the background task handler
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }
    }

    // Schedule the next background sync
    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60) // 2 hours from now

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background sync: \(error)")
        }
    }

    // Handle the background sync task
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        // Schedule the next sync
        scheduleBackgroundSync()

        // Create a task to perform the sync
        let syncTask = Task {
            await performSync()
        }

        // Set expiration handler
        task.expirationHandler = {
            syncTask.cancel()
        }

        // Mark task as complete when done
        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }

    // Perform the actual sync
    private func performSync() async {
        let config = ServerConfig.load()
        let apiClient = APIClient(config: config)
        let healthKitManager = HealthKitManager.shared

        do {
            // Fetch all activity dates
            let dates = try await apiClient.fetchActivityDates()

            var allSummaries: [DailySummary] = []
            for date in dates {
                if let summary = try? await apiClient.fetchDailySummary(date: date) {
                    allSummaries.append(summary)
                }
            }

            // Sync previous days that haven't been synced yet
            for summary in allSummaries.filter({ !$0.isSynced && !$0.isToday }) {
                do {
                    let samples = try await apiClient.fetchSamples(date: summary.date)

                    try await healthKitManager.saveWorkout(
                        date: summary.date,
                        samples: samples,
                        distanceMeters: summary.distanceMeters,
                        calories: summary.calories,
                        steps: summary.steps
                    )

                    try await apiClient.markDateSynced(date: summary.date)
                } catch {
                    // Continue on error
                    continue
                }
            }
        } catch {
            // Background sync failed, will retry next time
            print("Background sync failed: \(error)")
        }
    }
}
