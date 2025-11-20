import SwiftUI
import Charts

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if viewModel.isLoading {
                        ProgressView("Loading stats...")
                            .padding()
                    } else if viewModel.dailySummaries.isEmpty {
                        emptyState
                    } else {
                        // Full Month Calendar
                        monthCalendar

                        // Monthly Summary
                        monthlySummary

                        // Trend Chart
                        if viewModel.dailySummaries.count > 1 {
                            trendChart
                        }

                        // Batch Sync Section
                        if viewModel.unsyncedCount > 0 {
                            batchSyncSection
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
        .sheet(item: $viewModel.selectedDaySummary) { summary in
            NavigationStack {
                ActivityDetailView(summary: summary)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                viewModel.selectedDaySummary = nil
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Monthly Summary

    private var monthlySummary: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly Total")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(viewModel.monthStepsFormatted)
                    .font(.title3)
                    .fontWeight(.bold)
                Text("steps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Distance")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(viewModel.monthDistanceFormatted)
                    .font(.title3)
                    .fontWeight(.bold)
                Text("miles")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Batch Sync Section

    private var batchSyncSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.blue)
                Text("Sync \(viewModel.unsyncedCount) \(viewModel.unsyncedCount == 1 ? "day" : "days") to Health")
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

            if let error = viewModel.syncError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Month Calendar

    private var monthCalendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    viewModel.previousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }

                Spacer()

                Text(viewModel.currentMonthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.nextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                }
                .disabled(viewModel.isCurrentMonth)
            }
            .padding(.horizontal)

            MonthCalendarView(
                year: viewModel.selectedYear,
                month: viewModel.selectedMonth,
                summaries: viewModel.dailySummaries,
                onDayTap: { summary in
                    viewModel.selectedDaySummary = summary
                }
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Steps")
                .font(.headline)
                .padding(.horizontal)

            Chart {
                ForEach(viewModel.last30Days) { summary in
                    LineMark(
                        x: .value("Date", summary.dateDisplay ?? Date()),
                        y: .value("Steps", summary.steps)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", summary.dateDisplay ?? Date()),
                        y: .value("Steps", summary.steps)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month().day())
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Activity Yet")
                .font(.title2)
                .bold()
            Text("Start using your treadmill to see stats here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Summary Card Component

struct StatSummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Month Calendar View

struct MonthCalendarView: View {
    let year: Int
    let month: Int
    let summaries: [DailySummary]
    let onDayTap: (DailySummary) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var weeks: [[Date?]] {
        let dateComponents = DateComponents(year: year, month: month, day: 1)
        guard let firstDay = calendar.date(from: dateComponents) else { return [] }

        // Get range of days in month
        guard let range = calendar.range(of: .day, in: .month, for: firstDay) else { return [] }

        // Get first weekday (1 = Sunday, 7 = Saturday)
        let firstWeekday = calendar.component(.weekday, from: firstDay)

        var weeks: [[Date?]] = []
        var currentWeek: [Date?] = []

        // Fill in empty days before first of month
        for _ in 1..<firstWeekday {
            currentWeek.append(nil)
        }

        // Fill in days of month
        for day in range {
            let dateComponents = DateComponents(year: year, month: month, day: day)
            if let date = calendar.date(from: dateComponents) {
                currentWeek.append(date)

                if currentWeek.count == 7 {
                    weeks.append(currentWeek)
                    currentWeek = []
                }
            }
        }

        // Fill in remaining days to complete last week
        while !currentWeek.isEmpty && currentWeek.count < 7 {
            currentWeek.append(nil)
        }
        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }

        return weeks
    }

    private func stepsForDate(_ date: Date) -> Int64? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = formatter.string(from: date)

        return summaries.first(where: { $0.date == dateString })?.steps
    }

    private func summaryForDate(_ date: Date) -> DailySummary? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = formatter.string(from: date)

        return summaries.first(where: { $0.date == dateString })
    }

    private func colorForSteps(_ steps: Int64?) -> Color {
        guard let steps = steps else {
            return Color(.systemGray6)
        }

        if steps == 0 {
            return Color(.systemGray6)
        }

        let maxSteps = summaries.map { $0.steps }.max() ?? 1
        let intensity = Double(steps) / Double(maxSteps)

        if intensity > 0.75 {
            return .blue.opacity(1.0)
        } else if intensity > 0.5 {
            return .blue.opacity(0.7)
        } else if intensity > 0.25 {
            return .blue.opacity(0.5)
        } else {
            return .blue.opacity(0.2)
        }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Weekday headers
            HStack(spacing: 4) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        if let date = weeks[weekIndex][dayIndex] {
                            let steps = stepsForDate(date)
                            let day = calendar.component(.day, from: date)
                            let daySummary = summaryForDate(date)

                            Button {
                                if let summary = daySummary {
                                    onDayTap(summary)
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorForSteps(steps))
                                        .frame(height: 44)

                                    VStack(spacing: 2) {
                                        Text("\(day)")
                                            .font(.caption)
                                            .fontWeight(isToday(date) ? .bold : .regular)
                                            .foregroundColor(steps ?? 0 > 0 ? .white : .primary)

                                        if let steps = steps, steps > 0 {
                                            Text("\(steps / 1000)k")
                                                .font(.system(size: 8))
                                                .foregroundColor(.white.opacity(0.9))
                                        }
                                    }

                                    // Unsynced indicator
                                    if let summary = daySummary, !summary.isSynced {
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Circle()
                                                    .fill(Color.blue)
                                                    .frame(width: 6, height: 6)
                                                    .padding(4)
                                            }
                                            Spacer()
                                        }
                                    }

                                    if isToday(date) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.orange, lineWidth: 2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(daySummary == nil)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                                .frame(height: 44)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - View Model

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var dailySummaries: [DailySummary] = []
    @Published var isLoading = false
    @Published var selectedYear: Int
    @Published var selectedMonth: Int
    @Published var selectedDaySummary: DailySummary?
    @Published var isSyncing = false
    @Published var syncError: String?

    private let apiClient: APIClient
    private let healthKitManager = HealthKitManager.shared

    init() {
        let config = ServerConfig.load()
        self.apiClient = APIClient(config: config)

        // Initialize to current month in UTC
        let calendar = Calendar.current
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        self.selectedYear = utcCalendar.component(.year, from: now)
        self.selectedMonth = utcCalendar.component(.month, from: now)
    }

    var currentMonthTitle: String {
        let dateComponents = DateComponents(year: selectedYear, month: selectedMonth)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!

        guard let date = calendar.date(from: dateComponents) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    var isCurrentMonth: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        return selectedYear == currentYear && selectedMonth == currentMonth
    }

    // Streak calculation
    var currentStreak: Int {
        guard !dailySummaries.isEmpty else { return 0 }

        let sorted = dailySummaries.sorted { $0.date > $1.date }
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

    // This week stats
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

        let weekSteps = dailySummaries
            .filter { $0.date >= weekStartStr }
            .reduce(0) { $0 + $1.steps }

        return formatSteps(weekSteps)
    }

    // This month stats
    var monthStepsFormatted: String {
        let monthSteps = dailySummaries
            .filter {
                guard let date = $0.dateDisplay else { return false }
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: "UTC")!
                let summaryYear = calendar.component(.year, from: date)
                let summaryMonth = calendar.component(.month, from: date)
                return summaryYear == selectedYear && summaryMonth == selectedMonth
            }
            .reduce(0) { $0 + $1.steps }

        return formatSteps(monthSteps)
    }

    var monthDistanceFormatted: String {
        let monthDistance = dailySummaries
            .filter {
                guard let date = $0.dateDisplay else { return false }
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: "UTC")!
                let summaryYear = calendar.component(.year, from: date)
                let summaryMonth = calendar.component(.month, from: date)
                return summaryYear == selectedYear && summaryMonth == selectedMonth
            }
            .reduce(0) { $0 + $1.distanceMeters }

        let miles = Double(monthDistance) / 1609.34
        return String(format: "%.1f", miles)
    }

    var unsyncedCount: Int {
        dailySummaries.filter { !$0.isSynced }.count
    }

    // Best day stats
    var bestDayStepsFormatted: String {
        let maxSteps = dailySummaries.map { $0.steps }.max() ?? 0
        return formatSteps(maxSteps)
    }

    // Last 30 days for chart
    var last30Days: [DailySummary] {
        Array(dailySummaries.suffix(30))
    }

    private func formatSteps(_ steps: Int64) -> String {
        if steps >= 1000 {
            let k = Double(steps) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(steps)"
    }

    func previousMonth() {
        if selectedMonth == 1 {
            selectedMonth = 12
            selectedYear -= 1
        } else {
            selectedMonth -= 1
        }
    }

    func nextMonth() {
        guard !isCurrentMonth else { return }

        if selectedMonth == 12 {
            selectedMonth = 1
            selectedYear += 1
        } else {
            selectedMonth += 1
        }
    }

    func loadData() async {
        isLoading = true

        do {
            let dates = try await apiClient.fetchActivityDates()

            var loadedSummaries: [DailySummary] = []
            for date in dates {
                if let summary = try? await apiClient.fetchDailySummary(date: date) {
                    loadedSummaries.append(summary)
                }
            }

            dailySummaries = loadedSummaries.sorted { $0.date < $1.date }
        } catch {
            print("Error loading stats: \(error)")
        }

        isLoading = false
    }

    func syncAll() async {
        isSyncing = true
        syncError = nil

        let unsyncedSummaries = dailySummaries.filter { !$0.isSynced }

        for summary in unsyncedSummaries {
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

                // Mark as synced
                try await apiClient.markDateSynced(date: summary.date)

                // Reload to get updated sync status
                await loadData()
            } catch {
                syncError = "Failed to sync \(summary.dateFormatted): \(error.localizedDescription)"
                break
            }
        }

        isSyncing = false
    }
}
