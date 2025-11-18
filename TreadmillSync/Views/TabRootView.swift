//
//  TabRootView.swift
//  TreadmillSync
//
//  Beautiful tab-based interface - NO scrolling, everything fits on screen
//

import SwiftUI

struct TabRootView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayTab()
                .tabItem {
                    Label("Today", systemImage: "figure.walk")
                }
                .tag(0)

            ActivityTab()
                .tabItem {
                    Label("Activity", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(1)

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
            VStack(spacing: 0) {
                // Stats area - takes most space
                VStack(spacing: 20) {
                    Spacer()

                    if sessionManager.currentSession.hasData {
                        // Giant step count
                        VStack(spacing: 8) {
                            Text("\(sessionManager.currentSession.totalSteps)")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)

                            Text("steps today")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Compact stats row
                        HStack(spacing: 16) {
                            QuickStat(icon: "map", value: String(format: "%.1f", sessionManager.currentSession.totalDistanceMiles), unit: "mi")
                            QuickStat(icon: "flame", value: "\(sessionManager.currentSession.totalCalories)", unit: "cal")
                            QuickStat(icon: "clock", value: sessionManager.currentSession.formattedDuration, unit: "")
                        }
                        .padding(.horizontal)
                    } else {
                        // Onboarding - clean and simple
                        VStack(spacing: 16) {
                            Image(systemName: "figure.walk.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.blue.opacity(0.3))

                            VStack(spacing: 8) {
                                Text("Ready to Walk")
                                    .font(.title2.bold())

                                Text("Turn on your treadmill to start")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()
                }

                // Bottom section - connection + action
                VStack(spacing: 12) {
                    // Connection status
                    StatusRow(
                        state: coordinator.treadmillManager.connectionState,
                        isCollecting: coordinator.isAutoCollecting,
                        onRetry: retryConnection
                    )

                    // Save button
                    if sessionManager.currentSession.hasData {
                        Button(action: { showReviewSheet = true }) {
                            HStack {
                                Image(systemName: "heart.fill")
                                Text("Review & Save")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.blue)
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
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
                                    userInfo: [NSLocalizedDescriptionKey: "Save timeout"])
                    }
                    try await group.next()
                    group.cancelAll()
                }
                showReviewSheet = false
                alertMessage = "Saved to Apple Health! 🎉"
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
            VStack(spacing: 0) {
                if !sessionManager.currentSession.activitySegments.isEmpty {
                    // Sessions list - fits on screen
                    VStack(spacing: 0) {
                        ForEach(Array(sessionManager.currentSession.activitySegments.enumerated()), id: \.element.id) { index, segment in
                            SessionRow(number: index + 1, segment: segment)

                            if index < sessionManager.currentSession.activitySegments.count - 1 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }

                    Spacer()

                    // Summary
                    VStack(spacing: 8) {
                        Text("\(sessionManager.currentSession.activitySegments.count) session\(sessionManager.currentSession.activitySegments.count == 1 ? "" : "s") today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()

                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary.opacity(0.5))

                        Text("No Activity Yet")
                            .font(.title3.bold())

                        Text("Start walking to see your sessions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Components

struct QuickStat: View {
    let icon: String
    let value: String
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.callout)
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct StatusRow: View {
    let state: ConnectionState
    let isCollecting: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.description)
                        .font(.subheadline.weight(.medium))

                    if isCollecting {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("Auto-syncing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )

            // Retry button for BLE-off
            if state.needsManualReconnect, let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Press BLE button, then reconnect")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
            }
        }
    }

    private var iconName: String {
        switch state {
        case .connected: return "antenna.radiowaves.left.and.right"
        case .disconnectedBLEOff: return "bluetooth.slash"
        case .error: return "exclamationmark.triangle"
        default: return "figure.walk"
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

struct SessionRow: View {
    let number: Int
    let segment: DailySession.ActivitySegment

    var body: some View {
        HStack(spacing: 16) {
            // Number circle
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.15))
                    .frame(width: 44, height: 44)

                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }

            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 12) {
                    Label("\(segment.steps)", systemImage: "figure.walk")
                    Label(String(format: "%.1f mi", segment.distanceMiles), systemImage: "map")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: segment.startTime)
        let end = formatter.string(from: segment.endTime)
        return "\(start) - \(end)"
    }
}

#Preview {
    TabRootView()
}
