import SwiftUI

@main
struct TreadmillSyncApp: App {
    @StateObject private var syncManager = SyncManager()
    @StateObject private var healthKitManager = HealthKitManager()

    init() {
        // Request HealthKit permissions on launch
        Task {
            await HealthKitManager.shared.requestAuthorization()
        }

        // Register for background refresh
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.treadmillsync.refresh",
            using: nil
        ) { task in
            handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncManager)
                .environmentObject(healthKitManager)
                .task {
                    // Sync on app launch
                    await syncManager.syncIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Sync when app comes to foreground
                    Task {
                        await syncManager.syncIfNeeded()
                    }
                }
        }
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Schedule next background refresh
        scheduleBackgroundRefresh()

        let syncTask = Task {
            await syncManager.performBackgroundSync()
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.treadmillsync.refresh")
        // Request refresh in 4 hours (iOS will schedule based on usage patterns)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }
}

import BackgroundTasks
