import SwiftUI
import BackgroundTasks

@main
struct TreadmillSyncApp: App {
    @StateObject private var syncManager = SyncManager()
    @State private var hasRegisteredBackgroundTask = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncManager)
                .task {
                    // Register background task once
                    if !hasRegisteredBackgroundTask {
                        registerBackgroundTask()
                        hasRegisteredBackgroundTask = true
                    }

                    // Request HealthKit permissions on launch
                    try? await HealthKitManager.shared.requestAuthorization()

                    // Sync on app launch
                    await syncManager.syncIfNeeded()

                    // Schedule first background refresh
                    scheduleBackgroundRefresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Sync when app comes to foreground
                    Task {
                        await syncManager.syncIfNeeded()
                    }
                }
        }
    }

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.treadmillsync.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundRefresh(task: refreshTask)
        }
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Schedule next background refresh
        scheduleBackgroundRefresh()

        let syncTask = Task { [weak self] in
            await self?.syncManager.performBackgroundSync()
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
