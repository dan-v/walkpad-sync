//
//  SimpleMainView.swift
//  TreadmillSync
//
//  Simple one-button interface to sync workout from treadmill
//

import SwiftUI

struct SimpleMainView: View {
    @State private var sync = SimpleTreadmillSync.shared
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 80))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.pulse, isActive: isAnimating)

                // Title
                Text("Treadmill Sync")
                    .font(.largeTitle.bold())

                // Status
                Text(sync.state.description)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Data Display
                if sync.steps > 0 || sync.distance > 0 || sync.calories > 0 {
                    VStack(spacing: 16) {
                        Divider()
                            .padding(.horizontal)

                        HStack(spacing: 30) {
                            DataPill(title: "Steps", value: "\(sync.steps)")
                            DataPill(title: "Distance", value: String(format: "%.2f mi", sync.distance))
                            DataPill(title: "Calories", value: "\(sync.calories)")
                        }
                    }
                }

                Spacer()

                // Main Action Button
                Button(action: syncWorkout) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(buttonText)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(buttonColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isLoading)
                .padding(.horizontal)

                // Instructions
                Text("Turn on your treadmill, then tap the button above to sync your workout to Apple Health.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 40)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Permission Required", isPresented: $showPermissionAlert) {
                Button("Grant Access") {
                    Task {
                        try? await sync.requestHealthAuthorization()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This app needs permission to save workout data to Apple Health.")
            }
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch sync.state {
        case .idle:
            return "figure.walk"
        case .scanning, .connecting:
            return "antenna.radiowaves.left.and.right"
        case .fetchingData:
            return "arrow.down.circle"
        case .savingToHealth:
            return "heart.circle"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch sync.state {
        case .idle:
            return .blue
        case .scanning, .connecting, .fetchingData:
            return .orange
        case .savingToHealth:
            return .red
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var statusColor: Color {
        switch sync.state {
        case .error:
            return .red
        case .success:
            return .green
        default:
            return .primary
        }
    }

    private var isAnimating: Bool {
        switch sync.state {
        case .scanning, .connecting, .fetchingData, .savingToHealth:
            return true
        default:
            return false
        }
    }

    private var isLoading: Bool {
        switch sync.state {
        case .scanning, .connecting, .fetchingData, .savingToHealth:
            return true
        default:
            return false
        }
    }

    private var buttonText: String {
        switch sync.state {
        case .idle, .error:
            return "Connect & Sync Workout"
        case .success:
            return "Sync Another Workout"
        default:
            return "Syncing..."
        }
    }

    private var buttonColor: Color {
        switch sync.state {
        case .error:
            return .red
        case .success:
            return .green
        default:
            return .blue
        }
    }

    // MARK: - Actions

    private func syncWorkout() {
        Task {
            // Request permission first if needed
            do {
                try await sync.requestHealthAuthorization()
                await sync.syncWorkout()
            } catch {
                showPermissionAlert = true
            }
        }
    }
}

// MARK: - Supporting Views

struct DataPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    SimpleMainView()
}
