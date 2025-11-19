import SwiftUI

struct WorkoutDetailView: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) var dismiss
    let workout: Workout

    var body: some View {
        List {
            // Summary Section
            Section("Summary") {
                DetailRow(icon: "calendar", label: "Date", value: workout.dateFormatted)
                DetailRow(icon: "clock", label: "Duration", value: workout.durationFormatted)
                DetailRow(icon: "figure.walk", label: "Distance", value: workout.distanceFormatted)
                DetailRow(icon: "flame", label: "Calories", value: workout.caloriesFormatted)
            }

            // Performance Section
            if workout.avgSpeed != nil || workout.maxSpeed != nil {
                Section("Performance") {
                    if let avgSpeed = workout.avgSpeed {
                        DetailRow(
                            icon: "speedometer",
                            label: "Avg Speed",
                            value: String(format: "%.2f mph", avgSpeed * 2.23694)
                        )
                    }
                    if let maxSpeed = workout.maxSpeed {
                        DetailRow(
                            icon: "speedometer",
                            label: "Max Speed",
                            value: String(format: "%.2f mph", maxSpeed * 2.23694)
                        )
                    }
                    if let avgIncline = workout.avgIncline {
                        DetailRow(
                            icon: "arrow.up.right",
                            label: "Avg Incline",
                            value: String(format: "%.1f%%", avgIncline)
                        )
                    }
                    if let maxIncline = workout.maxIncline {
                        DetailRow(
                            icon: "arrow.up.right",
                            label: "Max Incline",
                            value: String(format: "%.1f%%", maxIncline)
                        )
                    }
                }
            }

            // Heart Rate Section
            if workout.avgHeartRate != nil || workout.maxHeartRate != nil {
                Section("Heart Rate") {
                    if let avgHR = workout.avgHeartRate {
                        DetailRow(
                            icon: "heart",
                            label: "Average",
                            value: "\(avgHR) bpm",
                            iconColor: .red
                        )
                    }
                    if let maxHR = workout.maxHeartRate {
                        DetailRow(
                            icon: "heart.fill",
                            label: "Maximum",
                            value: "\(maxHR) bpm",
                            iconColor: .red
                        )
                    }
                }
            }

            // Actions Section
            Section {
                Button {
                    Task {
                        await syncManager.syncWorkout(workout)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "heart.circle.fill")
                            .font(.title3)
                        Text("Add to Apple Health")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.green.opacity(0.1))
                .foregroundColor(.green)

                Button(role: .destructive) {
                    Task {
                        await syncManager.deleteWorkout(workout)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Workout")
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var iconColor: Color = .blue

    var body: some View {
        HStack {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 24)
            }
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
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
            avgSpeed: 1.78,
            maxSpeed: 2.5,
            avgIncline: 2.5,
            maxIncline: 5.0,
            totalCalories: 250,
            avgHeartRate: 145,
            maxHeartRate: 165,
            samplesUrl: "/api/workouts/1/samples"
        ))
    }
}
