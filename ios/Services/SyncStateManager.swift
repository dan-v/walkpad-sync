import Foundation

/// Manages local sync state for Apple Health workouts
/// Tracks which dates have been synced and detects when re-sync is needed
class SyncStateManager {
    static let shared = SyncStateManager()

    private let defaults = UserDefaults.standard
    private let syncStateKey = "treadmill_sync_state"
    private let lock = NSLock()

    private init() {}

    // MARK: - Sync State

    struct SyncState: Codable {
        let date: String          // YYYY-MM-DD
        let syncedAt: Date        // When it was synced
        let steps: Int64          // Steps at time of sync
        let distanceMeters: Int64 // Distance at time of sync
        let calories: Int64       // Calories at time of sync
    }

    // MARK: - Public Methods

    /// Mark a date as synced with the current summary data
    func markAsSynced(summary: DailySummary) {
        lock.lock()
        defer { lock.unlock() }

        var states = getAllSyncStates()

        let newState = SyncState(
            date: summary.date,
            syncedAt: Date(),
            steps: summary.steps,
            distanceMeters: summary.distanceMeters,
            calories: summary.calories
        )

        // Update or add the sync state for this date
        states[summary.date] = newState
        saveSyncStates(states)
    }

    /// Get sync info for a specific date
    func getSyncState(for date: String) -> SyncState? {
        let states = getAllSyncStates()
        return states[date]
    }

    /// Check if a date has been synced
    func isSynced(_ date: String) -> Bool {
        return getSyncState(for: date) != nil
    }

    /// Check if a date should be re-synced based on current summary
    /// Returns true if:
    /// - Never synced before
    /// - Steps/distance/calories have increased since last sync
    func shouldResync(summary: DailySummary) -> Bool {
        guard let syncState = getSyncState(for: summary.date) else {
            // Never synced before
            return true
        }

        // Check if any metrics have increased
        let hasNewData = summary.steps > syncState.steps ||
                        summary.distanceMeters > syncState.distanceMeters ||
                        summary.calories > syncState.calories

        return hasNewData
    }

    /// Get formatted sync time for display
    func getSyncedAtFormatted(for date: String) -> String? {
        guard let syncState = getSyncState(for: date) else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Synced " + formatter.localizedString(for: syncState.syncedAt, relativeTo: Date())
    }

    /// Get short sync time for display
    func getSyncedAtShort(for date: String) -> String? {
        guard let syncState = getSyncState(for: date) else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: syncState.syncedAt, relativeTo: Date())
    }

    /// Get all synced dates
    func getAllSyncedDates() -> [String] {
        return Array(getAllSyncStates().keys).sorted(by: >)
    }

    /// Clear sync state for a specific date (useful if user wants to force re-sync)
    func clearSyncState(for date: String) {
        lock.lock()
        defer { lock.unlock() }

        var states = getAllSyncStates()
        states.removeValue(forKey: date)
        saveSyncStates(states)
    }

    /// Clear all sync states (useful for debugging/reset)
    func clearAllSyncStates() {
        lock.lock()
        defer { lock.unlock() }

        defaults.removeObject(forKey: syncStateKey)
    }

    // MARK: - Private Methods

    private func getAllSyncStates() -> [String: SyncState] {
        guard let data = defaults.data(forKey: syncStateKey) else {
            return [:]
        }

        guard let states = try? JSONDecoder().decode([String: SyncState].self, from: data) else {
            return [:]
        }

        return states
    }

    private func saveSyncStates(_ states: [String: SyncState]) {
        guard let data = try? JSONEncoder().encode(states) else {
            print("❌ Failed to encode sync states")
            return
        }

        defaults.set(data, forKey: syncStateKey)
    }
}
