//
//  DailySessionManager.swift
//  TreadmillSync
//
//  Aggregates treadmill data into a single ongoing session until the user saves it
//  Optimized for all-day desk walking with multiple on/off cycles
//

import Foundation
import Observation

/// Represents an ongoing walking session for the day
struct DailySession: Codable, Equatable, Identifiable {
    var id: UUID
    var startDate: Date
    var lastUpdated: Date?
    var totalSteps: Int
    var totalDistanceMiles: Double
    var totalCalories: Int

    // Track activity segments for timeline view
    var activitySegments: [ActivitySegment] = []

    struct ActivitySegment: Codable, Equatable, Identifiable {
        let id: UUID
        let startTime: Date
        let endTime: Date
        let steps: Int
        let distanceMiles: Double
        let calories: Int
        let avgSpeed: Double?

        init(startTime: Date, endTime: Date, steps: Int, distanceMiles: Double, calories: Int, avgSpeed: Double? = nil) {
            self.id = UUID()
            self.startTime = startTime
            self.endTime = endTime
            self.steps = steps
            self.distanceMiles = distanceMiles
            self.calories = calories
            self.avgSpeed = avgSpeed
        }
    }

    static func newSession(start date: Date = Date()) -> DailySession {
        DailySession(
            id: UUID(),
            startDate: date,
            lastUpdated: nil,
            totalSteps: 0,
            totalDistanceMiles: 0,
            totalCalories: 0,
            activitySegments: []
        )
    }

    var formattedDuration: String {
        guard let end = lastUpdated else { return "--" }
        let interval = end.timeIntervalSince(startDate)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    var hasData: Bool {
        totalSteps > 0 || totalDistanceMiles > 0 || totalCalories > 0
    }
}

@Observable
@MainActor
final class DailySessionManager {

    static let shared = DailySessionManager()

    private(set) var currentSession: DailySession
    private var lastTreadmillData: TreadmillData?
    private var currentSegmentStart: Date?
    private var currentSegmentData: (steps: Int, distance: Double, calories: Int) = (0, 0.0, 0)

    private let storageKey = "dailySessionState"
    private let calendar = Calendar.current

    private struct PersistedState: Codable {
        var session: DailySession
        var lastSample: TreadmillData?
    }

    private init() {
        if let decoded = Self.loadState(forKey: storageKey),
           calendar.isDateInToday(decoded.session.startDate) {
            // Valid session from today
            currentSession = decoded.session
            lastTreadmillData = decoded.lastSample
            print("📂 Restored today's session: \(decoded.session.totalSteps) steps")
        } else {
            // No saved state or session is from a previous day
            currentSession = DailySession.newSession()
            lastTreadmillData = nil
            if let decoded = Self.loadState(forKey: storageKey) {
                print("⚠️ Discarded stale session from \(decoded.session.startDate)")
            }
        }
    }

    // MARK: - Public Methods

    func ingest(_ data: TreadmillData) {
        rolloverIfNeeded(for: Date())

        guard let previousSample = lastTreadmillData else {
            // Treat the first reading as baseline so we do not double count
            lastTreadmillData = data
            currentSegmentStart = Date()
            persistState()
            print("📊 Set baseline: steps=\(data.steps ?? 0), distance=\(data.distance ?? 0), calories=\(data.calories ?? 0)")
            return
        }

        var session = currentSession
        var didChange = false

        // Calculate deltas
        if let stepsDelta = delta(current: data.steps, previous: previousSample.steps),
           stepsDelta > 0 {
            session.totalSteps += stepsDelta
            currentSegmentData.steps += stepsDelta
            didChange = true
            print("  📈 Steps delta: +\(stepsDelta) (total: \(session.totalSteps))")
        }

        if let distanceDelta = delta(current: data.distance, previous: previousSample.distance),
           distanceDelta > 0 {
            session.totalDistanceMiles += distanceDelta
            currentSegmentData.distance += distanceDelta
            didChange = true
            print("  📈 Distance delta: +\(String(format: "%.2f", distanceDelta)) mi (total: \(String(format: "%.2f", session.totalDistanceMiles)) mi)")
        }

        if let calorieDelta = delta(current: data.calories, previous: previousSample.calories),
           calorieDelta > 0 {
            session.totalCalories += calorieDelta
            currentSegmentData.calories += calorieDelta
            didChange = true
            print("  📈 Calories delta: +\(calorieDelta) (total: \(session.totalCalories))")
        }

        if didChange {
            session.lastUpdated = Date()
            currentSession = session
        }

        lastTreadmillData = data
        persistState()
    }

    func startNewSegment() {
        currentSegmentStart = Date()
        currentSegmentData = (0, 0.0, 0)
        print("🆕 Started new activity segment")
    }

    func endCurrentSegment(avgSpeed: Double? = nil) {
        guard let startTime = currentSegmentStart,
              currentSegmentData.steps > 0 else {
            print("⚠️ No active segment to end")
            return
        }

        let segment = DailySession.ActivitySegment(
            startTime: startTime,
            endTime: Date(),
            steps: currentSegmentData.steps,
            distanceMiles: currentSegmentData.distance,
            calories: currentSegmentData.calories,
            avgSpeed: avgSpeed
        )

        currentSession.activitySegments.append(segment)
        currentSegmentStart = nil
        currentSegmentData = (0, 0.0, 0)

        print("✅ Ended segment: \(segment.steps) steps, \(String(format: "%.2f", segment.distanceMiles)) mi")
        persistState()
    }

    func resetSession(startingAt date: Date = Date(), reason: String? = nil) {
        currentSession = DailySession.newSession(start: date)
        lastTreadmillData = nil
        currentSegmentStart = nil
        currentSegmentData = (0, 0.0, 0)
        persistState()

        if let reason {
            print("🔄 Reset daily session (\(reason))")
        } else {
            print("🔄 Reset daily session")
        }
    }

    // MARK: - Private Methods

    private func persistState() {
        let state = PersistedState(session: currentSession, lastSample: lastTreadmillData)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func loadState(forKey key: String) -> PersistedState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func rolloverIfNeeded(for date: Date) {
        guard !calendar.isDate(currentSession.startDate, inSameDayAs: date) else { return }
        resetSession(startingAt: date, reason: "new day")
    }

    private func delta<T: Comparable & Numeric>(current: T?, previous: T?) -> T? {
        guard let current else { return nil }
        guard let previous else { return current }
        let change = current - previous

        // If change is negative, the treadmill likely reset - don't add anything
        if change < 0 {
            print("⚠️ Treadmill counter reset detected (previous: \(previous), current: \(current))")
            return 0
        }

        return change
    }
}

#if DEBUG
extension DailySessionManager {
    /// Inject synthetic data for testing
    func debugInjectSample(steps: Int, distanceMiles: Double, calories: Int) {
        var session = currentSession
        session.totalSteps += max(0, steps)
        session.totalDistanceMiles += max(0, distanceMiles)
        session.totalCalories += max(0, calories)
        session.lastUpdated = Date()
        currentSession = session
        print("🧪 Injected debug sample: +\(steps) steps")
        persistState()
    }
}
#endif
