import SwiftUI
import Charts

struct StatsView: View {
    private let apiClient = APIClient(config: ServerConfig.load())
    @State private var activityDates: [String] = []
    @State private var dailySummaries: [DailySummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPeriod: TimePeriod = .month

    enum TimePeriod: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case all = "All Time"

        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .all: return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Loading stats...")
                            .padding()
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if dailySummaries.isEmpty {
                        emptyStateView
                    } else {
                        // Period Selector
                        periodSelector

                        // Overview Cards
                        overviewCards

                        // Calendar Heatmap
                        calendarHeatmap

                        // Charts
                        chartsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await loadData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadData()
            }
        }
    }

    private var periodSelector: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(TimePeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var filteredSummaries: [DailySummary] {
        guard let days = selectedPeriod.days else {
            return dailySummaries
        }
        return Array(dailySummaries.suffix(days))
    }

    private var overviewCards: some View {
        VStack(spacing: 16) {
            Text(selectedPeriod.rawValue)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: "Total Steps",
                    value: formatNumber(totalSteps),
                    icon: "figure.walk",
                    color: .blue
                )

                StatCard(
                    title: "Total Distance",
                    value: formatDistance(totalDistance),
                    icon: "arrow.left.and.right",
                    color: .green
                )

                StatCard(
                    title: "Total Calories",
                    value: formatNumber(totalCalories),
                    icon: "flame.fill",
                    color: .orange
                )

                StatCard(
                    title: "Active Days",
                    value: "\(filteredSummaries.count)",
                    icon: "calendar",
                    color: .purple
                )
            }
        }
    }

    private var calendarHeatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Heatmap")
                .font(.headline)

            CalendarHeatmapView(summaries: dailySummaries)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var chartsSection: some View {
        VStack(spacing: 20) {
            if filteredSummaries.count > 1 {
                stepsChart
                distanceChart
                caloriesChart
                speedComparisonChart
            }
        }
    }

    private var stepsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps Trend")
                .font(.headline)

            Chart(filteredSummaries) { summary in
                BarMark(
                    x: .value("Date", formatDateShort(summary.date)),
                    y: .value("Steps", summary.steps)
                )
                .foregroundStyle(.blue.gradient)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var distanceChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distance Trend")
                .font(.headline)

            Chart(filteredSummaries) { summary in
                LineMark(
                    x: .value("Date", formatDateShort(summary.date)),
                    y: .value("Distance", Double(summary.distanceMeters) / 1609.34)
                )
                .foregroundStyle(.green.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", formatDateShort(summary.date)),
                    y: .value("Distance", Double(summary.distanceMeters) / 1609.34)
                )
                .foregroundStyle(.green.gradient.opacity(0.2))
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let miles = value.as(Double.self) {
                            Text("\(miles, specifier: "%.1f") mi")
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var caloriesChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calories Burned")
                .font(.headline)

            Chart(filteredSummaries) { summary in
                BarMark(
                    x: .value("Date", formatDateShort(summary.date)),
                    y: .value("Calories", summary.calories)
                )
                .foregroundStyle(.orange.gradient)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var speedComparisonChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed Analysis")
                .font(.headline)

            Chart(filteredSummaries) { summary in
                BarMark(
                    x: .value("Date", formatDateShort(summary.date)),
                    y: .value("Speed", summary.avgSpeed * 2.23694) // m/s to mph
                )
                .foregroundStyle(.purple.gradient)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let mph = value.as(Double.self) {
                            Text("\(mph, specifier: "%.1f") mph")
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    // MARK: - Computed Properties

    private var totalSteps: Int64 {
        filteredSummaries.reduce(0) { $0 + $1.steps }
    }

    private var totalDistance: Int64 {
        filteredSummaries.reduce(0) { $0 + $1.distanceMeters }
    }

    private var totalCalories: Int64 {
        filteredSummaries.reduce(0) { $0 + $1.calories }
    }

    // MARK: - Helper Methods

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            activityDates = try await apiClient.fetchActivityDates()

            var summaries: [DailySummary] = []
            for date in activityDates {
                if let summary = try? await apiClient.fetchDailySummary(date: date) {
                    summaries.append(summary)
                }
            }

            dailySummaries = summaries.sorted { $0.date < $1.date }
        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func formatDateShort(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }

        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func formatNumber(_ num: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }

    private func formatDistance(_ meters: Int64) -> String {
        let miles = Double(meters) / 1609.34
        return String(format: "%.2f mi", miles)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No activity data yet")
                .foregroundColor(.secondary)
            Text("Start using your treadmill to see stats here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Calendar Heatmap

struct CalendarHeatmapView: View {
    let summaries: [DailySummary]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let calendar = Calendar.current

    private var weeks: [[Date?]] {
        guard let firstDate = summaries.first?.dateDisplay,
              let lastDate = summaries.last?.dateDisplay else {
            return []
        }

        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: firstDate))!
        let endDate = calendar.date(byAdding: .day, value: 1, to: lastDate)!

        var result: [[Date?]] = []
        var currentWeek: [Date?] = []
        var currentDate = startOfWeek

        // Fill in days before first date
        let firstWeekday = calendar.component(.weekday, from: startOfWeek)
        for _ in 1..<firstWeekday {
            currentWeek.append(nil)
        }

        while currentDate < endDate {
            currentWeek.append(currentDate)

            if currentWeek.count == 7 {
                result.append(currentWeek)
                currentWeek = []
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        // Fill in remaining days
        while !currentWeek.isEmpty && currentWeek.count < 7 {
            currentWeek.append(nil)
        }
        if !currentWeek.isEmpty {
            result.append(currentWeek)
        }

        return result
    }

    private func stepsForDate(_ date: Date) -> Int64? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        return summaries.first(where: { $0.date == dateString })?.steps
    }

    private func colorForSteps(_ steps: Int64?) -> Color {
        guard let steps = steps else {
            return Color(.systemGray6)
        }

        let maxSteps = summaries.map { $0.steps }.max() ?? 1
        let intensity = Double(steps) / Double(maxSteps)

        if intensity > 0.75 {
            return .blue.opacity(1.0)
        } else if intensity > 0.5 {
            return .blue.opacity(0.7)
        } else if intensity > 0.25 {
            return .blue.opacity(0.4)
        } else if intensity > 0 {
            return .blue.opacity(0.2)
        } else {
            return Color(.systemGray6)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Weekday labels
            HStack(spacing: 4) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
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
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colorForSteps(steps))
                                .frame(height: 40)
                                .overlay(
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(.caption2)
                                        .foregroundColor(steps != nil && steps! > 0 ? .white : .secondary)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.clear)
                                .frame(height: 40)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 8) {
                Text("Less")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.blue.opacity(intensity == 0 ? 0.1 : intensity))
                        .frame(width: 16, height: 16)
                }

                Text("More")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
}

#Preview {
    StatsView()
}
