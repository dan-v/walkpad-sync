//
//  SettingsView.swift
//  TreadmillSync
//
//  App settings and configuration
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var treadmillManager: TreadmillManager
    @State private var healthManager = HealthKitManager.shared
    @State private var showForgetConfirmation = false
    @State private var isRequestingHealthAccess = false

    var body: some View {
        NavigationStack {
            Form {
                // Treadmill Section
                Section {
                    HStack {
                        Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text(treadmillManager.connectionState.description)
                            .foregroundStyle(statusColor)
                    }

                    if let savedUUID = UserDefaults.standard.string(forKey: "savedPeripheralUUID") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Saved Device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(savedUUID)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Button(role: .destructive, action: {
                            showForgetConfirmation = true
                        }) {
                            Label("Forget Device", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Treadmill")
                } footer: {
                    Text("TreadmillSync automatically connects to your LifeSpan TR1200B treadmill when it's powered on.")
                }

                // HealthKit Section
                Section {
                    HStack {
                        Label("Authorization", systemImage: "heart.text.square")
                        Spacer()
                        if healthManager.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    Button(action: requestHealthAuthorization) {
                        if isRequestingHealthAccess {
                            HStack {
                                ProgressView()
                                Text("Requesting Access...")
                            }
                        } else {
                            Label("Grant Health Access", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRequestingHealthAccess)

                    Button(action: openHealthApp) {
                        Label("Open Health App", systemImage: "heart.text.square.fill")
                    }

                    Button(action: openDataSourceSettings) {
                        Label("Data Source Priority", systemImage: "list.number")
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("For best results, set TreadmillSync as your #1 data source for steps in the Health app to prevent duplicate counting.")
                }

                // App Information
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("iOS Version")
                        Spacer()
                        Text("iOS 18+")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/dan-v/lifespan-app")!) {
                        Label("GitHub Repository", systemImage: "link")
                    }
                } header: {
                    Text("About")
                }

                // Privacy Section
                Section {
                    HStack {
                        Label("Data Collection", systemImage: "eye.slash.fill")
                        Spacer()
                        Text("None")
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Label("Data Storage", systemImage: "internaldrive")
                        Spacer()
                        Text("On-device only")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("TreadmillSync does not collect any personal data. All workout data stays on your device and is only shared with Apple Health.")
                }

                // Advanced
                Section {
                    Button(action: resetApp) {
                        Label("Reset All Data", systemImage: "arrow.counterclockwise.circle")
                    }
                    .foregroundStyle(.red)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("This will clear all stored data and reset the app to initial state.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Forget Treadmill?",
                isPresented: $showForgetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Forget Device", role: .destructive) {
                    treadmillManager.forgetDevice()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the saved treadmill. You'll need to scan for it again on next use.")
            }
        }
    }

    private var statusColor: Color {
        switch treadmillManager.connectionState {
        case .connected:
            return .green
        case .connecting, .scanning:
            return .blue
        case .disconnected:
            return .secondary
        case .disconnectedBLEOff:
            return .orange
        case .error:
            return .red
        }
    }

    private func openHealthApp() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        }
    }

    private func openDataSourceSettings() {
        openHealthApp()
    }

    private func requestHealthAuthorization() {
        guard !isRequestingHealthAccess else { return }

        isRequestingHealthAccess = true

        Task {
            do {
                try await healthManager.requestAuthorization()
            } catch {
                print("Health authorization failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                isRequestingHealthAccess = false
            }
        }
    }

    private func resetApp() {
        // Clear all stored data
        treadmillManager.forgetDevice()
        DailySessionManager.shared.resetSession()
        UserDefaults.standard.removeObject(forKey: "dailySessionState")
        UserDefaults.standard.removeObject(forKey: "savedPeripheralUUID")
        print("🔄 App data reset")
    }
}

#Preview {
    SettingsView(treadmillManager: TreadmillManager())
}
