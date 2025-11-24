import SwiftUI

struct SettingsView: View {
    @State private var host: String
    @State private var port: String
    @State private var useHTTPS: Bool
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @AppStorage(UnitPreference.storageKey) private var unitPreferenceRaw: String = UnitPreference.imperial.rawValue

    private var unitPreference: UnitPreference {
        UnitPreference(rawValue: unitPreferenceRaw) ?? .imperial
    }

    init() {
        let config = ServerConfig.load()
        _host = State(initialValue: config.host)
        _port = State(initialValue: String(config.port))
        _useHTTPS = State(initialValue: config.useHTTPS)
    }

    private var hasUnsavedChanges: Bool {
        let saved = ServerConfig.load()
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let currentPort = Int(port) ?? 0

        return trimmedHost != saved.host ||
               currentPort != saved.port ||
               useHTTPS != saved.useHTTPS
    }

    var body: some View {
        NavigationStack {
            Form {
                // Unsaved changes warning
                if hasUnsavedChanges {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("You have unsaved changes")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Server Configuration
                Section {
                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Toggle("Use HTTPS", isOn: $useHTTPS)
                } header: {
                    Text("Server Configuration")
                } footer: {
                    Text("Changes apply after successful connection test. Example: myserver.local or 192.168.1.100")
                }

                // Test Connection
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                            Text("Test & Apply")
                        }
                    }
                    .disabled(isTestingConnection)

                    if let result = connectionTestResult {
                        HStack {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.success ? .green : .red)
                            Text(result.message)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Units
                Section {
                    Picker("Units", selection: $unitPreferenceRaw) {
                        Text("Imperial (mi, mph)").tag(UnitPreference.imperial.rawValue)
                        Text("Metric (km, km/h)").tag(UnitPreference.metric.rawValue)
                    }
                } header: {
                    Text("Display Units")
                } footer: {
                    Text("Choose how to display distance and speed")
                }

                // Device Info
                Section("Device Information") {
                    LabeledContent("Device ID", value: UserDefaults.deviceID)
                        .font(.caption)
                }

                // About
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Reset to saved config when appearing
            // This discards any unsaved changes from previous visits
            resetToSavedConfig()
        }
    }

    private func resetToSavedConfig() {
        let config = ServerConfig.load()
        host = config.host
        port = String(config.port)
        useHTTPS = config.useHTTPS
        connectionTestResult = nil
    }

    private func testConnection() {
        // Validate inputs
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else {
            connectionTestResult = ConnectionTestResult(success: false, message: "Host cannot be empty")
            return
        }

        guard let portNum = Int(port), portNum > 0, portNum <= 65535 else {
            connectionTestResult = ConnectionTestResult(success: false, message: "Invalid port number")
            return
        }

        let testConfig = ServerConfig(host: trimmedHost, port: portNum, useHTTPS: useHTTPS)
        let testClient = APIClient(config: testConfig)

        isTestingConnection = true
        connectionTestResult = nil

        Task {
            do {
                let success = try await testClient.checkConnection()

                if success {
                    // Save config and notify views to reload
                    testConfig.saveAndNotify()
                    connectionTestResult = ConnectionTestResult(
                        success: true,
                        message: "Connected successfully"
                    )
                } else {
                    connectionTestResult = ConnectionTestResult(
                        success: false,
                        message: "Connection failed - settings not saved"
                    )
                }
            } catch {
                connectionTestResult = ConnectionTestResult(
                    success: false,
                    message: "Error: \(error.localizedDescription)"
                )
            }
            isTestingConnection = false
        }
    }
}

struct ConnectionTestResult {
    let success: Bool
    let message: String
}

#Preview {
    SettingsView()
}
