import SwiftUI

struct WorkoutListView: View {
    @EnvironmentObject var syncManager: SyncManager

    @State private var showingServerSetup = false

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
                            Text("Tap to configure your Raspberry Pi server")
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
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(syncManager.isSyncing ? "Syncing..." : "Sync Now")
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
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
                    await syncManager.performSync()
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
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
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
