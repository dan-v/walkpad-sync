import Foundation

actor APIClient {
    private let config: ServerConfig
    private let session: URLSession

    init(config: ServerConfig) {
        self.config = config

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
    }

    // Get current timezone offset in seconds (negative for timezones behind UTC)
    private var timezoneOffsetSeconds: Int {
        return TimeZone.current.secondsFromGMT()
    }

    // MARK: - Health Check

    func checkConnection() async throws -> Bool {
        guard let url = URL(string: "\(config.baseURL)/api/health") else {
            throw APIError.invalidURL
        }

        do {
            let (_, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return httpResponse.statusCode == 200
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    // MARK: - Activity Dates

    func fetchActivityDates() async throws -> [String] {
        guard var urlComponents = URLComponents(string: "\(config.baseURL)/api/dates") else {
            throw APIError.invalidURL
        }

        // Add timezone offset query parameter
        urlComponents.queryItems = [
            URLQueryItem(name: "tz_offset", value: "\(timezoneOffsetSeconds)")
        ]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.serverError(0)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError(httpResponse.statusCode)
            }

            let result = try JSONDecoder().decode(ActivityDatesResponse.self, from: data)
            return result.dates
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        } catch is DecodingError {
            throw APIError.decodingError
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }
    }

    // MARK: - Daily Summary

    func fetchDailySummary(date: String) async throws -> DailySummary {
        guard var urlComponents = URLComponents(string: "\(config.baseURL)/api/dates/\(date)/summary") else {
            throw APIError.invalidURL
        }

        // Add timezone offset query parameter
        urlComponents.queryItems = [
            URLQueryItem(name: "tz_offset", value: "\(timezoneOffsetSeconds)")
        ]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.serverError(0)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError(httpResponse.statusCode)
            }

            return try JSONDecoder().decode(DailySummary.self, from: data)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        } catch is DecodingError {
            throw APIError.decodingError
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }
    }

    // MARK: - Samples

    func fetchSamples(date: String) async throws -> [TreadmillSample] {
        guard var urlComponents = URLComponents(string: "\(config.baseURL)/api/dates/\(date)/samples") else {
            throw APIError.invalidURL
        }

        // Add timezone offset query parameter
        urlComponents.queryItems = [
            URLQueryItem(name: "tz_offset", value: "\(timezoneOffsetSeconds)")
        ]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.serverError(0)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError(httpResponse.statusCode)
            }

            let result = try JSONDecoder().decode(SamplesResponse.self, from: data)
            return result.samples
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        } catch is DecodingError {
            throw APIError.decodingError
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }
    }

}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case invalidURL
    case serverError(Int)
    case decodingError
    case connectionRefused
    case networkUnavailable
    case timeout
    case hostNotFound
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL. Check settings."
        case .serverError(let code):
            if code == 404 {
                return "Server endpoint not found (404)"
            } else if code >= 500 {
                return "Server error (\(code)). Is the server running?"
            } else {
                return "Server error (\(code))"
            }
        case .decodingError:
            return "Invalid response from server"
        case .connectionRefused:
            return "Connection refused. Is the server running?"
        case .networkUnavailable:
            return "No network connection"
        case .timeout:
            return "Connection timed out. Check server address."
        case .hostNotFound:
            return "Server not found. Check the IP address."
        case .unknown(let message):
            return message
        }
    }

    static func fromURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .networkConnectionLost:
            return .connectionRefused
        case .notConnectedToInternet:
            return .networkUnavailable
        case .cannotFindHost, .dnsLookupFailed:
            return .hostNotFound
        default:
            return .unknown(error.localizedDescription)
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
