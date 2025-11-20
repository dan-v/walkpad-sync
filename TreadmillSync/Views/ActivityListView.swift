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
                    VStack(spacing: 0) {
                        // Quick summary header
                        if !viewModel.summaries.isEmpty {
                            quickSummaryHeader
                                .padding()
                                .background(Color(.systemGroupedBackground))
                        }

                        List(viewModel.recentSummaries) { summary in
                            NavigationLink {
                                ActivityDetailView(summary: summary)
                            } label: {
                                ActivityRow(summary: summary)
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await viewModel.loadActivities()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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

    private var quickSummaryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity")
                        .font(.headline)
                    Text("Last 30 days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                SummaryBadge(
                    value: "\(viewModel.totalDays)",
                    label: "days",
                    icon: "calendar",
                    color: .blue
                )
                SummaryBadge(
                    value: viewModel.totalStepsFormatted,
                    label: "steps",
                    icon: "figure.walk",
                    color: .green
                )
                SummaryBadge(
                    value: viewModel.totalDistanceFormatted,
                    label: "miles",
                    icon: "ruler",
                    color: .orange
                )
            }
        }
    }
}

struct SummaryBadge: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
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

    var recentSummaries: [DailySummary] {
        Array(summaries.prefix(30))
    }

    var totalDays: Int {
        recentSummaries.count
    }

    var totalStepsFormatted: String {
        let total = recentSummaries.reduce(0) { $0 + $1.steps }
        if total >= 1000 {
            let k = Double(total) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(total)"
    }

    var totalDistanceFormatted: String {
        let totalMeters = recentSummaries.reduce(0) { $0 + $1.distanceMeters }
        let miles = Double(totalMeters) / 1609.34
        return String(format: "%.1f", miles)
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
