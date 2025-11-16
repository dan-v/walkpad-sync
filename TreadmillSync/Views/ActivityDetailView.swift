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

                    if summary.isSynced {
                        Label("Synced to Apple Health", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
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

                // Sync button
                if !summary.isSynced {
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
                            Label("Sync to Apple Health", systemImage: "heart.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSyncing)
                    .padding(.horizontal)
                }

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
            // Fetch samples for this date
            let samples = try await apiClient.fetchSamples(date: summary.date)

            // Sync to HealthKit
            try await healthKitManager.saveWorkout(
                date: summary.date,
                samples: samples,
                distanceMeters: summary.distanceMeters,
                calories: summary.calories,
                steps: summary.steps
            )

            // Mark as synced on server
            try await apiClient.markDateSynced(date: summary.date)

            showSuccessAlert = true
        } catch {
            self.error = error.localizedDescription
        }

        isSyncing = false
    }
}
