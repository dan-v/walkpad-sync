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
        let url = URL(string: "\(config.baseURL)/api/health")!
        let (_, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Registration

    func registerDevice(name: String = "iPhone") async throws {
        let url = URL(string: "\(config.baseURL)/api/sync/register")!
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
        var components = URLComponents(string: "\(config.baseURL)/api/workouts/pending")!
        components.queryItems = [
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        let (data, response) = try await session.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        let result = try JSONDecoder().decode(PendingWorkoutsResponse.self, from: data)
        return result.workouts
    }

    // MARK: - Fetch Samples

    func fetchWorkoutSamples(workoutId: Int64) async throws -> [WorkoutSample] {
        let url = URL(string: "\(config.baseURL)/api/workouts/\(workoutId)/samples")!
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
        let url = URL(string: "\(config.baseURL)/api/workouts/\(workoutId)/confirm_sync")!
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
