import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    // Server configuration
    @State private var serverHost = ""
    @State private var serverPort = "8080"
    @State private var useHTTPS = false

    // Connection test state
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    enum ConnectionTestResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // Page 1: Welcome
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.blue)
                    Text("Welcome to\nWalkPad Sync")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("Sync your LifeSpan walking pad data to Apple Health")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .tag(0)

                // Page 2: How it works
                VStack(spacing: 32) {
                    Spacer()
                    VStack(spacing: 24) {
                        OnboardingFeature(
                            icon: "server.rack",
                            title: "Set Up Server First",
                            description: "Run the Rust server on a Raspberry Pi near your treadmill"
                        )
                        OnboardingFeature(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "Automatic Capture",
                            description: "Server collects data via Bluetooth while you walk"
                        )
                        OnboardingFeature(
                            icon: "heart.fill",
                            title: "Sync to Health",
                            description: "App syncs steps, distance, and calories to Apple Health"
                        )
                    }
                    .padding(.horizontal)
                    Spacer()
                }
                .tag(1)

                // Page 3: Server Setup
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "network")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Connect to Server")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Enter your server's IP address")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Server configuration form
                    VStack(spacing: 16) {
                        HStack {
                            TextField("Server IP (e.g., 192.168.1.100)", text: $serverHost)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()

                            Text(":")
                                .foregroundColor(.secondary)

                            TextField("Port", text: $serverPort)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .frame(width: 70)
                        }

                        Toggle("Use HTTPS", isOn: $useHTTPS)
                            .tint(.blue)
                    }
                    .padding(.horizontal, 32)

                    // Connection test button and result
                    VStack(spacing: 12) {
                        Button {
                            testConnection()
                        } label: {
                            HStack {
                                if isTestingConnection {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "wifi")
                                }
                                Text(isTestingConnection ? "Testing..." : "Test Connection")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canTestConnection ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(!canTestConnection || isTestingConnection)
                        .padding(.horizontal, 32)

                        // Connection result
                        if let result = connectionTestResult {
                            HStack(spacing: 8) {
                                switch result {
                                case .success:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Connected successfully!")
                                        .foregroundColor(.green)
                                case .failure(let message):
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text(message)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer()
                }
                .tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Continue/Done button
            Button {
                if currentPage < 2 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    saveConfigAndFinish()
                }
            } label: {
                Text(buttonTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(buttonEnabled ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!buttonEnabled)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .interactiveDismissDisabled()
        .onAppear {
            // Load existing config if any
            let config = ServerConfig.load()
            if !config.host.isEmpty && config.host != "localhost" {
                serverHost = config.host
                serverPort = "\(config.port)"
                useHTTPS = config.useHTTPS
            }
        }
    }

    private var buttonTitle: String {
        switch currentPage {
        case 2:
            return connectionTestResult.isSuccess ? "Get Started" : "Test Connection First"
        default:
            return "Continue"
        }
    }

    private var buttonEnabled: Bool {
        switch currentPage {
        case 2:
            return connectionTestResult.isSuccess
        default:
            return true
        }
    }

    private var canTestConnection: Bool {
        !serverHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(serverPort) != nil
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        let trimmedHost = serverHost.trimmingCharacters(in: .whitespaces)
        guard let port = Int(serverPort) else {
            connectionTestResult = .failure("Invalid port number")
            isTestingConnection = false
            return
        }

        let config = ServerConfig(host: trimmedHost, port: port, useHTTPS: useHTTPS)
        let apiClient = APIClient(config: config)

        Task {
            do {
                let isConnected = try await apiClient.checkConnection()
                await MainActor.run {
                    if isConnected {
                        connectionTestResult = .success
                    } else {
                        connectionTestResult = .failure("Server not responding")
                    }
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = .failure(error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }

    private func saveConfigAndFinish() {
        let trimmedHost = serverHost.trimmingCharacters(in: .whitespaces)
        guard let port = Int(serverPort) else { return }

        let config = ServerConfig(host: trimmedHost, port: port, useHTTPS: useHTTPS)
        config.save()

        hasCompletedOnboarding = true
    }
}

extension OnboardingView.ConnectionTestResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

extension Optional where Wrapped == OnboardingView.ConnectionTestResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

struct OnboardingFeature: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.blue)
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
