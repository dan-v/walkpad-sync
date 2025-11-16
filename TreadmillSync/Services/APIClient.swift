import Foundation

actor APIClient {
    private let config: ServerConfig
    private let session: URLSession

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

    // MARK: - Activity Dates

    func fetchActivityDates() async throws -> [String] {
        guard let url = URL(string: "\(config.baseURL)/api/dates") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        let result = try JSONDecoder().decode(ActivityDatesResponse.self, from: data)
        return result.dates
    }

    // MARK: - Daily Summary

    func fetchDailySummary(date: String) async throws -> DailySummary {
        guard let url = URL(string: "\(config.baseURL)/api/dates/\(date)/summary") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        return try JSONDecoder().decode(DailySummary.self, from: data)
    }

    // MARK: - Samples

    func fetchSamples(date: String) async throws -> [TreadmillSample] {
        guard let url = URL(string: "\(config.baseURL)/api/dates/\(date)/samples") else {
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

    // MARK: - Mark as Synced

    func markDateSynced(date: String) async throws {
        guard let url = URL(string: "\(config.baseURL)/api/dates/\(date)/sync") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }
    }

    // MARK: - Get Synced Dates

    func fetchSyncedDates() async throws -> [HealthSync] {
        guard let url = URL(string: "\(config.baseURL)/api/dates/synced") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        let result = try JSONDecoder().decode(SyncedDatesResponse.self, from: data)
        return result.syncedDates
    }
}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case invalidURL
    case serverError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .serverError:
            return "Server error occurred"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    static var deviceID: String {
        let key = "deviceID"
        if let id = standard.string(forKey: key) {
            return id
        }
        let id = UUID().uuidString
        standard.set(id, forKey: key)
        return id
    }
}
