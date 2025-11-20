import SwiftUI

@main
struct TreadmillSyncApp: App {
    init() {
        // Register background sync task
        BackgroundSyncManager.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Request HealthKit permissions on launch
                    try? await HealthKitManager.shared.requestAuthorization()

                    // Schedule background sync
                    BackgroundSyncManager.shared.scheduleBackgroundSync()
                }
        }
    }
}
