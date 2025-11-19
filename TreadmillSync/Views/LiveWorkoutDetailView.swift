import SwiftUI
import Charts

struct LiveWorkoutDetailView: View {
    @EnvironmentObject var syncManager: SyncManager
    let liveData: LiveWorkoutResponse

    @State private var currentLiveData: LiveWorkoutResponse?
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        let data = currentLiveData ?? liveData

        ScrollView {
            VStack(spacing: 20) {
                // Live Indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                    Text("LIVE WORKOUT IN PROGRESS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                .padding(.top, 20)

                // Elapsed Time
                if let workout = data.workout, let start = workout.start {
                    Text(formatElapsedTime(from: start))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                // Current Metrics Grid
                if let metrics = data.currentMetrics {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        LiveMetricCard(
                            icon: "speedometer",
                            label: "Speed",
                            value: metrics.speedFormatted,
                            unit: "mph",
                            color: .green
                        )

                        LiveMetricCard(
                            icon: "figure.walk",
                            label: "Distance",
                            value: metrics.distanceFormatted,
                            unit: "mi",
                            color: .blue
                        )

                        LiveMetricCard(
                            icon: "shoeprints.fill",
                            label: "Steps",
                            value: metrics.stepsFormatted,
                            unit: "steps",
                            color: .purple
                        )

                        LiveMetricCard(
                            icon: "flame.fill",
                            label: "Calories",
                            value: metrics.caloriesFormatted,
                            unit: "kcal",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)
                }

                // Recent Trend Chart
                if !data.recentSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(.green)
                            Text("Speed Trend (Last 20 samples)")
                                .font(.headline)
                        }
                        .padding(.horizontal)

                        Chart(data.recentSamples) { sample in
                            if let speed = sample.speed, let date = sample.date {
                                LineMark(
                                    x: .value("Time", date),
                                    y: .value("Speed", speed * 2.23694)
                                )
                                .foregroundStyle(.green)
                                .interpolationMethod(.catmullRom)

                                AreaMark(
                                    x: .value("Time", date),
                                    y: .value("Speed", speed * 2.23694)
                                )
                                .foregroundStyle(
                                    .linearGradient(
                                        colors: [.green.opacity(0.3), .green.opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .frame(height: 200)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }

                // Info Message
                Text("This workout is currently in progress. Data updates every 2 seconds.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
        }
        .navigationTitle("Live Workout")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startLivePolling()
        }
        .onDisappear {
            stopLivePolling()
        }
    }

    private func startLivePolling() {
        pollingTask?.cancel()

        pollingTask = Task {
            while !Task.isCancelled {
                if let data = await syncManager.fetchLiveWorkout() {
                    currentLiveData = data
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopLivePolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func formatElapsedTime(from start: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(start))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

struct LiveMetricCard: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(color)

            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        LiveWorkoutDetailView(liveData: LiveWorkoutResponse(
            workout: Workout(
                id: 1,
                workoutUuid: "test",
                startTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600)),
                endTime: nil,
                totalDuration: nil,
                totalDistance: nil,
                totalSteps: nil,
                avgSpeed: nil,
                maxSpeed: nil,
                totalCalories: nil,
                samplesUrl: "/api/workouts/1/samples"
            ),
            currentMetrics: LiveWorkoutMetrics(
                currentSpeed: 1.8,
                distanceSoFar: 1200,
                stepsSoFar: 950,
                caloriesSoFar: 85
            ),
            recentSamples: []
        ))
        .environmentObject(SyncManager())
    }
}
