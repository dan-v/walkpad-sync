import SwiftUI

struct WorkoutListView: View {
    @EnvironmentObject var syncManager: SyncManager

    @State private var showingServerSetup = false
    @State private var liveWorkout: LiveWorkoutResponse?
    @State private var liveWorkoutTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Server Setup Banner (if not connected)
            if !syncManager.isConnected {
                Button {
                    showingServerSetup = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Server Not Connected")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Tap to configure your sync server")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingServerSetup) {
                    SettingsView()
                }
            }

            // Live Workout Banner
            if let liveWorkout = liveWorkout {
                LiveWorkoutBanner(liveData: liveWorkout)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            // Status Header
            VStack(spacing: 12) {
                // Connection Status
                HStack {
                    Circle()
                        .fill(syncManager.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(syncManager.isConnected ? "Connected to \(syncManager.serverConfig.host)" : "Disconnected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let lastSync = syncManager.lastSyncDate {
                        Text("Last sync: \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Sync Button
                Button {
                    Task {
                        await syncManager.performSync()
                    }
                } label: {
                    HStack {
                        if syncManager.isSyncing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "heart.circle.fill")
                        }
                        Text(syncManager.isSyncing ? "Syncing to Apple Health..." : "Sync All to Apple Health")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(syncManager.isConnected ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!syncManager.isConnected || syncManager.isSyncing)
                .padding(.horizontal)

                // Pending Count
                if syncManager.pendingCount > 0 {
                    HStack {
                        Image(systemName: "tray.fill")
                            .foregroundColor(.orange)
                        Text("\(syncManager.pendingCount) pending workout\(syncManager.pendingCount == 1 ? "" : "s")")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }
            }
            .padding(.vertical)
            .background(Color(.systemGroupedBackground))

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
                             : "Connect to your server in settings")
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
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        Task {
                                            await syncManager.syncWorkout(workout)
                                        }
                                    } label: {
                                        Label("Sync", systemImage: "heart.circle.fill")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task {
                                            await syncManager.deleteWorkout(workout)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workout.dateFormatted)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text("Pending")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

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
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        WorkoutListView()
            .environmentObject(SyncManager())
    }
}
