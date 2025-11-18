import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var syncManager: SyncManager
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var showingServerSetup = false

    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                Button("Skip") {
                    hasCompletedOnboarding = true
                }
                .padding()
            }

            TabView(selection: $currentPage) {
                // Page 1: Welcome
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.blue)
                    Text("Welcome to\nTreadmill Sync")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("Sync your treadmill workouts to Apple Health automatically")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .tag(0)

                // Page 2: How it works
                VStack(spacing: 32) {
                    Spacer()
                    VStack(spacing: 24) {
                        OnboardingFeature(
                            icon: "server.rack",
                            title: "Raspberry Pi Server",
                            description: "Runs 24/7 collecting treadmill data via Bluetooth"
                        )
                        OnboardingFeature(
                            icon: "iphone",
                            title: "Lightweight App",
                            description: "Pulls workouts and syncs to Apple Health"
                        )
                        OnboardingFeature(
                            icon: "heart.fill",
                            title: "Complete Data",
                            description: "Heart rate, distance, calories, and more"
                        )
                    }
                    .padding(.horizontal)
                    Spacer()
                }
                .tag(1)

                // Page 3: Setup
                VStack(spacing: 32) {
                    Spacer()
                    Image(systemName: "network")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    Text("Connect to Server")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Configure your Raspberry Pi server address to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        showingServerSetup = true
                    } label: {
                        Text("Configure Server")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                    .sheet(isPresented: $showingServerSetup) {
                        SettingsView()
                    }

                    Spacer()
                }
                .tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Continue/Done button
            Button {
                if currentPage < 2 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    hasCompletedOnboarding = true
                }
            } label: {
                Text(currentPage == 2 ? "Get Started" : "Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .interactiveDismissDisabled()
    }
}

struct OnboardingFeature: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.blue)
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(SyncManager())
}
