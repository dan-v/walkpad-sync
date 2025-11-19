import SwiftUI
import Combine

struct WorkoutListView: View {
    @EnvironmentObject var syncManager: SyncManager

    @State private var liveWorkoutData: LiveWorkoutResponse?
    @State private var updateTask: Task<Void, Never>?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Live Workout Banner (tappable)
                if let liveData = liveWorkoutData, liveData.workout != nil {
                    NavigationLink(destination: LiveWorkoutDetailView(liveData: liveData)) {
                        LiveWorkoutBanner(liveData: liveData)
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
                setupLiveWorkoutUpdates()
            }
            .onDisappear {
                updateTask?.cancel()
                cancellables.removeAll()
            }
        }
    }

    // MARK: - Live Workout via WebSocket

    private func setupLiveWorkoutUpdates() {
        print("🔧 WorkoutListView: Setting up live workout updates")

        // Watch for changes to liveWorkout from WebSocket
        syncManager.$liveWorkout
            .sink { workout in
                print("📢 WorkoutListView: liveWorkout changed to: \(workout?.id ?? -1)")
                Task { @MainActor in
                    if workout != nil {
                        print("  ▶️ Active workout detected, fetching live data...")
                        // WebSocket says there's an active workout - fetch full data with metrics
                        await self.fetchLiveWorkoutData()
                        self.startPeriodicUpdates()
                    } else {
                        print("  ⏸️ No active workout, clearing live data")
                        // No active workout
                        self.liveWorkoutData = nil
                        self.updateTask?.cancel()
                    }
                }
            }
            .store(in: &cancellables)

        // Initial fetch if there's already a live workout
        if syncManager.liveWorkout != nil {
            print("🏁 WorkoutListView: Initial live workout detected: \(syncManager.liveWorkout!.id)")
            Task {
                await fetchLiveWorkoutData()
                startPeriodicUpdates()
            }
        } else {
            print("🏁 WorkoutListView: No initial live workout")
        }
    }

    private func startPeriodicUpdates() {
        updateTask?.cancel()

        updateTask = Task {
            while !Task.isCancelled && syncManager.liveWorkout != nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Update every 2 seconds
                await fetchLiveWorkoutData()
            }
        }
    }

    private func fetchLiveWorkoutData() async {
        guard syncManager.isConnected else {
            print("⚠️ WorkoutListView: Not connected, clearing live workout data")
            liveWorkoutData = nil
            return
        }

        print("🔍 WorkoutListView: Fetching live workout data...")
        let data = await syncManager.fetchLiveWorkout()
        if let data = data {
            print("✅ WorkoutListView: Received live workout data - workout: \(data.workout?.id ?? -1), has metrics: \(data.currentMetrics != nil)")
            liveWorkoutData = data
        } else {
            print("⚠️ WorkoutListView: fetchLiveWorkout returned nil")
            liveWorkoutData = nil
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
