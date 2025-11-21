import Foundation
import Combine

/// Manages WebSocket connection for real-time treadmill sample updates
actor WebSocketManager {
    private let config: ServerConfig
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var shouldReconnect = true

    // Publisher for connection status
    private let connectionStatusSubject = CurrentValueSubject<ConnectionStatus, Never>(.disconnected)
    var connectionStatusPublisher: AnyPublisher<ConnectionStatus, Never> {
        connectionStatusSubject.eraseToAnyPublisher()
    }

    // Publisher for new samples
    private let sampleSubject = PassthroughSubject<WebSocketSample, Never>()
    var samplePublisher: AnyPublisher<WebSocketSample, Never> {
        sampleSubject.eraseToAnyPublisher()
    }

    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    init(config: ServerConfig = .default) {
        self.config = config
    }

    // MARK: - Connection Management

    /// Connect to WebSocket server
    func connect() {
        guard webSocketTask == nil else {
            print("⚠️ WebSocket already connected or connecting")
            return
        }

        // Build WebSocket URL
        let wsURL: URL
        if config.baseURL.hasPrefix("http://") {
            wsURL = URL(string: config.baseURL.replacingOccurrences(of: "http://", with: "ws://") + "/ws/live")!
        } else if config.baseURL.hasPrefix("https://") {
            wsURL = URL(string: config.baseURL.replacingOccurrences(of: "https://", with: "wss://") + "/ws/live")!
        } else {
            wsURL = URL(string: "ws://\(config.baseURL)/ws/live")!
        }

        print("🔌 Connecting to WebSocket: \(wsURL.absoluteString)")
        connectionStatusSubject.send(.connecting)

        // Create WebSocket task
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()

        isConnected = true
        connectionStatusSubject.send(.connected)
        print("✅ WebSocket connected")

        // Start receiving messages
        Task {
            await receiveMessages()
        }
    }

    /// Disconnect from WebSocket server
    func disconnect() {
        shouldReconnect = false
        closeConnection()
    }

    private func closeConnection() {
        guard let task = webSocketTask else { return }

        print("🔌 Closing WebSocket connection")
        task.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        connectionStatusSubject.send(.disconnected)
    }

    // MARK: - Message Handling

    private func receiveMessages() async {
        guard let task = webSocketTask else { return }

        do {
            while isConnected {
                let message = try await task.receive()

                switch message {
                case .string(let text):
                    await handleMessage(text)

                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }

                @unknown default:
                    print("⚠️ Unknown WebSocket message type")
                }
            }
        } catch {
            print("❌ WebSocket receive error: \(error)")
            handleDisconnection(error: error)
        }
    }

    private func handleMessage(_ text: String) async {
        // Parse JSON message
        guard let data = text.data(using: .utf8) else {
            print("⚠️ Failed to convert message to data")
            return
        }

        do {
            let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)

            switch message {
            case .newSample(let sample):
                print("📨 Received new sample via WebSocket: steps=\(sample.stepsDelta ?? 0)")
                sampleSubject.send(sample)

            case .heartbeat:
                // Heartbeat - connection is alive
                break
            }
        } catch {
            print("⚠️ Failed to parse WebSocket message: \(error)")
        }
    }

    private func handleDisconnection(error: Error) {
        closeConnection()

        if shouldReconnect {
            print("🔄 Attempting to reconnect in 5 seconds...")
            connectionStatusSubject.send(.error("Disconnected, reconnecting..."))

            Task {
                try? await Task.sleep(for: .seconds(5))
                if shouldReconnect {
                    connect()
                }
            }
        }
    }
}

// MARK: - WebSocket Message Types

enum WebSocketMessage: Codable {
    case newSample(sample: WebSocketSample)
    case heartbeat

    enum CodingKeys: String, CodingKey {
        case type
        case sample
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "NewSample":
            let sample = try container.decode(WebSocketSample.self, forKey: .sample)
            self = .newSample(sample: sample)
        case "Heartbeat":
            self = .heartbeat
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .newSample(let sample):
            try container.encode("NewSample", forKey: .type)
            try container.encode(sample, forKey: .sample)
        case .heartbeat:
            try container.encode("Heartbeat", forKey: .type)
        }
    }
}

struct WebSocketSample: Codable {
    let timestamp: Int64
    let speed: Double?
    let distanceDelta: Int64?
    let caloriesDelta: Int64?
    let stepsDelta: Int64?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case speed
        case distanceDelta = "distance_delta"
        case caloriesDelta = "calories_delta"
        case stepsDelta = "steps_delta"
    }

    var timestampDate: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}
