import SwiftUI

@main
struct WalkPadSyncApp: App {
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
