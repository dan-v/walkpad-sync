//
//  TabRootView.swift
//  TreadmillSync
//
//  Beautiful tab-based interface for iOS
//

import SwiftUI

struct TabRootView: View {
    @State private var selectedTab = 0
    @State private var coordinator = WorkoutCoordinator.shared
    @State private var sessionManager = DailySessionManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // Today Tab - Main stats and quick actions
            TodayTab()
                .tabItem {
                    Label("Today", systemImage: "figure.walk")
                }
                .tag(0)

            // Activity Tab - Timeline and history
            ActivityTab()
                .tabItem {
                    Label("Activity", systemImage: "chart.xyaxis.line")
                }
                .tag(1)

            // Settings Tab
            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
        .tint(.blue)
    }
}

// MARK: - Today Tab

struct TodayTab: View {
    @State private var coordinator = WorkoutCoordinator.shared
    @State private var sessionManager = DailySessionManager.shared
    @State private var showReviewSheet = false
    @State private var isSavingWorkout = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Big stats at top
                    if sessionManager.currentSession.hasData {
                        StatsHeroCard(session: sessionManager.currentSession)
                    } else {
                        EmptyStateCard()
                    }

                    // Connection status (compact)
                    CompactConnectionCard(
                        state: coordinator.treadmillManager.connectionState,
                        isCollecting: coordinator.isAutoCollecting,
                        onRetry: retryConnection
                    )

                    // Live stats (only when connected)
                    if coordinator.treadmillManager.connectionState.isConnected {
                        LiveDataCard(data: coordinator.treadmillManager.currentData)
                    }

                    // Save button (when has data)
                    if sessionManager.currentSession.hasData {
                        SaveButton(action: { showReviewSheet = true })
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .sheet(isPresented: $showReviewSheet) {
                SessionReviewSheet(
                    session: sessionManager.currentSession,
                    isSaving: $isSavingWorkout,
                    onSave: saveWorkout,
                    onCancel: { showReviewSheet = false }
                )
            }
            .alert("Workout", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK") { alertMessage = nil }
            } message: {
                if let message = alertMessage {
                    Text(message)
                }
            }
        }
    }

    private func saveWorkout() {
        guard !isSavingWorkout else { return }
        isSavingWorkout = true

        Task { @MainActor in
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await coordinator.saveWorkout() }
                    group.addTask {
                        try await Task.sleep(for: .seconds(30))
                        throw NSError(domain: "TreadmillSync", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Save timeout - please try again"])
                    }
                    try await group.next()
                    group.cancelAll()
                }
                showReviewSheet = false
                alertMessage = "Workout saved! 🎉"
            } catch {
                alertMessage = error.localizedDescription
            }
            isSavingWorkout = false
        }
    }

    private func retryConnection() {
        Task { await coordinator.treadmillManager.retryConnection() }
    }
}

// MARK: - Activity Tab

struct ActivityTab: View {
    @State private var sessionManager = DailySessionManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if !sessionManager.currentSession.activitySegments.isEmpty {
                    ScrollView {
                        VStack(spacing: 16) {
                            ActivityTimelineCard(segments: sessionManager.currentSession.activitySegments)
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "No Activity Yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Start walking to see your activity timeline")
                    )
                }
            }
            .navigationTitle("Activity")
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @State private var coordinator = WorkoutCoordinator.shared

    var body: some View {
        NavigationStack {
            SettingsView(treadmillManager: coordinator.treadmillManager)
        }
    }
}

// MARK: - Stats Hero Card (Big numbers)

struct StatsHeroCard: View {
    let session: DailySession

    var body: some View {
        VStack(spacing: 16) {
            // Giant step count
            VStack(spacing: 4) {
                Text("\(session.totalSteps)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)

                Text("steps")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Other stats grid
            HStack(spacing: 16) {
                StatPill(
                    icon: "map",
                    value: String(format: "%.1f", session.totalDistanceMiles),
                    unit: "mi"
                )

                StatPill(
                    icon: "flame",
                    value: "\(session.totalCalories)",
                    unit: "cal"
                )

                StatPill(
                    icon: "clock",
                    value: session.formattedDuration,
                    unit: ""
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.blue.opacity(0.1))
        )
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)

            HStack(spacing: 2) {
                Text(value)
                    .font(.headline)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}

// MARK: - Empty State

struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk.circle")
                .font(.system(size: 60))
                .foregroundStyle(.blue.opacity(0.5))

            Text("Ready to Walk")
                .font(.title2.bold())

            Text("Turn on your treadmill\nand start moving")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.blue.opacity(0.05))
        )
    }
}

// MARK: - Compact Connection Card

struct CompactConnectionCard: View {
    let state: ConnectionState
    let isCollecting: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(state.description, systemImage: iconName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor)

                Spacer()

                if isCollecting {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Auto-sync")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Retry button for BLE-off
            if state.needsManualReconnect, let onRetry = onRetry {
                Button(action: onRetry) {
                    Label("Press BLE button, then reconnect", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var iconName: String {
        switch state {
        case .connected: return "antenna.radiowaves.left.and.right"
        case .disconnectedBLEOff: return "bluetooth.slash"
        default: return "figure.walk.slash"
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected: return .green
        case .disconnectedBLEOff: return .orange
        case .error: return .red
        default: return .secondary
        }
    }
}

// MARK: - Live Data Card

struct LiveDataCard: View {
    let data: TreadmillData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Stats")
                .font(.headline)

            HStack(spacing: 20) {
                if let speed = data.speed {
                    LiveStat(icon: "speedometer", value: String(format: "%.1f", speed), unit: "mph")
                }

                if let time = data.time {
                    LiveStat(icon: "timer", value: String(format: "%02d:%02d", time.minutes, time.seconds), unit: "")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct LiveStat: View {
    let icon: String
    let value: String
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)

            Text(value)
                .font(.title3.bold())

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Save Button

struct SaveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Review & Save to Health", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
        }
    }
}

#Preview {
    TabRootView()
}
