import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if viewModel.isLoading {
                        ProgressView("Loading...")
                            .padding()
                    } else if let todaySummary = viewModel.todaySummary {
                        // Date header
                        Text("TODAY")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(todaySummary.dateFormatted)
                            .font(.title3)
                            .fontWeight(.semibold)

                        // Big steps display
                        VStack(spacing: 8) {
                            Text("\(todaySummary.steps)")
                                .font(.system(size: 72, weight: .bold))
                                .foregroundColor(.blue)

                            Text("steps")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)

                        // Secondary stats
                        HStack(spacing: 4) {
                            SecondaryStatView(
                                value: todaySummary.distanceFormatted,
                                icon: "ruler"
                            )
                            Text("•")
                                .foregroundColor(.secondary)
                            SecondaryStatView(
                                value: todaySummary.caloriesFormatted,
                                icon: "flame.fill"
                            )
                            Text("•")
                                .foregroundColor(.secondary)
                            SecondaryStatView(
                                value: todaySummary.durationFormatted,
                                icon: "clock"
                            )
                        }
                        .font(.subheadline)

                        Divider()
                            .padding(.vertical, 8)

                        // Quick stats cards
                        HStack(spacing: 12) {
                            QuickStatCard(
                                value: "\(viewModel.currentStreak)",
                                label: viewModel.currentStreak == 1 ? "day" : "days",
                                title: "Streak",
                                icon: "flame.fill",
                                color: .orange
                            )

                            QuickStatCard(
                                value: viewModel.weekStepsFormatted,
                                label: "steps",
                                title: "This Week",
                                icon: "calendar.badge.clock",
                                color: .blue
                            )
                        }
                        .padding(.horizontal)

                        Divider()
                            .padding(.vertical, 8)

                        // Sync section
                        syncSection
                            .padding(.horizontal)

                    } else {
                        // No activity today
                        ContentUnavailableView {
                            Label("No Activity Today", systemImage: "figure.walk")
                        } description: {
                            Text("Start walking on your treadmill to see stats here")
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.loadData()
            }
        }
        .task {
            await viewModel.loadData()
        }
    }

    private var syncSection: some View {
        VStack(spacing: 12) {
            if viewModel.unsyncedCount > 0 {
                // Unsynced days exist
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                        Text("\(viewModel.unsyncedCount) \(viewModel.unsyncedCount == 1 ? "day" : "days") not synced to Health")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Button {
                        Task {
                            await viewModel.syncAll()
                        }
                    } label: {
                        if viewModel.isSyncing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Sync All to Apple Health", systemImage: "heart.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSyncing)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)

            } else if !viewModel.isLoading && viewModel.todaySummary != nil {
                // All caught up
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All caught up! Everything synced")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

struct SecondaryStatView: View {
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(value)
        }
        .foregroundColor(.secondary)
    }
}

struct QuickStatCard: View {
    let value: String
    let label: String
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

@MainActor
class TodayViewModel: ObservableObject {
    @Published var todaySummary: DailySummary?
    @Published var allSummaries: [DailySummary] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var error: String?

    private let apiClient: APIClient
    private let healthKitManager = HealthKitManager.shared

    init() {
        let config = ServerConfig.load()
        self.apiClient = APIClient(config: config)
    }

    var currentStreak: Int {
        guard !allSummaries.isEmpty else { return 0 }

        let sorted = allSummaries.sorted { $0.date > $1.date }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var streak = 0
        var expectedDate = calendar.startOfDay(for: Date())

        for summary in sorted {
            guard let summaryDate = summary.dateDisplay else { continue }
            let summaryDay = calendar.startOfDay(for: summaryDate)

            if calendar.isDate(summaryDay, inSameDayAs: expectedDate) {
                streak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate)!
            } else {
                break
            }
        }

        return streak
    }

    var weekStepsFormatted: String {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return "0"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let weekStartStr = formatter.string(from: weekStart)

        let weekSteps = allSummaries
            .filter { $0.date >= weekStartStr }
            .reduce(0) { $0 + $1.steps }

        if weekSteps >= 1000 {
            let k = Double(weekSteps) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(weekSteps)"
    }

    var unsyncedCount: Int {
        allSummaries.filter { !$0.isSynced }.count
    }

    var unsyncedSummaries: [DailySummary] {
        allSummaries.filter { !$0.isSynced }.sorted { $0.date < $1.date }
    }

    func loadData() async {
        isLoading = true
        error = nil

        do {
            // Get today's date
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            let todayStr = formatter.string(from: Date())

            // Fetch all dates to get full summaries for streak/week calculation
            let dates = try await apiClient.fetchActivityDates()

            var loadedSummaries: [DailySummary] = []
            for date in dates {
                if let summary = try? await apiClient.fetchDailySummary(date: date) {
                    loadedSummaries.append(summary)
                }
            }

            allSummaries = loadedSummaries

            // Find today's summary
            todaySummary = loadedSummaries.first(where: { $0.date == todayStr })

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func syncAll() async {
        isSyncing = true
        error = nil

        do {
            // Sync all unsynced days
            for summary in unsyncedSummaries {
                // Fetch samples
                let samples = try await apiClient.fetchSamples(date: summary.date)

                // Sync to HealthKit
                try await healthKitManager.saveWorkout(
                    date: summary.date,
                    samples: samples,
                    distanceMeters: summary.distanceMeters,
                    calories: summary.calories,
                    steps: summary.steps
                )

                // Mark as synced
                try await apiClient.markDateSynced(date: summary.date)
            }

            // Reload to update sync status
            await loadData()

        } catch {
            self.error = error.localizedDescription
        }

        isSyncing = false
    }
}
