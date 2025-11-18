import SwiftUI

struct WorkoutListView: View {
    @EnvironmentObject var syncManager: SyncManager

    @State private var liveWorkout: LiveWorkoutResponse?
    @State private var liveWorkoutTimer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Live Workout Banner
                if let liveWorkout = liveWorkout {
                    LiveWorkoutBanner(liveData: liveWorkout)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                // Workout List
                if syncManager.workouts.isEmpty {
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No Workouts")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text(syncManager.isConnected
                                 ? "Your workouts will appear here"
                                 : "Connect to your server in Settings tab")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 400)
                        .padding()
                    }
                    .refreshable {
                        await syncManager.checkConnection()
                        await syncManager.loadWorkouts()
                    }
                } else {
                    List {
                        ForEach(groupedWorkouts.keys.sorted().reversed(), id: \.self) { date in
                            Section(header: Text(formatSectionHeader(date))) {
                                ForEach(groupedWorkouts[date] ?? []) { workout in
                                    WorkoutRow(
                                        workout: workout,
                                        onSync: {
                                            Task {
                                                await syncManager.syncWorkout(workout)
                                            }
                                        },
                                        onDelete: {
                                            Task {
                                                await syncManager.deleteWorkout(workout)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await syncManager.checkConnection()
                        await syncManager.loadWorkouts()
                    }
                }
            }
            .alert("Sync Error", isPresented: .constant(syncManager.syncError != nil)) {
                Button("OK") {
                    syncManager.syncError = nil
                }
            } message: {
                Text(syncManager.syncError?.localizedDescription ?? "Unknown error")
            }
            .alert("Sync Complete", isPresented: .constant(syncManager.syncSuccessMessage != nil)) {
                Button("OK") {
                    syncManager.syncSuccessMessage = nil
                }
            } message: {
                Text(syncManager.syncSuccessMessage ?? "")
            }
            .onAppear {
                startLiveWorkoutPolling()
            }
            .onDisappear {
                stopLiveWorkoutPolling()
            }
        }
    }

    // MARK: - Live Workout Polling

    private func startLiveWorkoutPolling() {
        // Fetch immediately
        fetchLiveWorkout()

        // Then poll every 2 seconds
        liveWorkoutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            fetchLiveWorkout()
        }
    }

    private func stopLiveWorkoutPolling() {
        liveWorkoutTimer?.invalidate()
        liveWorkoutTimer = nil
    }

    private func fetchLiveWorkout() {
        guard syncManager.isConnected else {
            liveWorkout = nil
            return
        }

        Task {
            let data = await syncManager.fetchLiveWorkout()
            await MainActor.run {
                liveWorkout = data
            }
        }
    }

    // Group workouts by date
    private var groupedWorkouts: [String: [Workout]] {
        Dictionary(grouping: syncManager.workouts) { workout in
            guard let start = workout.start else { return "Unknown" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: start)
        }
    }

    private func formatSectionHeader(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let date = formatter.date(from: dateString) {
            let workoutDate = calendar.startOfDay(for: date)
            if workoutDate == today {
                return "Today"
            } else if workoutDate == calendar.date(byAdding: .day, value: -1, to: today) {
                return "Yesterday"
            }
        }

        return dateString
    }
}

struct WorkoutRow: View {
    let workout: Workout
    let onSync: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Workout Info
            VStack(alignment: .leading, spacing: 8) {
                Text(workout.dateFormatted)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    Label(workout.durationFormatted, systemImage: "clock")
                    Label(workout.distanceFormatted, systemImage: "figure.walk")
                    Label(workout.caloriesFormatted, systemImage: "flame")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                if let avgHR = workout.avgHeartRate, let maxHR = workout.maxHeartRate {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("Avg: \(avgHR) bpm")
                        Text("•")
                        Text("Max: \(maxHR) bpm")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action Buttons
            VStack(spacing: 8) {
                Button(action: onSync) {
                    Image(systemName: "heart.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        WorkoutListView()
            .environmentObject(SyncManager())
    }
}
