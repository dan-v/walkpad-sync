//
//  MainView.swift
//  TreadmillSync
//
//  Beautiful, data-rich main interface optimized for desk walking
//

import SwiftUI
import Charts

struct MainView: View {
    @State private var coordinator = WorkoutCoordinator.shared
    @State private var sessionManager = DailySessionManager.shared
    @State private var showSettings = false
    @State private var showReviewSheet = false
    @State private var isSavingWorkout = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [.blue.opacity(0.1), .purple.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection

                        // Connection Status Card
                        ConnectionStatusCard(
                            state: coordinator.treadmillManager.connectionState,
                            isCollecting: coordinator.isAutoCollecting
                        )

                        // Today's Session Card
                        if sessionManager.currentSession.hasData {
                            TodaySessionCard(
                                session: sessionManager.currentSession,
                                onSave: { showReviewSheet = true }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Live Stats (if connected)
                        if coordinator.treadmillManager.connectionState.isConnected {
                            LiveStatsCard(
                                data: coordinator.treadmillManager.currentData,
                                lastUpdate: coordinator.lastDataUpdate
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Activity Timeline
                        if !sessionManager.currentSession.activitySegments.isEmpty {
                            ActivityTimelineCard(
                                segments: sessionManager.currentSession.activitySegments
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Info Card
                        if !sessionManager.currentSession.hasData {
                            WelcomeCard()
                                .transition(.scale.combined(with: .opacity))
                        }

                        Spacer(minLength: 40)
                    }
                    .padding()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sessionManager.currentSession.hasData)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: coordinator.treadmillManager.connectionState)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("TreadmillSync")
                        .font(.title3.bold())
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(treadmillManager: coordinator.treadmillManager)
            }
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
                Button("OK", role: .cancel) {}
            } message: {
                if let alertMessage {
                    Text(alertMessage)
                }
            }
        }
        .task {
            await coordinator.start()
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.bold())
                Text(dateString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        case 17..<21:
            return "Good Evening"
        default:
            return "Good Night"
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    private func saveWorkout() {
        guard !isSavingWorkout else { return }
        isSavingWorkout = true

        Task { @MainActor in
            do {
                try await coordinator.saveWorkout()
                showReviewSheet = false
                alertMessage = "Workout saved to Apple Health! 🎉"
            } catch {
                alertMessage = error.localizedDescription
            }
            isSavingWorkout = false
        }
    }
}

// MARK: - Connection Status Card

struct ConnectionStatusCard: View {
    let state: ConnectionState
    let isCollecting: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, isActive: isAnimating)
                .frame(width: 60)

            // Status Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Treadmill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(state.description)
                    .font(.headline)
                    .foregroundStyle(statusColor)

                if isCollecting {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Auto-collecting data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
    }

    private var iconName: String {
        switch state {
        case .connected: return "figure.walk"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .scanning: return "magnifyingglass"
        case .disconnected: return "figure.walk.slash"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .connected: return .green
        case .connecting, .scanning: return .blue
        case .disconnected: return .secondary
        case .error: return .red
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected: return .green
        case .connecting, .scanning: return .blue
        case .disconnected: return .primary
        case .error: return .red
        }
    }

    private var isAnimating: Bool {
        state == .connecting || state == .scanning
    }
}

// MARK: - Today's Session Card

struct TodaySessionCard: View {
    let session: DailySession
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Workout")
                        .font(.headline)
                    Text("\(session.activitySegments.count) session\(session.activitySegments.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let updated = session.lastUpdated {
                    Text(updated, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatCard(icon: "figure.walk", label: "Steps", value: "\(session.totalSteps)", color: .blue)
                StatCard(icon: "map", label: "Distance", value: String(format: "%.2f mi", session.totalDistanceMiles), color: .green)
                StatCard(icon: "flame.fill", label: "Calories", value: "\(session.totalCalories)", color: .orange)
                StatCard(icon: "clock.fill", label: "Duration", value: session.formattedDuration, color: .purple)
            }

            // Save Button
            Button(action: onSave) {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Save to Apple Health")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
    }
}

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Live Stats Card

struct LiveStatsCard: View {
    let data: TreadmillData
    let lastUpdate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Live Data", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                if let lastUpdate {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Updated \(lastUpdate, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let speed = data.speed {
                    LiveStatRow(icon: "gauge", label: "Speed", value: String(format: "%.1f mph", speed))
                }
                if let time = data.time {
                    LiveStatRow(icon: "clock", label: "Time", value: time.formatted)
                }
                if let steps = data.steps {
                    LiveStatRow(icon: "figure.walk", label: "Steps", value: "\(steps)")
                }
                if let distance = data.distance {
                    LiveStatRow(icon: "map", label: "Distance", value: String(format: "%.2f mi", distance))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
    }
}

struct LiveStatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Activity Timeline Card

struct ActivityTimelineCard: View {
    let segments: [DailySession.ActivitySegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity Timeline")
                .font(.headline)

            Divider()

            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                HStack(spacing: 12) {
                    // Time marker
                    VStack(spacing: 4) {
                        Text(segment.startTime, style: .time)
                            .font(.caption.bold().monospacedDigit())
                        Rectangle()
                            .fill(.blue)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                        Text(segment.endTime, style: .time)
                            .font(.caption.bold().monospacedDigit())
                    }
                    .frame(width: 60)

                    // Segment info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session \(index + 1)")
                            .font(.subheadline.bold())
                        HStack(spacing: 12) {
                            Label("\(segment.steps)", systemImage: "figure.walk")
                            Label(String(format: "%.2f mi", segment.distanceMiles), systemImage: "map")
                            Label("\(segment.calories)", systemImage: "flame")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )

                if index < segments.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
    }
}

// MARK: - Welcome Card

struct WelcomeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text("Welcome to TreadmillSync")
                    .font(.headline)
            }

            Text("Your treadmill will automatically connect when powered on. Simply start walking, and your workout data will be tracked throughout the day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                WelcomeStep(number: 1, text: "Turn on your LifeSpan treadmill")
                WelcomeStep(number: 2, text: "Start walking at your desk")
                WelcomeStep(number: 3, text: "Data collects automatically all day")
                WelcomeStep(number: 4, text: "Save to Apple Health when done")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
    }
}

struct WelcomeStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    MainView()
}
