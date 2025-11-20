import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @State private var autoRefreshTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
                        .padding(.vertical, 12)

                        // Secondary stats - larger and more prominent
                        HStack(spacing: 20) {
                            StatBadge(
                                value: todaySummary.distanceFormatted,
                                icon: "figure.walk",
                                color: .green
                            )
                            StatBadge(
                                value: todaySummary.caloriesFormatted,
                                icon: "flame.fill",
                                color: .orange
                            )
                            StatBadge(
                                value: todaySummary.durationFormatted,
                                icon: "clock.fill",
                                color: .purple
                            )
                        }
                        .padding(.horizontal)

                        Divider()
                            .padding(.vertical, 4)

                        // Quick stats - compact horizontal layout
                        HStack(spacing: 12) {
                            CompactStatCard(
                                value: "\(viewModel.currentStreak)",
                                label: viewModel.currentStreak == 1 ? "day streak" : "day streak",
                                icon: "flame.fill",
                                color: .orange
                            )

                            CompactStatCard(
                                value: viewModel.weekStepsFormatted,
                                label: "this week",
                                icon: "calendar",
                                color: .blue
                            )
                        }
                        .padding(.horizontal)

                        // Recent trend
                        if viewModel.last7Days.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Last 7 Days")
                                    .font(.headline)
                                    .padding(.horizontal)

                                recentTrendBars
                            }
                            .padding(.top, 8)
                        }

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

            // Smart auto-refresh: fast during workout, slow otherwise
            autoRefreshTask = Task {
                while !Task.isCancelled {
                    // Use fast refresh (3s) if workout is ongoing, otherwise slow (30s)
                    let refreshInterval = viewModel.isWorkoutOngoing ? 3.0 : 30.0
                    try? await Task.sleep(for: .seconds(refreshInterval))

                    if !Task.isCancelled {
                        // Don't show loading indicator during background refresh
                        await viewModel.loadData(showLoading: false)
                    }
                }
            }
        }
        .onAppear {
            // Keep screen awake while on Today page
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            // Re-enable auto-lock when leaving Today page
            UIApplication.shared.isIdleTimerDisabled = false

            // Cancel auto-refresh when view disappears
            autoRefreshTask?.cancel()
        }
    }

    private var recentTrendBars: some View {
        let maxSteps = viewModel.last7Days.map { $0.steps }.max() ?? 1

        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(viewModel.last7Days) { summary in
                    VStack(spacing: 4) {
                        // Bar
                        let height = maxSteps > 0 ? CGFloat(summary.steps) / CGFloat(maxSteps) * 80 : 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(summary.isToday ? Color.blue : Color.blue.opacity(0.5))
                            .frame(height: max(height, 4))

                        // Day label
                        Text(summary.dayOfWeek)
                            .font(.caption2)
                            .foregroundColor(summary.isToday ? .blue : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
            .padding(.horizontal)

            // Legend
            HStack {
                Text("Daily average: \(viewModel.dailyAverageFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
        }
    }
}

// Larger, more prominent stat badges
struct StatBadge: View {
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }
}

// Compact horizontal stat card
struct CompactStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

@MainActor
class TodayViewModel: ObservableObject {
    @Published var todaySummary: DailySummary?
    @Published var allSummaries: [DailySummary] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var error: String?
    @Published var lastFetchTime: Date?

    private let apiClient: APIClient
    private let healthKitManager = HealthKitManager.shared

    init() {
        let config = ServerConfig.load()
        self.apiClient = APIClient(config: config)
    }

    // Check if a workout is likely ongoing based on recent activity
    var isWorkoutOngoing: Bool {
        guard let summary = todaySummary else { return false }

        // If we have a summary and it was fetched recently (within last 10 seconds),
        // and it has recent samples, consider workout as ongoing
        guard let lastFetch = lastFetchTime else { return false }

        // If last fetch was more than 30 seconds ago, we don't know
        let timeSinceLastFetch = Date().timeIntervalSince(lastFetch)
        if timeSinceLastFetch > 30 {
            return false
        }

        // If we have steps/activity today, assume workout might be ongoing
        return summary.steps > 0
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

    var last7Days: [DailySummary] {
        Array(allSummaries.suffix(7))
    }

    var dailyAverageFormatted: String {
        guard !last7Days.isEmpty else { return "0" }
        let totalSteps = last7Days.reduce(0) { $0 + $1.steps }
        let average = totalSteps / Int64(last7Days.count)

        if average >= 1000 {
            let k = Double(average) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(average)"
    }

    func loadData(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }
        error = nil

        do {
            // Get today's date in UTC (server uses UTC for date grouping)
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
            let previousSteps = todaySummary?.steps ?? 0
            todaySummary = loadedSummaries.first(where: { $0.date == todayStr })

            // Track fetch time for workout detection
            lastFetchTime = Date()

        } catch {
            self.error = error.localizedDescription
        }

        if showLoading {
            isLoading = false
        }
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
