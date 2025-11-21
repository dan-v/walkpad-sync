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
                        // Workout status indicator
                        if viewModel.isWorkoutOngoing {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Active workout detected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "bolt.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("Refreshing every 3s")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }

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
    @Published var previousSteps: Int64 = 0
    @Published var lastStepsChangeTime: Date?

    private let apiClient: APIClient
    private let healthKitManager = HealthKitManager.shared

    init() {
        let config = ServerConfig.load()
        self.apiClient = APIClient(config: config)
    }

    // Check if a workout is likely ongoing based on recent activity
    var isWorkoutOngoing: Bool {
        guard let summary = todaySummary else { return false }
        guard let lastChange = lastStepsChangeTime else { return false }

        // If steps increased within the last 60 seconds, workout is ongoing
        let timeSinceLastChange = Date().timeIntervalSince(lastChange)
        return timeSinceLastChange < 60
    }

    var currentStreak: Int {
        guard !allSummaries.isEmpty else { return 0 }

        let sorted = allSummaries.sorted { $0.date > $1.date }
        let calendar = Calendar.current

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
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return "0"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
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

    func loadData(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }
        error = nil

        do {
            // Get today's date in local timezone
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
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

            // Find today's summary and detect if steps increased (workout ongoing)
            let newSummary = loadedSummaries.first(where: { $0.date == todayStr })
            let newSteps = newSummary?.steps ?? 0

            // If steps increased since last fetch, update last change time
            if newSteps > previousSteps {
                lastStepsChangeTime = Date()
            }

            previousSteps = newSteps
            todaySummary = newSummary

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

                // Mark as synced locally
                SyncStateManager.shared.markAsSynced(summary: summary)
            }

            // Reload to update sync status
            await loadData()

        } catch {
            self.error = error.localizedDescription
        }

        isSyncing = false
    }
}
