import Foundation

actor APIClient {
    private let config: ServerConfig
    private let session: URLSession
    private let deviceID = UserDefaults.deviceID

    init(config: ServerConfig) {
        self.config = config

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Health Check

    func checkConnection() async throws -> Bool {
        guard let url = URL(string: "\(config.baseURL)/api/health") else {
            throw APIError.invalidURL
        }
        let (_, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Registration

    func registerDevice(name: String = "iPhone") async throws {
        guard let url = URL(string: "\(config.baseURL)/api/sync/register") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RegisterRequest(deviceId: deviceID, deviceName: name)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }
    }

    // MARK: - Fetch Workouts

    func fetchPendingWorkouts(limit: Int = 100) async throws -> [Workout] {
        guard var components = URLComponents(string: "\(config.baseURL)/api/workouts/pending") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        let result = try JSONDecoder().decode(PendingWorkoutsResponse.self, from: data)
        return result.workouts
    }

    // MARK: - Fetch Samples

    func fetchWorkoutSamples(workoutId: Int64) async throws -> [WorkoutSample] {
        guard let url = URL(string: "\(config.baseURL)/api/workouts/\(workoutId)/samples") else {
            throw APIError.invalidURL
        }
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        let result = try JSONDecoder().decode(SamplesResponse.self, from: data)
        return result.samples
    }

    // MARK: - Confirm Sync

    func confirmSync(workoutId: Int64, healthKitUUID: UUID? = nil) async throws {
        guard let url = URL(string: "\(config.baseURL)/api/workouts/\(workoutId)/confirm_sync") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ConfirmSyncRequest(
            deviceId: deviceID,
            healthkitUuid: healthKitUUID?.uuidString
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }
    }

    // MARK: - Delete Workout

    func deleteWorkout(workoutId: Int64) async throws {
        guard let url = URL(string: "\(config.baseURL)/api/workouts/\(workoutId)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }
    }

    // MARK: - Live Workout

    func fetchLiveWorkout() async throws -> LiveWorkoutResponse? {
        guard let url = URL(string: "\(config.baseURL)/api/debug/live") else {
            throw APIError.invalidURL
        }

        print("🔍 Fetching live workout from: \(url)")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError
        }

        print("📡 Response status: \(httpResponse.statusCode)")

        // Return nil if no workout in progress (204 No Content or empty response)
        if httpResponse.statusCode == 204 || data.isEmpty {
            print("ℹ️ No live workout (204 or empty)")
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        // Log the raw JSON for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📦 Raw JSON response:")
            print(jsonString)
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(LiveWorkoutResponse.self, from: data)

        print("✅ Successfully decoded live workout")
        print("  Workout ID: \(result.workout?.id ?? -1)")
        print("  Has metrics: \(result.currentMetrics != nil)")

        // Return nil if no workout in the response
        if result.workout == nil {
            print("⚠️ No workout in response")
            return nil
        }

        return result
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case serverError
    case decodingError
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .serverError:
            return "Server error occurred"
        case .decodingError:
            return "Failed to decode response"
        case .networkError:
            return "Network connection failed"
        }
    }
}
