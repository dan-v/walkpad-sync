import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        TabView {
            ActivityListView()
                .tabItem {
                    Label("Activity", systemImage: "figure.walk")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
        }
    }
}
