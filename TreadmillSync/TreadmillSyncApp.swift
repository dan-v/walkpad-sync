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

                    // Note: Manual sync only - user must tap "Sync All to Apple Health" button
                    // Background sync still happens every 4 hours when app is backgrounded
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
        // Background sync is disabled - user prefers manual sync only
        // If you want to enable it, uncomment the code below:

        // scheduleBackgroundRefresh()
        // let syncTask = Task {
        //     await syncManager.performBackgroundSync()
        // }
        // task.expirationHandler = {
        //     syncTask.cancel()
        // }
        // Task {
        //     await syncTask.value
        //     task.setTaskCompleted(success: true)
        // }

        task.setTaskCompleted(success: true)
    }

    private func scheduleBackgroundRefresh() {
        // Background sync disabled - manual sync only
        // let request = BGAppRefreshTaskRequest(identifier: "com.treadmillsync.refresh")
        // request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        // do {
        //     try BGTaskScheduler.shared.submit(request)
        // } catch {
        //     print("Failed to schedule background refresh: \(error)")
        // }
    }
}
