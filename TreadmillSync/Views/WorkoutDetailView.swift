import SwiftUI
import Charts

struct WorkoutDetailView: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) var dismiss
    let workout: Workout

    @State private var samples: [WorkoutSample] = []
    @State private var isLoadingSamples = false
    @State private var showingCharts = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Date & Time
                VStack(spacing: 4) {
                    Text(workout.dateFormatted)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(workout.durationFormatted)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatCard(
                        icon: "figure.walk",
                        label: "Distance",
                        value: workout.distanceFormatted,
                        color: .blue
                    )

                    StatCard(
                        icon: "shoeprints.fill",
                        label: "Steps",
                        value: formatSteps(),
                        color: .purple
                    )

                    StatCard(
                        icon: "flame.fill",
                        label: "Calories",
                        value: workout.caloriesFormatted,
                        color: .orange
                    )

                    StatCard(
                        icon: "speedometer",
                        label: "Avg Speed",
                        value: formatSpeed(),
                        color: .green
                    )

                    if let maxSpeed = workout.maxSpeed {
                        StatCard(
                            icon: "hare.fill",
                            label: "Max Speed",
                            value: String(format: "%.1f mph", maxSpeed * 2.23694),
                            color: .red
                        )
                    }

                    if let avgPace = calculatePace() {
                        StatCard(
                            icon: "timer",
                            label: "Avg Pace",
                            value: avgPace,
                            color: .cyan
                        )
                    }

                    if let avgHR = workout.avgHeartRate {
                        StatCard(
                            icon: "heart.fill",
                            label: "Avg Heart Rate",
                            value: String(format: "%.0f bpm", avgHR),
                            color: .pink
                        )
                    }

                    if let maxHR = workout.maxHeartRate {
                        StatCard(
                            icon: "bolt.heart.fill",
                            label: "Max Heart Rate",
                            value: "\(maxHR) bpm",
                            color: .pink
                        )
                    }

                    if let avgIncline = workout.avgIncline {
                        StatCard(
                            icon: "mountain.2.fill",
                            label: "Avg Incline",
                            value: String(format: "%.1f%%", avgIncline),
                            color: .brown
                        )
                    }

                    if let maxIncline = workout.maxIncline {
                        StatCard(
                            icon: "arrow.up.right",
                            label: "Max Incline",
                            value: String(format: "%.1f%%", maxIncline),
                            color: .brown
                        )
                    }
                }
                .padding(.horizontal)

                // Charts Section
                if showingCharts && !samples.isEmpty {
                    VStack(spacing: 20) {
                        // Speed Chart
                        ChartSection(title: "Speed Over Time", icon: "speedometer", color: .green) {
                            Chart(samples) { sample in
                                if let speed = sample.speed, let date = sample.date {
                                    LineMark(
                                        x: .value("Time", date),
                                        y: .value("Speed", speed * 2.23694) // Convert to mph
                                    )
                                    .foregroundStyle(.green)
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading)
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 4))
                            }
                        }

                        // Heart Rate Chart
                        if samples.contains(where: { $0.heartRate != nil }) {
                            ChartSection(title: "Heart Rate", icon: "heart.fill", color: .pink) {
                                Chart(samples) { sample in
                                    if let hr = sample.heartRate, hr > 0, let date = sample.date {
                                        LineMark(
                                            x: .value("Time", date),
                                            y: .value("BPM", hr)
                                        )
                                        .foregroundStyle(.pink)
                                        .interpolationMethod(.catmullRom)
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks(position: .leading)
                                }
                                .chartXAxis {
                                    AxisMarks(values: .automatic(desiredCount: 4))
                                }
                            }
                        }

                        // Incline Chart
                        if samples.contains(where: { $0.incline != nil }) {
                            ChartSection(title: "Incline", icon: "mountain.2.fill", color: .brown) {
                                Chart(samples) { sample in
                                    if let incline = sample.incline, let date = sample.date {
                                        LineMark(
                                            x: .value("Time", date),
                                            y: .value("Incline %", incline)
                                        )
                                        .foregroundStyle(.brown)
                                        .interpolationMethod(.catmullRom)
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks(position: .leading)
                                }
                                .chartXAxis {
                                    AxisMarks(values: .automatic(desiredCount: 4))
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Load Charts Button
                if !showingCharts {
                    Button {
                        Task {
                            await loadSamples()
                        }
                    } label: {
                        HStack {
                            if isLoadingSamples {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "chart.xyaxis.line")
                            }
                            Text(isLoadingSamples ? "Loading Charts..." : "Show Detailed Charts")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isLoadingSamples)
                    .padding(.horizontal)
                }

                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await syncManager.syncWorkout(workout)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "heart.circle.fill")
                                .font(.title3)
                            Text("Add to Apple Health")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button(role: .destructive) {
                        Task {
                            await syncManager.deleteWorkout(workout)
                            dismiss()
                        }
                    } label: {
                        Text("Delete Workout")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadSamples() async {
        isLoadingSamples = true
        defer { isLoadingSamples = false }

        do {
            let apiClient = APIClient(config: syncManager.serverConfig)
            let response = try await apiClient.fetchWorkoutSamples(workoutId: workout.id)
            samples = response
            withAnimation {
                showingCharts = true
            }
        } catch {
            print("Failed to load samples: \(error)")
        }
    }

    private func formatSteps() -> String {
        guard let steps = workout.totalSteps else { return "N/A" }
        return "\(steps)"
    }

    private func formatSpeed() -> String {
        guard let avgSpeed = workout.avgSpeed else { return "N/A" }
        let mph = avgSpeed * 2.23694
        return String(format: "%.1f mph", mph)
    }

    private func calculatePace() -> String? {
        guard let avgSpeed = workout.avgSpeed, avgSpeed > 0 else { return nil }
        let milesPerHour = avgSpeed * 2.23694
        let minutesPerMile = 60.0 / milesPerHour
        let minutes = Int(minutesPerMile)
        let seconds = Int((minutesPerMile - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
}

struct ChartSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }

            content
                .frame(height: 200)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
        }
    }
}

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)

            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(workout: Workout(
            id: 1,
            workoutUuid: "test",
            startTime: ISO8601DateFormatter().string(from: Date()),
            endTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(1800)),
            totalDuration: 1800,
            totalDistance: 3200,
            totalSteps: 2400,
            avgSpeed: 1.78,
            maxSpeed: 2.5,
            totalCalories: 250,
            avgHeartRate: 135.0,
            maxHeartRate: 165,
            avgIncline: 2.5,
            maxIncline: 5.0,
            samplesUrl: "/api/workouts/1/samples"
        ))
        .environmentObject(SyncManager())
    }
}
