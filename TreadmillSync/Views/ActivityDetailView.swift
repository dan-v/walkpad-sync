import SwiftUI

struct ActivityDetailView: View {
    let summary: DailySummary
    @StateObject private var viewModel: ActivityDetailViewModel

    init(summary: DailySummary) {
        self.summary = summary
        self._viewModel = StateObject(wrappedValue: ActivityDetailViewModel(summary: summary))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Date header
                VStack(spacing: 4) {
                    Text(summary.dateFormatted)
                        .font(.title2)
                        .bold()

                    if summary.isSynced, let syncTime = summary.syncedAtFormatted {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(syncTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("You can re-sync if you've walked more since then")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()

                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(title: "Steps", value: summary.stepsFormatted, icon: "figure.walk", color: .blue)
                    StatCard(title: "Distance", value: summary.distanceFormatted, icon: "ruler", color: .green)
                    StatCard(title: "Calories", value: summary.caloriesFormatted, icon: "flame.fill", color: .orange)
                    StatCard(title: "Duration", value: summary.durationFormatted, icon: "clock.fill", color: .purple)
                }
                .padding(.horizontal)

                // Sync button - always show, but change text based on status
                Button {
                    Task {
                        await viewModel.syncToAppleHealth()
                    }
                } label: {
                    if viewModel.isSyncing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                    } else {
                        if summary.isSynced {
                            Label("Re-sync to Apple Health", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Sync to Apple Health", systemImage: "heart.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(summary.isSynced ? .green : .blue)
                .disabled(viewModel.isSyncing)
                .padding(.horizontal)

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success", isPresented: $viewModel.showSuccessAlert) {
            Button("OK") { }
        } message: {
            Text("Activity synced to Apple Health")
        }
    }
}

@MainActor
class ActivityDetailViewModel: ObservableObject {
    @Published var isSyncing = false
    @Published var error: String?
    @Published var showSuccessAlert = false

    private let summary: DailySummary
    private let apiClient: APIClient
    private let healthKitManager = HealthKitManager.shared

    init(summary: DailySummary) {
        self.summary = summary
        let config = ServerConfig.load()
        self.apiClient = APIClient(config: config)
    }

    func syncToAppleHealth() async {
        isSyncing = true
        error = nil

        do {
            print("🔄 Syncing \(summary.date) - Steps: \(summary.steps), Distance: \(summary.distanceMeters)m")

            // Fetch samples for this date
            let samples = try await apiClient.fetchSamples(date: summary.date)
            print("✅ Fetched \(samples.count) samples")

            // Sync to HealthKit (this will delete existing workouts first)
            try await healthKitManager.saveWorkout(
                date: summary.date,
                samples: samples,
                distanceMeters: summary.distanceMeters,
                calories: summary.calories,
                steps: summary.steps
            )
            print("✅ Saved to HealthKit")

            // Mark as synced on server
            try await apiClient.markDateSynced(date: summary.date)
            print("✅ Marked as synced on server")

            showSuccessAlert = true
        } catch {
            print("❌ Sync error: \(error)")
            // Show detailed error message
            if let apiError = error as? APIError {
                self.error = "API Error: \(apiError.localizedDescription)"
            } else {
                self.error = "Error: \(error.localizedDescription)"
            }
        }

        isSyncing = false
    }
}
