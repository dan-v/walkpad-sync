import SwiftUI

struct WorkoutListView: View {
    @EnvironmentObject var syncManager: SyncManager

    @State private var liveWorkout: LiveWorkoutResponse?
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Live Workout Banner (tappable)
                if let liveWorkout = liveWorkout, let workout = liveWorkout.workout {
                    NavigationLink(destination: LiveWorkoutDetailView(liveData: liveWorkout)) {
                        LiveWorkoutBanner(liveData: liveWorkout)
                    }
                    .buttonStyle(.plain)
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
                                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                        WorkoutRow(workout: workout)
                                    }
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
        // Cancel any existing task
        pollingTask?.cancel()

        // Start new polling task
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchLiveWorkout()

                // Only continue polling if there's an active workout
                if liveWorkout == nil {
                    // If no active workout, check less frequently (every 5 seconds)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                } else {
                    // Active workout - poll every 2 seconds
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    private func stopLiveWorkoutPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        liveWorkout = nil
    }

    private func fetchLiveWorkout() async {
        guard syncManager.isConnected else {
            liveWorkout = nil
            return
        }

        let data = await syncManager.fetchLiveWorkout()
        liveWorkout = data
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

    var body: some View {
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
