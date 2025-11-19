import Foundation
import Combine

// MARK: - Workout Event Models

enum WorkoutEvent: Codable {
    case workoutStarted(workout: Workout)
    case workoutSample(workoutId: Int64, sample: WorkoutSample)
    case workoutCompleted(workout: Workout)
    case workoutFailed(workoutId: Int64, reason: String)
    case connectionStatus(connected: Bool)

    enum CodingKeys: String, CodingKey {
        case type
        case workout
        case workoutId = "workout_id"
        case sample
        case reason
        case connected
    }

    enum EventType: String, Codable {
        case workoutStarted = "workout_started"
        case workoutSample = "workout_sample"
        case workoutCompleted = "workout_completed"
        case workoutFailed = "workout_failed"
        case connectionStatus = "connection_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)

        switch type {
        case .workoutStarted:
            let workout = try container.decode(Workout.self, forKey: .workout)
            self = .workoutStarted(workout: workout)
        case .workoutSample:
            let workoutId = try container.decode(Int64.self, forKey: .workoutId)
            let sample = try container.decode(WorkoutSample.self, forKey: .sample)
            self = .workoutSample(workoutId: workoutId, sample: sample)
        case .workoutCompleted:
            let workout = try container.decode(Workout.self, forKey: .workout)
            self = .workoutCompleted(workout: workout)
        case .workoutFailed:
            let workoutId = try container.decode(Int64.self, forKey: .workoutId)
            let reason = try container.decode(String.self, forKey: .reason)
            self = .workoutFailed(workoutId: workoutId, reason: reason)
        case .connectionStatus:
            let connected = try container.decode(Bool.self, forKey: .connected)
            self = .connectionStatus(connected: connected)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .workoutStarted(let workout):
            try container.encode(EventType.workoutStarted, forKey: .type)
            try container.encode(workout, forKey: .workout)
        case .workoutSample(let workoutId, let sample):
            try container.encode(EventType.workoutSample, forKey: .type)
            try container.encode(workoutId, forKey: .workoutId)
            try container.encode(sample, forKey: .sample)
        case .workoutCompleted(let workout):
            try container.encode(EventType.workoutCompleted, forKey: .type)
            try container.encode(workout, forKey: .workout)
        case .workoutFailed(let workoutId, let reason):
            try container.encode(EventType.workoutFailed, forKey: .type)
            try container.encode(workoutId, forKey: .workoutId)
            try container.encode(reason, forKey: .reason)
        case .connectionStatus(let connected):
            try container.encode(EventType.connectionStatus, forKey: .type)
            try container.encode(connected, forKey: .connected)
        }
    }
}

// MARK: - WebSocket Manager

@MainActor
class WebSocketManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var currentLiveWorkout: Workout?

    private var webSocketTask: URLSessionWebSocketTask?
    private let serverConfig: ServerConfig
    private var reconnectTimer: Task<Void, Never>?
    private var isActive: Bool = false

    // Event publisher for other components to subscribe to
    let eventPublisher = PassthroughSubject<WorkoutEvent, Never>()

    init(serverConfig: ServerConfig) {
        self.serverConfig = serverConfig
    }

    // MARK: - Connection Management

    func connect() {
        guard !isActive else { return }
        isActive = true

        connectWebSocket()
    }

    func disconnect() {
        isActive = false
        reconnectTimer?.cancel()
        reconnectTimer = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func connectWebSocket() {
        guard isActive else {
            print("⚠️ WebSocket connect called but not active")
            return
        }

        // Build WebSocket URL
        guard let url = buildWebSocketURL() else {
            print("❌ Invalid WebSocket URL")
            scheduleReconnect()
            return
        }

        print("🔌 Connecting to WebSocket: \(url)")

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        print("✅ WebSocket connection initiated")

        // Start receiving messages
        receiveMessage()

        // Send ping every 30 seconds to keep connection alive
        sendPeriodicPing()
    }

    private func buildWebSocketURL() -> URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = serverConfig.host
        components.port = Int(serverConfig.port)
        components.path = "/ws/live"

        return components.url
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                Task { @MainActor in
                    await self.handleMessage(message)
                    // Continue receiving
                    self.receiveMessage()
                }

            case .failure(let error):
                Task { @MainActor in
                    print("WebSocket receive error: \(error)")
                    self.handleDisconnection()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            print("📨 Received WebSocket string message: \(text)")
            // Decode JSON event
            guard let data = text.data(using: .utf8) else {
                print("❌ Failed to convert message to data")
                return
            }

            do {
                let event = try JSONDecoder().decode(WorkoutEvent.self, from: data)
                await handleEvent(event)
            } catch {
                print("❌ Failed to decode WebSocket event: \(error)")
                print("   Raw message: \(text)")
            }

        case .data(let data):
            print("📨 Received WebSocket binary message (\(data.count) bytes)")
            do {
                let event = try JSONDecoder().decode(WorkoutEvent.self, from: data)
                await handleEvent(event)
            } catch {
                print("❌ Failed to decode WebSocket event: \(error)")
            }

        @unknown default:
            print("⚠️ Unknown WebSocket message type")
        }
    }

    private func handleEvent(_ event: WorkoutEvent) async {
        print("📡 Received WebSocket event: \(event)")

        // Update local state
        switch event {
        case .workoutStarted(let workout):
            print("🏃 WorkoutStarted event - Setting currentLiveWorkout to \(workout.id)")
            currentLiveWorkout = workout
            print("  Current live workout is now: \(currentLiveWorkout?.id ?? -1)")

        case .workoutSample(_, _):
            // Sample updates - just forward to subscribers
            break

        case .workoutCompleted(let workout):
            // Workout completed - clear live workout if it matches
            print("✅ WorkoutCompleted event for workout \(workout.id)")
            if currentLiveWorkout?.id == workout.id {
                print("  Clearing currentLiveWorkout")
                currentLiveWorkout = nil
            }

        case .workoutFailed(let workoutId, _):
            // Workout failed - clear live workout if it matches
            print("❌ WorkoutFailed event for workout \(workoutId)")
            if currentLiveWorkout?.id == workoutId {
                print("  Clearing currentLiveWorkout")
                currentLiveWorkout = nil
            }

        case .connectionStatus(let connected):
            print("📊 Server connection status: \(connected ? "connected" : "disconnected")")
        }

        // Publish event to subscribers
        eventPublisher.send(event)
    }

    // MARK: - Connection Maintenance

    private func sendPeriodicPing() {
        Task {
            while isConnected && isActive {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    webSocketTask?.sendPing { error in
                        if let error = error {
                            print("Ping failed: \(error)")
                        }
                    }
                } catch {
                    break
                }
            }
        }
    }

    private func handleDisconnection() {
        isConnected = false
        currentLiveWorkout = nil
        webSocketTask = nil

        // Attempt reconnection if still active
        if isActive {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard isActive else { return }

        reconnectTimer?.cancel()
        reconnectTimer = Task {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if !Task.isCancelled && isActive {
                    print("Attempting to reconnect WebSocket...")
                    connectWebSocket()
                }
            } catch {
                // Task cancelled
            }
        }
    }
}
