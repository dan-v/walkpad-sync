//
//  BLEDataParser.swift
//  TreadmillSync
//
//  Enhanced BLE data parser with validation and comprehensive logging
//

import Foundation

/// Represents a query command for the DT3-BT treadmill console
enum TreadmillQuery: String, CaseIterable {
    case steps
    case distance
    case calories
    case speed
    case time

    var commandBytes: [UInt8] {
        switch self {
        case .steps:    return [0xA1, 0x88, 0x00, 0x00, 0x00]
        case .calories: return [0xA1, 0x87, 0x00, 0x00, 0x00]
        case .distance: return [0xA1, 0x85, 0x00, 0x00, 0x00]
        case .time:     return [0xA1, 0x89, 0x00, 0x00, 0x00]
        case .speed:    return [0xA1, 0x82, 0x00, 0x00, 0x00]
        }
    }

    var data: Data {
        Data(commandBytes)
    }
}

/// Parsed data from treadmill
struct TreadmillData: Equatable, Codable {
    var speed: Double?           // mph
    var distance: Double?        // miles
    var steps: Int?              // step count
    var calories: Int?           // calories burned
    var time: TimeComponents?    // workout duration

    struct TimeComponents: Equatable, Codable {
        let hours: Int
        let minutes: Int
        let seconds: Int

        var totalSeconds: Int {
            hours * 3600 + minutes * 60 + seconds
        }

        var formatted: String {
            String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }
}

/// Enhanced BLE data parser with validation and logging
class BLEDataParser {

    // MARK: - Properties

    private var lastValidValues: [TreadmillQuery: Any] = [:]
    private let enableDebugLogging: Bool

    // MARK: - Initialization

    init(enableDebugLogging: Bool = true) {
        self.enableDebugLogging = enableDebugLogging
    }

    // MARK: - Parsing

    func parseResponse(data: Data, for query: TreadmillQuery) -> Any? {
        // Log raw data
        if enableDebugLogging {
            logRawData(data, for: query)
        }

        // Validate minimum length
        guard data.count >= 3 else {
            logError("Data too short: \(data.count) bytes (need at least 3)", for: query)
            return lastValidValues[query]
        }

        let bytes = [UInt8](data)

        // Parse based on query type
        let result: Any?

        switch query {
        case .speed:
            result = parseSpeed(bytes: bytes)
        case .distance:
            result = parseDistance(bytes: bytes)
        case .steps:
            result = parseSteps(bytes: bytes)
        case .calories:
            result = parseCalories(bytes: bytes)
        case .time:
            result = parseTime(bytes: bytes)
        }

        // Store valid result
        if let result = result {
            lastValidValues[query] = result
            if enableDebugLogging {
                logSuccess("\(result)", for: query)
            }
        }

        return result
    }

    // MARK: - Individual Parsers

    private func parseSpeed(bytes: [UInt8]) -> Double? {
        // Speed format: byte[1] = integer part, byte[2] = decimal part (x/100)
        let integerPart = Double(bytes[1])
        let decimalPart = Double(bytes[2]) / 100.0
        let speed = integerPart + decimalPart

        // Validate range (0-10 mph for walking)
        guard speed >= 0 && speed <= 10 else {
            logError("Speed out of range: \(speed) mph", for: .speed)
            return lastValidValues[.speed] as? Double
        }

        // Check for suspicious jumps
        if let lastSpeed = lastValidValues[.speed] as? Double {
            let change = abs(speed - lastSpeed)
            if change > 3.0 {
                logWarning("Large speed change: \(lastSpeed) → \(speed) mph", for: .speed)
            }
        }

        return speed
    }

    private func parseDistance(bytes: [UInt8]) -> Double? {
        // Distance format: byte[1] = integer part, byte[2] = decimal part (x/100)
        let integerPart = Double(bytes[1])
        let decimalPart = Double(bytes[2]) / 100.0
        let distance = integerPart + decimalPart

        // Log both parsing methods for debugging
        if enableDebugLogging {
            let method1 = integerPart + decimalPart
            let method2 = Double(bytes[2]) + (Double(bytes[1]) / 100.0)
            print("  📊 Distance parsing:")
            print("     Method 1 (bytes[1] + bytes[2]/100): \(method1)")
            print("     Method 2 (bytes[2] + bytes[1]/100): \(method2)")
        }

        // Validate range (0-50 miles is reasonable for a day)
        guard distance >= 0 && distance <= 50 else {
            logError("Distance out of range: \(distance) miles", for: .distance)
            return lastValidValues[.distance] as? Double
        }

        // Distance should only increase or stay same
        if let lastDistance = lastValidValues[.distance] as? Double {
            if distance < lastDistance - 0.01 { // Allow small floating point errors
                logWarning("Distance decreased: \(lastDistance) → \(distance) miles", for: .distance)
            }
        }

        return distance
    }

    private func parseSteps(bytes: [UInt8]) -> Int? {
        // Steps format: 16-bit integer, little-endian
        let lowByte = UInt16(bytes[1])
        let highByte = UInt16(bytes[2]) << 8
        let steps = Int(highByte | lowByte)

        // Try both byte orders for debugging
        if enableDebugLogging {
            let littleEndian = Int((UInt16(bytes[2]) << 8) | UInt16(bytes[1]))
            let bigEndian = Int((UInt16(bytes[1]) << 8) | UInt16(bytes[2]))
            print("  📊 Steps parsing:")
            print("     Little-endian (bytes[2] << 8 | bytes[1]): \(littleEndian)")
            print("     Big-endian (bytes[1] << 8 | bytes[2]): \(bigEndian)")
        }

        // Validate range (0-50000 steps is reasonable for a day)
        guard steps >= 0 && steps <= 50000 else {
            logError("Steps out of range: \(steps)", for: .steps)
            return lastValidValues[.steps] as? Int
        }

        // Steps should only increase or stay same
        if let lastSteps = lastValidValues[.steps] as? Int {
            if steps < lastSteps {
                logWarning("Steps decreased: \(lastSteps) → \(steps) (treadmill reset?)", for: .steps)
            }
        }

        return steps
    }

    private func parseCalories(bytes: [UInt8]) -> Int? {
        // Calories format: 16-bit integer, little-endian
        let lowByte = UInt16(bytes[1])
        let highByte = UInt16(bytes[2]) << 8
        let calories = Int(highByte | lowByte)

        // Try both byte orders for debugging
        if enableDebugLogging {
            let littleEndian = Int((UInt16(bytes[2]) << 8) | UInt16(bytes[1]))
            let bigEndian = Int((UInt16(bytes[1]) << 8) | UInt16(bytes[2]))
            print("  📊 Calories parsing:")
            print("     Little-endian (bytes[2] << 8 | bytes[1]): \(littleEndian)")
            print("     Big-endian (bytes[1] << 8 | bytes[2]): \(bigEndian)")
        }

        // Validate range (0-5000 calories is reasonable)
        guard calories >= 0 && calories <= 5000 else {
            logError("Calories out of range: \(calories)", for: .calories)
            return lastValidValues[.calories] as? Int
        }

        // Calories should only increase or stay same
        if let lastCalories = lastValidValues[.calories] as? Int {
            if calories < lastCalories {
                logWarning("Calories decreased: \(lastCalories) → \(calories)", for: .calories)
            }
        }

        return calories
    }

    private func parseTime(bytes: [UInt8]) -> TreadmillData.TimeComponents? {
        guard bytes.count >= 4 else {
            logError("Time data too short: \(bytes.count) bytes (need at least 4)", for: .time)
            return lastValidValues[.time] as? TreadmillData.TimeComponents
        }

        let hours = Int(bytes[1])
        let minutes = Int(bytes[2])
        let seconds = Int(bytes[3])

        // Validate ranges
        guard hours >= 0 && hours < 24,
              minutes >= 0 && minutes < 60,
              seconds >= 0 && seconds < 60 else {
            logError("Time values invalid: \(hours)h \(minutes)m \(seconds)s", for: .time)
            return lastValidValues[.time] as? TreadmillData.TimeComponents
        }

        return TreadmillData.TimeComponents(hours: hours, minutes: minutes, seconds: seconds)
    }

    // MARK: - Logging Helpers

    private func logRawData(_ data: Data, for query: TreadmillQuery) {
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let decString = data.map { String($0) }.joined(separator: ", ")

        print("\n📥 [\(query.rawValue.uppercased())] Received \(data.count) bytes")
        print("   Hex: \(hexString)")
        print("   Dec: \(decString)")
    }

    private func logSuccess(_ value: String, for query: TreadmillQuery) {
        print("   ✅ \(query.rawValue.capitalized): \(value)")
    }

    private func logError(_ message: String, for query: TreadmillQuery) {
        print("   ❌ [\(query.rawValue.uppercased())] ERROR: \(message)")
    }

    private func logWarning(_ message: String, for query: TreadmillQuery) {
        print("   ⚠️ [\(query.rawValue.uppercased())] WARNING: \(message)")
    }

    // MARK: - Reset

    func reset() {
        lastValidValues.removeAll()
    }
}
