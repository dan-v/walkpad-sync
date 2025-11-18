//
//  WorkoutCoordinator.swift
//  TreadmillSync
//
//  Coordinates BLE treadmill data with session tracking and HealthKit
//  Optimized for all-day desk walking with smart auto-detection
//

import Foundation
import Observation
import UIKit

/// Coordinates workout flow between TreadmillManager, DailySessionManager, and HealthKitManager
@Observable
@MainActor
class WorkoutCoordinator {

    // MARK: - Singleton

    static let shared = WorkoutCoordinator()

    // MARK: - Managers

    let treadmillManager: TreadmillManager
    let healthKitManager: HealthKitManager
    let sessionManager: DailySessionManager

    // MARK: - Published State

    private(set) var isAutoCollecting = false
    private(set) var lastDataUpdate: Date?

    // MARK: - Private Properties

    private var connectionObserver: Task<Void, Never>?
    private var dataObserver: Task<Void, Never>?
    private var wasConnected = false

    // Smart detection
    private var lastSpeed: Double = 0
    private var lastActivityTime: Date?
    private var pauseCheckTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        treadmillManager: TreadmillManager,
        healthKitManager: HealthKitManager,
        sessionManager: DailySessionManager
    ) {
        self.treadmillManager = treadmillManager
        self.healthKitManager = healthKitManager
        self.sessionManager = sessionManager
        setupObservers()
    }

    convenience init() {
        self.init(
            treadmillManager: TreadmillManager(),
            healthKitManager: .shared,
            sessionManager: .shared
        )
    }

    // MARK: - Public Methods

    func start() async {
        print("\n🚀 Starting TreadmillSync coordinator...")
        await treadmillManager.startScanning()
    }

    func saveWorkout() async throws {
        guard sessionManager.currentSession.hasData else {
            throw NSError(domain: "WorkoutCoordinator", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "No workout data to save"])
        }

        print("\n💾 Saving workout...")
        try await healthKitManager.saveDailyWorkout(from: sessionManager.currentSession)
        sessionManager.resetSession()
        print("✅ Workout saved and session reset")
    }

    // MARK: - Private Methods

    private func setupObservers() {
        let center = NotificationCenter.default

        // Observe connection state changes
        connectionObserver = Task { [weak self] in
            guard let self = self else { return }

            await self.handleConnectionStateChange(self.treadmillManager.connectionState)

            for await notification in center.notifications(named: .treadmillConnectionStateDidChange) {
                guard let state = notification.object as? ConnectionState else { continue }
                await self.handleConnectionStateChange(state)
            }
        }

        // Observe data updates
        dataObserver = Task { [weak self] in
            guard let self = self else { return }

            for await notification in center.notifications(named: .treadmillDataDidUpdate) {
                guard let data = notification.object as? TreadmillData else { continue }
                await self.handleDataUpdate(data)
            }
        }
    }

    private func handleConnectionStateChange(_ state: ConnectionState) async {
        let isConnected = state.isConnected

        if isConnected && !wasConnected {
            print("✅ Treadmill connected")
            triggerHaptic(.success)
            wasConnected = true
            isAutoCollecting = true
            sessionManager.startNewSegment()
            lastActivityTime = Date()
            startPauseDetection()
        } else if !isConnected && wasConnected {
            print("❌ Treadmill disconnected")
            triggerHaptic(.warning)
            wasConnected = false
            isAutoCollecting = false
            lastDataUpdate = nil
            lastSpeed = 0

            // End the current segment when disconnected
            sessionManager.endCurrentSegment(avgSpeed: nil)
            pauseCheckTask?.cancel()
        }

        if case .error(let message) = state {
            print("⚠️ Connection error: \(message)")
        }
    }

    private func handleDataUpdate(_ data: TreadmillData) async {
        guard treadmillManager.connectionState.isConnected else { return }

        // Ingest data into session
        sessionManager.ingest(data)
        lastDataUpdate = Date()

        // Track speed for auto-pause detection
        if let speed = data.speed {
            lastSpeed = speed

            // If moving, update last activity time
            if speed > 0.3 {
                lastActivityTime = Date()
            }
        }
    }

    private func startPauseDetection() {
        pauseCheckTask?.cancel()

        pauseCheckTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))

                guard let lastActivity = self.lastActivityTime else { continue }

                // If no activity for 5+ minutes, consider ending the segment
                let timeSinceActivity = Date().timeIntervalSince(lastActivity)
                if timeSinceActivity > 300 && self.lastSpeed < 0.3 {
                    print("⏸️ Auto-pause detected (no activity for \(Int(timeSinceActivity/60)) min)")
                    self.sessionManager.endCurrentSegment(avgSpeed: self.lastSpeed)
                    break
                }
            }
        }
    }

    private func triggerHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}
