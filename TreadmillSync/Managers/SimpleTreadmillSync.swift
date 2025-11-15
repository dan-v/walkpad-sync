//
//  SimpleTreadmillSync.swift
//  TreadmillSync
//
//  Simplified one-shot BLE connection to fetch steps and save to Health
//

import Foundation
import CoreBluetooth
import HealthKit
import Observation

@Observable
@MainActor
class SimpleTreadmillSync: NSObject {

    // MARK: - Singleton

    static let shared = SimpleTreadmillSync()

    // MARK: - Published State

    enum State {
        case idle
        case scanning
        case connecting
        case fetchingData
        case savingToHealth
        case success(String)
        case error(String)

        var description: String {
            switch self {
            case .idle: return "Ready"
            case .scanning: return "Scanning for treadmill..."
            case .connecting: return "Connecting..."
            case .fetchingData: return "Fetching workout data..."
            case .savingToHealth: return "Saving to Apple Health..."
            case .success(let msg): return msg
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var steps: Int = 0
    private(set) var distance: Double = 0.0  // miles
    private(set) var calories: Int = 0

    // MARK: - BLE Properties

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?

    private let serviceUUID = CBUUID(string: "0000fff0-0000-1000-8000-00805f9b34fb")
    private let characteristicUUID = CBUUID(string: "0000fff1-0000-1000-8000-00805f9b34fb")

    // MARK: - HealthKit

    private let healthStore = HKHealthStore()
    private var isHealthKitAuthorized = false

    // MARK: - Data Fetching State

    private var dataToFetch: [String] = ["steps", "distance", "calories"]
    private var currentFetchIndex = 0
    private var fetchedData: [String: Any] = [:]

    // MARK: - Initialization

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    /// Request HealthKit authorization
    func requestHealthAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "SimpleTreadmillSync", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "HealthKit not available"])
        }

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned)
        ]

        try await healthStore.requestAuthorization(toShare: typesToWrite, read: [])
        isHealthKitAuthorized = true
    }

    /// Connect to treadmill, fetch data, and save to Health
    func syncWorkout() async {
        guard centralManager.state == .poweredOn else {
            state = .error("Bluetooth is not powered on")
            return
        }

        guard isHealthKitAuthorized else {
            state = .error("HealthKit permission required")
            return
        }

        // Reset state
        steps = 0
        distance = 0.0
        calories = 0
        fetchedData.removeAll()
        currentFetchIndex = 0

        state = .scanning

        // Start scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        // Timeout after 10 seconds
        try? await Task.sleep(for: .seconds(10))

        if case .scanning = state {
            centralManager.stopScan()
            state = .error("Treadmill not found. Make sure it's powered on.")
        }
    }

    // MARK: - Private Helpers

    private func fetchNextData() {
        guard let peripheral = peripheral,
              let characteristic = targetCharacteristic else {
            return
        }

        guard currentFetchIndex < dataToFetch.count else {
            // All data fetched, save to Health
            Task { await saveToHealth() }
            return
        }

        let dataType = dataToFetch[currentFetchIndex]
        let command: Data

        switch dataType {
        case "steps":
            command = Data([0xA1, 0x88, 0x00, 0x00, 0x00])
        case "distance":
            command = Data([0xA1, 0x85, 0x00, 0x00, 0x00])
        case "calories":
            command = Data([0xA1, 0x87, 0x00, 0x00, 0x00])
        default:
            return
        }

        peripheral.writeValue(command, for: characteristic, type: .withResponse)
    }

    private func parseResponse(data: Data, forDataType dataType: String) {
        guard data.count >= 3 else { return }

        let bytes = [UInt8](data)

        switch dataType {
        case "steps":
            let lowByte = UInt16(bytes[1])
            let highByte = UInt16(bytes[2]) << 8
            steps = Int(highByte | lowByte)
            fetchedData["steps"] = steps

        case "distance":
            let integerPart = Double(bytes[1])
            let decimalPart = Double(bytes[2]) / 100.0
            distance = integerPart + decimalPart
            fetchedData["distance"] = distance

        case "calories":
            let lowByte = UInt16(bytes[1])
            let highByte = UInt16(bytes[2]) << 8
            calories = Int(highByte | lowByte)
            fetchedData["calories"] = calories

        default:
            break
        }

        currentFetchIndex += 1

        // Fetch next data point after a brief delay
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                fetchNextData()
            }
        }
    }

    private func saveToHealth() async {
        state = .savingToHealth

        // Use workout start time as "now minus 30 minutes" for a reasonable workout duration
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-30 * 60)  // 30 minutes ago

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore,
                                      configuration: configuration,
                                      device: .local())

        do {
            try await builder.beginCollection(at: startDate)

            var samples: [HKQuantitySample] = []

            // Add steps
            if steps > 0 {
                let stepType = HKQuantityType(.stepCount)
                let quantity = HKQuantity(unit: .count(), doubleValue: Double(steps))
                let sample = HKQuantitySample(type: stepType, quantity: quantity,
                                             start: startDate, end: endDate)
                samples.append(sample)
            }

            // Add distance
            if distance > 0 {
                let distType = HKQuantityType(.distanceWalkingRunning)
                let meters = distance * 1609.34  // Convert miles to meters
                let quantity = HKQuantity(unit: .meter(), doubleValue: meters)
                let sample = HKQuantitySample(type: distType, quantity: quantity,
                                             start: startDate, end: endDate)
                samples.append(sample)
            }

            // Add calories
            if calories > 0 {
                let calType = HKQuantityType(.activeEnergyBurned)
                let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(calories))
                let sample = HKQuantitySample(type: calType, quantity: quantity,
                                             start: startDate, end: endDate)
                samples.append(sample)
            }

            if !samples.isEmpty {
                try await builder.addSamples(samples)
            }

            try await builder.endCollection(at: endDate)
            _ = try await builder.finishWorkout()

            // Disconnect from treadmill
            if let peripheral = peripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }

            state = .success("Saved \(steps) steps to Apple Health!")

        } catch {
            state = .error("Failed to save: \(error.localizedDescription)")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension SimpleTreadmillSync: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Just log state changes
        print("Bluetooth state: \(central.state.rawValue)")
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didDiscover peripheral: CBPeripheral,
                                   advertisementData: [String : Any],
                                   rssi RSSI: NSNumber) {
        Task { @MainActor in
            // Look for LifeSpan treadmill
            if let name = peripheral.name, name.lowercased().contains("lifespan") {
                print("Found treadmill: \(name)")
                centralManager.stopScan()

                self.peripheral = peripheral
                peripheral.delegate = self

                state = .connecting
                centralManager.connect(peripheral, options: nil)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            print("Connected!")
            state = .fetchingData
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didFailToConnect peripheral: CBPeripheral,
                                   error: Error?) {
        Task { @MainActor in
            state = .error("Connection failed: \(error?.localizedDescription ?? "Unknown")")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension SimpleTreadmillSync: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                              didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }

            for service in services where service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([characteristicUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                              didDiscoverCharacteristicsFor service: CBService,
                              error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }

            for char in characteristics where char.uuid == characteristicUUID {
                targetCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                              didUpdateNotificationStateFor characteristic: CBCharacteristic,
                              error: Error?) {
        Task { @MainActor in
            if characteristic.isNotifying {
                print("Subscribed! Sending handshake...")

                // Send handshake sequence
                let handshake = [
                    Data([0x02, 0x00, 0x00, 0x00, 0x00]),
                    Data([0xC2, 0x00, 0x00, 0x00, 0x00]),
                    Data([0xE9, 0xFF, 0x00, 0x00, 0x00]),
                    Data([0xE4, 0x00, 0xF4, 0x00, 0x00])
                ]

                for cmd in handshake {
                    peripheral.writeValue(cmd, for: characteristic, type: .withResponse)
                }

                // Wait a bit for handshake to complete
                try? await Task.sleep(for: .milliseconds(500))

                // Start fetching data
                fetchNextData()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                              didUpdateValueFor characteristic: CBCharacteristic,
                              error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value else { return }

            let dataType = dataToFetch[currentFetchIndex]
            parseResponse(data: data, forDataType: dataType)
        }
    }
}
