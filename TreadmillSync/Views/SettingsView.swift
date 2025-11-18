import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) var dismiss

    @State private var host: String
    @State private var port: String
    @State private var useHTTPS: Bool
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    init() {
        let config = ServerConfig.load()
        _host = State(initialValue: config.host)
        _port = State(initialValue: String(config.port))
        _useHTTPS = State(initialValue: config.useHTTPS)
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("Example: raspberrypi.local or 192.168.1.100")
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
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func testConnection() {
        guard let portNum = Int(port) else {
            connectionTestResult = ConnectionTestResult(success: false, message: "Invalid port number")
            return
        }

        let testConfig = ServerConfig(host: host, port: portNum, useHTTPS: useHTTPS)
        let testClient = APIClient(config: testConfig)

        isTestingConnection = true
        connectionTestResult = nil

        Task {
            do {
                let success = try await testClient.checkConnection()
                connectionTestResult = ConnectionTestResult(
                    success: success,
                    message: success ? "Connected successfully" : "Connection failed"
                )
            } catch {
                connectionTestResult = ConnectionTestResult(
                    success: false,
                    message: "Error: \(error.localizedDescription)"
                )
            }
            isTestingConnection = false
        }
    }

    private func saveSettings() {
        guard let portNum = Int(port) else { return }

        let config = ServerConfig(host: host, port: portNum, useHTTPS: useHTTPS)

        Task {
            await syncManager.updateServerConfig(config)
            dismiss()
        }
    }
}

struct ConnectionTestResult {
    let success: Bool
    let message: String
}

#Preview {
    SettingsView()
        .environmentObject(SyncManager())
}
