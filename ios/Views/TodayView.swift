import SwiftUI
import Combine

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @State private var autoRefreshTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Error banner
                    if let error = viewModel.error {
                        HStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connection Error")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            Spacer()
                            Button {
                                Task { await viewModel.loadData() }
                            } label: {
                                Text("Retry")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    if viewModel.isLoading {
                        ProgressView("Loading...")
                            .padding()
                    } else if let todaySummary = viewModel.todaySummary {
                        // Connection status indicator
                        if viewModel.isWebSocketConnected {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Live")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        } else if viewModel.isWorkoutOngoing {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                Text("Active workout")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "bolt.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text("Polling every 3s")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
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
        .onAppear {
            // Refresh data when tab becomes visible
            Task {
                await viewModel.loadData(showLoading: false)
            }
        }
        .task {
            // Connect to WebSocket for live updates
            await viewModel.connectWebSocket()

            // Load initial data
            await viewModel.loadData()

            // Fallback polling when WebSocket is disconnected
            // This also serves as periodic full refresh
            autoRefreshTask = Task {
                while !Task.isCancelled {
                    // If WebSocket connected, do slower background refresh
                    // Otherwise, use fast refresh during workout
                    let refreshInterval: Double
                    if viewModel.isWebSocketConnected {
                        refreshInterval = 60.0  // Slow refresh when WebSocket is active
                    } else {
                        refreshInterval = viewModel.isWorkoutOngoing ? 3.0 : 30.0
                    }

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

            // Disconnect WebSocket
            Task {
                await viewModel.disconnectWebSocket()
            }
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
    @Published var error: String?
    @Published var lastFetchTime: Date?
    @Published var previousSteps: Int64 = 0
    @Published var lastStepsChangeTime: Date?
    @Published var isWebSocketConnected = false

    private let apiClient: APIClient
    private let webSocketManager: WebSocketManager

    init() {
        let config = ServerConfig.load()
        self.apiClient = APIClient(config: config)
        self.webSocketManager = WebSocketManager(config: config)

        // Subscribe to WebSocket connection status
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Subscribe to connection status changes
            for await status in await self.webSocketManager.connectionStatusPublisher.values {
                await MainActor.run {
                    self.isWebSocketConnected = (status == .connected)
                }
            }
        }

        // Subscribe to WebSocket sample updates
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            for await _ in await self.webSocketManager.samplePublisher.values {
                // Refresh data when new sample arrives
                await self.loadData(showLoading: false)
            }
        }
    }

    // Check if a workout is likely ongoing based on recent activity
    var isWorkoutOngoing: Bool {
        guard todaySummary != nil else { return false }
        guard let lastChange = lastStepsChangeTime else { return false }

        // If steps increased within the last 60 seconds, workout is ongoing
        let timeSinceLastChange = Date().timeIntervalSince(lastChange)
        return timeSinceLastChange < 60
    }

    var currentStreak: Int {
        guard !allSummaries.isEmpty else { return 0 }

        let calendar = Calendar.current

        // Build set of all dates with data for O(1) lookup
        let datesWithData: Set<Date> = Set(allSummaries.compactMap { summary in
            guard let date = summary.dateDisplay else { return nil }
            return calendar.startOfDay(for: date)
        })

        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // Go back up to 365 days
        for _ in 0..<365 {
            // Skip weekends entirely
            if calendar.isDateInWeekend(checkDate) {
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
                continue
            }

            // Check if this weekday has data
            if datesWithData.contains(checkDate) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
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

            // Fetch all summaries in a single API call (instead of N+1 queries)
            let loadedSummaries = try await apiClient.fetchAllSummaries()
            allSummaries = loadedSummaries

            // Find today's summary and detect if steps increased (workout ongoing)
            let newSummary = loadedSummaries.first(where: { $0.date == todayStr })
            let newSteps = newSummary?.steps ?? 0

            // If steps increased since last fetch, update last change time
            // But skip the first load (when previousSteps is still 0) to avoid false positive
            if newSteps > previousSteps && previousSteps > 0 {
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

    // MARK: - WebSocket Management

    func connectWebSocket() async {
        await webSocketManager.connect()
    }

    func disconnectWebSocket() async {
        await webSocketManager.disconnect()
    }
}
