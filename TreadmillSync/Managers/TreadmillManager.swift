//
//  TreadmillManager.swift
//  TreadmillSync
//
//  Enhanced BLE manager with comprehensive logging and reliability improvements
//

import CoreBluetooth
import Foundation
import Observation

/// Connection state for BLE treadmill
enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)

    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let message): return "Error: \(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Main BLE manager for LifeSpan TR1200B treadmill (DT3-BT console)
@Observable
@MainActor
class TreadmillManager: NSObject {

    // MARK: - Published State

    private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            guard connectionState != oldValue else { return }
            NotificationCenter.default.post(
                name: .treadmillConnectionStateDidChange,
                object: connectionState
            )
        }
    }

    private(set) var currentData: TreadmillData = TreadmillData() {
        didSet {
            guard currentData != oldValue else { return }
            NotificationCenter.default.post(
                name: .treadmillDataDidUpdate,
                object: currentData
            )
        }
    }

    private(set) var lastSyncTime: Date?

    // MARK: - BLE Constants

    private let serviceUUID = CBUUID(string: "0000fff0-0000-1000-8000-00805f9b34fb")
    private let characteristicUUID = CBUUID(string: "0000fff1-0000-1000-8000-00805f9b34fb")
    private let restoreIdentifier = "com.treadmillsync.centralManager"

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    private var pollTask: Task<Void, Never>?
    private var pendingQueries: [TreadmillQuery] = []

    // Enhanced parser with validation
    private let parser = BLEDataParser(enableDebugLogging: true)

    // Handshake command sequence
    private let handshakeCommands: [Data] = [
        Data([0x02, 0x00, 0x00, 0x00, 0x00]),
        Data([0xC2, 0x00, 0x00, 0x00, 0x00]),
        Data([0xE9, 0xFF, 0x00, 0x00, 0x00]),
        Data([0xE4, 0x00, 0xF4, 0x00, 0x00])
    ]

    // Persistence keys
    private let peripheralUUIDKey = "savedPeripheralUUID"

    // Delegate continuations for async/await
    private var stateContinuation: CheckedContinuation<Void, Never>?
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var characteristicContinuation: CheckedContinuation<CBCharacteristic, Error>?

    // MARK: - Initialization

    override init() {
        super.init()

        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier
        ]

        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: options
        )
    }

    // MARK: - Public Methods

    /// Start scanning for treadmill
    func startScanning() async {
        print("\n🔍 Starting treadmill scan...")

        switch centralManager.state {
        case .poweredOn:
            break
        case .poweredOff:
            connectionState = .error("Turn on Bluetooth to connect")
            print("❌ Bluetooth is powered off")
            await waitForPoweredOn()
            return await startScanning()
        case .resetting, .unknown:
            await waitForPoweredOn()
            return await startScanning()
        case .unauthorized:
            connectionState = .error("Bluetooth permission denied")
            print("❌ Bluetooth authorization missing")
            return
        case .unsupported:
            connectionState = .error("Bluetooth not supported on this device")
            print("❌ Bluetooth unsupported")
            return
        @unknown default:
            connectionState = .error("Bluetooth unavailable (\(centralManager.state.rawValue))")
            print("❌ Unexpected Bluetooth state: \(centralManager.state.rawValue)")
            return
        }

        // Try to retrieve cached peripheral first
        if let savedUUIDString = UserDefaults.standard.string(forKey: peripheralUUIDKey),
           let savedUUID = UUID(uuidString: savedUUIDString) {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [savedUUID])
            if let cachedPeripheral = peripherals.first {
                if !isLikelyTreadmill(name: cachedPeripheral.name) {
                    UserDefaults.standard.removeObject(forKey: peripheralUUIDKey)
                    print("⚠️ Cached peripheral name mismatch, clearing saved UUID")
                    return await startScanning()
                }

                print("✅ Found cached peripheral: \(cachedPeripheral.name ?? "Unknown")")
                await connect(to: cachedPeripheral)
                return
            }
        }

        // Fall back to scanning
        print("🔍 Scanning for LifeSpan treadmill...")
        connectionState = .scanning
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: options)
    }

    /// Forget the saved treadmill
    func forgetDevice() {
        print("🗑️ Forgetting saved treadmill")
        UserDefaults.standard.removeObject(forKey: peripheralUUIDKey)
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        targetCharacteristic = nil
        pendingQueries.removeAll()
        parser.reset()
        connectionState = .disconnected
    }

    // MARK: - Private Methods

    private func waitForPoweredOn() async {
        await withCheckedContinuation { continuation in
            stateContinuation = continuation
        }
    }

    private func connect(to peripheral: CBPeripheral) async {
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting

        do {
            print("🔌 Connecting to \(peripheral.name ?? "Unknown")...")
            centralManager.connect(peripheral, options: nil)
            try await withCheckedThrowingContinuation { continuation in
                connectionContinuation = continuation
            }
            print("✅ Connected to treadmill")
            await discoverServices()
        } catch {
            connectionState = .error("Connection failed: \(error.localizedDescription)")
            print("❌ Connection failed: \(error.localizedDescription)")
        }
    }

    private func discoverServices() async {
        guard let peripheral = peripheral else { return }

        do {
            print("🔍 Discovering services...")
            peripheral.discoverServices([serviceUUID])

            let characteristic = try await withCheckedThrowingContinuation { continuation in
                characteristicContinuation = continuation
            }

            targetCharacteristic = characteristic
            print("📡 Subscribing to notifications...")
            peripheral.setNotifyValue(true, for: characteristic)

            // Wait a moment for subscription to complete
            try await Task.sleep(for: .milliseconds(500))

            await sendHandshake()
        } catch {
            connectionState = .error("Service discovery failed: \(error.localizedDescription)")
            print("❌ Service discovery failed: \(error.localizedDescription)")
        }
    }

    private func sendHandshake() async {
        guard let peripheral = peripheral,
              let characteristic = targetCharacteristic else { return }

        print("\n🤝 Sending handshake sequence...")
        pendingQueries.removeAll()

        for (index, command) in handshakeCommands.enumerated() {
            peripheral.writeValue(command, for: characteristic, type: .withResponse)
            print("  ✓ Sent handshake command \(index + 1)/\(handshakeCommands.count)")

            // Small delay between commands
            try? await Task.sleep(for: .milliseconds(100))
        }

        print("✅ Handshake complete, starting data poll\n")
        connectionState = .connected
        startDataPoll()
    }

    private func startDataPoll() {
        // Cancel any existing poll task
        pollTask?.cancel()

        pollTask = Task { [weak self] in
            guard let self = self else { return }

            let queries: [TreadmillQuery] = [.steps, .distance, .calories, .speed, .time]
            let perQueryDelay: Duration = .milliseconds(300)

            defer { self.pendingQueries.removeAll() }

            while !Task.isCancelled {
                guard let peripheral = self.peripheral,
                      let characteristic = self.targetCharacteristic,
                      peripheral.state == .connected else {
                    break
                }

                for query in queries {
                    self.enqueue(query: query)
                    peripheral.writeValue(query.data, for: characteristic, type: .withResponse)
                    try? await Task.sleep(for: perQueryDelay)

                    if Task.isCancelled { break }
                }
            }
            print("⏹️ Stopped data polling task")
        }
    }

    private func enqueue(query: TreadmillQuery) {
        pendingQueries.append(query)

        // Prevent runaway queue if treadmill stops responding
        let maxPending = 10
        if pendingQueries.count > maxPending {
            pendingQueries.removeFirst(pendingQueries.count - maxPending)
        }
    }

    private func parseResponse(data: Data, for query: TreadmillQuery) {
        // Use enhanced parser
        guard let result = parser.parseResponse(data: data, for: query) else {
            return
        }

        // Update current data based on query type
        switch query {
        case .speed:
            if let speed = result as? Double {
                currentData.speed = speed
            }
        case .distance:
            if let distance = result as? Double {
                currentData.distance = distance
            }
        case .steps:
            if let steps = result as? Int {
                currentData.steps = steps
            }
        case .calories:
            if let calories = result as? Int {
                currentData.calories = calories
            }
        case .time:
            if let time = result as? TreadmillData.TimeComponents {
                currentData.time = time
            }
        }

        lastSyncTime = Date()
    }
}

// MARK: - CBCentralManagerDelegate

extension TreadmillManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            print("📶 Bluetooth state: \(central.state.rawValue)")

            switch central.state {
            case .poweredOn:
                stateContinuation?.resume()
                stateContinuation = nil
                if case .error = connectionState {
                    connectionState = .disconnected
                }
            case .poweredOff:
                connectionState = .error("Turn on Bluetooth to connect")
            case .unauthorized:
                connectionState = .error("Bluetooth permission denied")
                stateContinuation?.resume()
                stateContinuation = nil
            case .unsupported:
                connectionState = .error("Bluetooth unsupported")
                stateContinuation?.resume()
                stateContinuation = nil
            case .resetting:
                break
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didDiscover peripheral: CBPeripheral,
                                   advertisementData: [String: Any],
                                   rssi RSSI: NSNumber) {
        Task { @MainActor in
            print("📍 Discovered: \(peripheral.name ?? "Unknown") (RSSI: \(RSSI))")

            guard shouldConnect(to: peripheral, advertisementData: advertisementData) else {
                return
            }

            // Stop scanning once we find the treadmill
            central.stopScan()

            if isLikelyTreadmill(name: peripheral.name) ||
                isLikelyTreadmill(name: advertisementData[CBAdvertisementDataLocalNameKey] as? String) {
                UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: peripheralUUIDKey)
            }

            await connect(to: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionContinuation?.resume()
            connectionContinuation = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didFailToConnect peripheral: CBPeripheral,
                                   error: Error?) {
        Task { @MainActor in
            let err = error ?? NSError(domain: "TreadmillSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection failed"])
            connectionContinuation?.resume(throwing: err)
            connectionContinuation = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didDisconnectPeripheral peripheral: CBPeripheral,
                                   error: Error?) {
        Task { @MainActor in
            print("❌ Disconnected from treadmill")

            pollTask?.cancel()
            pollTask = nil
            pendingQueries.removeAll()

            connectionState = .disconnected

            // Automatically attempt to reconnect
            if let peripheral = self.peripheral {
                central.connect(peripheral, options: nil)
            } else {
                await startScanning()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   willRestoreState dict: [String: Any]) {
        Task { @MainActor in
            print("🔄 Restoring BLE state from iOS...")

            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                for peripheral in peripherals {
                    if peripheral.name?.contains("LifeSpan") ?? false {
                        print("✅ Restoring peripheral: \(peripheral.name ?? "Unknown")")

                        self.peripheral = peripheral
                        peripheral.delegate = self

                        if peripheral.state == .connected {
                            await discoverServices()
                        } else {
                            central.connect(peripheral, options: nil)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension TreadmillManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                              didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil,
                  let services = peripheral.services else {
                let err = error ?? NSError(domain: "TreadmillSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service discovery failed"])
                characteristicContinuation?.resume(throwing: err)
                characteristicContinuation = nil
                return
            }

            for service in services where service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([characteristicUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                              didDiscoverCharacteristicsFor service: CBService,
                              error: Error?) {
        Task { @MainActor in
            guard error == nil,
                  let characteristics = service.characteristics else {
                let err = error ?? NSError(domain: "TreadmillSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Characteristic discovery failed"])
                characteristicContinuation?.resume(throwing: err)
                characteristicContinuation = nil
                return
            }

            for characteristic in characteristics where characteristic.uuid == characteristicUUID {
                characteristicContinuation?.resume(returning: characteristic)
                characteristicContinuation = nil
                return
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                              didUpdateValueFor characteristic: CBCharacteristic,
                              error: Error?) {
        Task { @MainActor in
            guard error == nil,
                  let data = characteristic.value else { return }

            guard !pendingQueries.isEmpty else {
                print("⚠️ Received BLE data with no pending query")
                return
            }

            let query = pendingQueries.removeFirst()
            parseResponse(data: data, for: query)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                              didWriteValueFor characteristic: CBCharacteristic,
                              error: Error?) {
        if let error = error {
            Task { @MainActor in
                print("❌ Write error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Helpers

private extension TreadmillManager {
    func shouldConnect(to peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if isLikelyTreadmill(name: peripheral.name) {
            return true
        }

        if let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           isLikelyTreadmill(name: advName) {
            return true
        }

        if let savedUUIDString = UserDefaults.standard.string(forKey: peripheralUUIDKey),
           let savedUUID = UUID(uuidString: savedUUIDString),
           peripheral.identifier == savedUUID {
            return true
        }

        return false
    }

    func isLikelyTreadmill(name: String?) -> Bool {
        guard let lowercased = name?.lowercased() else { return false }
        let keywords = ["lifespan", "dt3", "tr1200", "treadmill"]
        return keywords.contains(where: { lowercased.contains($0) })
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let treadmillConnectionStateDidChange = Notification.Name("treadmillConnectionStateDidChange")
    static let treadmillDataDidUpdate = Notification.Name("treadmillDataDidUpdate")
}
