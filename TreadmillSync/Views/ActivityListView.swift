import SwiftUI

struct ActivityListView: View {
    @StateObject private var viewModel = ActivityViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading activity...")
                } else if let error = viewModel.error {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await viewModel.loadActivities() }
                        }
                    }
                } else if viewModel.summaries.isEmpty {
                    ContentUnavailableView {
                        Label("No Activity", systemImage: "figure.walk")
                    } description: {
                        Text("Start walking on your treadmill to see your activity here.")
                    }
                } else {
                    List(viewModel.summaries) { summary in
                        NavigationLink {
                            ActivityDetailView(summary: summary)
                        } label: {
                            ActivityRow(summary: summary)
                        }
                    }
                    .refreshable {
                        await viewModel.loadActivities()
                    }
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.loadActivities() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .task {
            await viewModel.loadActivities()
        }
    }
}

struct ActivityRow: View {
    let summary: DailySummary

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.dateFormatted)
                        .font(.headline)

                    HStack(spacing: 12) {
                        Label(summary.stepsFormatted, systemImage: "figure.walk")
                            .font(.subheadline)
                        Label(summary.distanceFormatted, systemImage: "ruler")
                            .font(.subheadline)
                        Label(summary.caloriesFormatted, systemImage: "flame.fill")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if summary.isSynced {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .imageScale(.large)
                        if let syncTime = summary.syncedAtShort {
                            Text(syncTime)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        } else {
                            Text("Synced")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(.blue)
                            .imageScale(.large)
                        Text("Tap to sync")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class ActivityViewModel: ObservableObject {
    @Published var summaries: [DailySummary] = []
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient: APIClient

    init() {
        let config = ServerConfig.load()
        self.apiClient = APIClient(config: config)
    }

    func loadActivities() async {
        isLoading = true
        error = nil

        do {
            // Fetch all activity dates
            let dates = try await apiClient.fetchActivityDates()

            // Fetch summaries for each date
            var loadedSummaries: [DailySummary] = []
            for date in dates {
                if let summary = try? await apiClient.fetchDailySummary(date: date) {
                    loadedSummaries.append(summary)
                }
            }

            summaries = loadedSummaries.sorted { $0.date > $1.date }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
