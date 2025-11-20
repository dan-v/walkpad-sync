import SwiftUI
import Charts

struct StatsView: View {
    @StateObject private var viewModel = StatsViewModel()

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
                        // Summary Cards
                        summaryCards

                        // Full Month Calendar
                        monthCalendar

                        // Trend Chart
                        if viewModel.dailySummaries.count > 1 {
                            trendChart
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

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatSummaryCard(
                title: "Streak",
                value: "\(viewModel.currentStreak)",
                subtitle: viewModel.currentStreak == 1 ? "day" : "days",
                icon: "flame.fill",
                color: .orange
            )

            StatSummaryCard(
                title: "This Week",
                value: viewModel.weekStepsFormatted,
                subtitle: "steps",
                icon: "calendar.badge.clock",
                color: .blue
            )

            StatSummaryCard(
                title: "This Month",
                value: viewModel.monthStepsFormatted,
                subtitle: "steps",
                icon: "calendar",
                color: .green
            )

            StatSummaryCard(
                title: "Best Day",
                value: viewModel.bestDayStepsFormatted,
                subtitle: "steps",
                icon: "trophy.fill",
                color: .yellow
            )
        }
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
class StatsViewModel: ObservableObject {
    @Published var dailySummaries: [DailySummary] = []
    @Published var isLoading = false
    @Published var selectedYear: Int
    @Published var selectedMonth: Int
    @Published var selectedDaySummary: DailySummary?

    private let apiClient: APIClient

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
}
