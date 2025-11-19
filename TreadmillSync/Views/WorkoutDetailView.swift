import SwiftUI

struct WorkoutDetailView: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) var dismiss
    let workout: Workout

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

                // Stats Grid (2x2)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
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
                }
                .padding(.horizontal)

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

    private func formatSteps() -> String {
        guard let steps = workout.totalSteps else { return "N/A" }
        return "\(steps)"
    }

    private func formatSpeed() -> String {
        guard let avgSpeed = workout.avgSpeed else { return "N/A" }
        let mph = avgSpeed * 2.23694
        return String(format: "%.1f mph", mph)
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
            samplesUrl: "/api/workouts/1/samples"
        ))
        .environmentObject(SyncManager())
    }
}
