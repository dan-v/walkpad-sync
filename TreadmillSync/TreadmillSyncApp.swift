import SwiftUI

@main
struct TreadmillSyncApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Request HealthKit permissions on launch
                    try? await HealthKitManager.shared.requestAuthorization()
                }
        }
    }
}
