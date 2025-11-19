import SwiftUI
import Charts

struct StatsView: View {
    private let apiClient = APIClient(config: ServerConfig.load())
    @State private var activityDates: [String] = []
    @State private var dailySummaries: [DailySummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Loading stats...")
                            .padding()
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            Text(error)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else if dailySummaries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No activity data yet")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    } else {
                        // Overview Cards
                        overviewCards

                        // Charts
                        if dailySummaries.count > 1 {
                            stepsChart
                            distanceChart
                            caloriesChart
                            activeTimeChart
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await loadData()
                        }
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

    private var overviewCards: some View {
        VStack(spacing: 16) {
            Text("Last 30 Days")
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
                    value: "\(dailySummaries.count)",
                    icon: "calendar",
                    color: .purple
                )
            }
        }
    }

    private var stepsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps Trend")
                .font(.headline)

            Chart(dailySummaries) { summary in
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

            Chart(dailySummaries) { summary in
                LineMark(
                    x: .value("Date", formatDateShort(summary.date)),
                    y: .value("Distance", Double(summary.distanceMeters) / 1000.0)
                )
                .foregroundStyle(.green.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", formatDateShort(summary.date)),
                    y: .value("Distance", Double(summary.distanceMeters) / 1000.0)
                )
                .foregroundStyle(.green.gradient.opacity(0.2))
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let km = value.as(Double.self) {
                            Text("\(km, specifier: "%.1f") km")
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
            Text("Calories Trend")
                .font(.headline)

            Chart(dailySummaries) { summary in
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

    private var activeTimeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Time Trend")
                .font(.headline)

            Chart(dailySummaries) { summary in
                LineMark(
                    x: .value("Date", formatDateShort(summary.date)),
                    y: .value("Minutes", Double(summary.durationSeconds) / 60.0)
                )
                .foregroundStyle(.purple.gradient)
                .interpolationMethod(.catmullRom)
                .symbol(.circle)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let mins = value.as(Double.self) {
                            Text("\(Int(mins)) min")
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
        dailySummaries.reduce(0) { $0 + $1.steps }
    }

    private var totalDistance: Int64 {
        dailySummaries.reduce(0) { $0 + $1.distanceMeters }
    }

    private var totalCalories: Int64 {
        dailySummaries.reduce(0) { $0 + $1.calories }
    }

    // MARK: - Helper Methods

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Get activity dates
            activityDates = try await apiClient.fetchActivityDates()

            // Load last 30 days of summaries
            let last30Dates = activityDates.suffix(30)
            var summaries: [DailySummary] = []

            for date in last30Dates {
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
        let km = Double(meters) / 1000.0
        return String(format: "%.1f km", km)
    }
}

#Preview {
    StatsView()
}
