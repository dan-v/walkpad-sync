//! Treadmill Protocol Parsers
//!
//! This module contains data structures and parsing functions for treadmill protocols.

use anyhow::{anyhow, Result};
use tracing::{debug, warn};
use uuid::Uuid;

// ============================================================================
// LifeSpan Protocol
// ============================================================================

/// Characteristic UUID used by LifeSpan treadmills for their proprietary protocol.
///
/// Note: 0xFFF1 is in the vendor-specific UUID range (0xFFF0-0xFFFF) commonly used
/// by BLE devices. While not unique to LifeSpan, the combination of this UUID plus
/// the device name filter and specific handshake/query protocol identifies LifeSpan
/// treadmills.
pub const LIFESPAN_CHAR_UUID: Uuid = Uuid::from_u128(0x0000FFF1_0000_1000_8000_00805F9B34FB);

/// Handshake sequence required to initialize communication with LifeSpan treadmills.
/// Must be sent after connecting, before polling for data.
pub const LIFESPAN_HANDSHAKE: [[u8; 5]; 4] = [
    [0x02, 0x00, 0x00, 0x00, 0x00],
    [0xC2, 0x00, 0x00, 0x00, 0x00],
    [0xE9, 0xFF, 0x00, 0x00, 0x00],
    [0xE4, 0x00, 0xF4, 0x00, 0x00],
];

/// Query types for LifeSpan polling protocol.
/// Each query retrieves one piece of data from the treadmill.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LifeSpanQuery {
    Steps,
    Distance,
    Calories,
    Speed,
    Time,
}

impl LifeSpanQuery {
    /// Returns the 5-byte command to send for this query type.
    pub fn command(&self) -> [u8; 5] {
        match self {
            LifeSpanQuery::Steps => [0xA1, 0x88, 0x00, 0x00, 0x00],
            LifeSpanQuery::Distance => [0xA1, 0x85, 0x00, 0x00, 0x00],
            LifeSpanQuery::Calories => [0xA1, 0x87, 0x00, 0x00, 0x00],
            LifeSpanQuery::Speed => [0xA1, 0x82, 0x00, 0x00, 0x00],
            LifeSpanQuery::Time => [0xA1, 0x89, 0x00, 0x00, 0x00],
        }
    }
}

// ============================================================================
// Common Data Structures
// ============================================================================

/// Parsed treadmill data from any protocol.
/// All fields are optional as different protocols provide different data.
#[derive(Debug, Clone, Default)]
pub struct TreadmillData {
    pub speed: Option<f64>,           // m/s
    pub incline: Option<f64>,         // percentage
    pub distance: Option<u32>,        // meters
    pub steps: Option<u16>,           // step count
    pub total_energy: Option<u16>,    // kcal
    pub energy_per_hour: Option<u16>, // kcal/hour
    pub heart_rate: Option<u8>,       // bpm
    pub elapsed_time: Option<u32>,    // seconds
    pub remaining_time: Option<u16>,  // seconds
    pub force_on_belt: Option<i16>,   // newtons
    pub power_output: Option<i16>,    // watts
}

// ============================================================================
// LifeSpan Protocol Parser
// ============================================================================

/// Parse LifeSpan proprietary protocol response.
///
/// Each query type returns data in a slightly different format, but all follow
/// the general pattern: [0xA1, 0xAA, data_bytes...]
pub fn parse_lifespan_response(data: &[u8], query: LifeSpanQuery) -> Result<TreadmillData> {
    if data.len() < 4 {
        return Err(anyhow!("LifeSpan data too short: {} bytes", data.len()));
    }

    let mut result = TreadmillData::default();

    // Log raw response
    debug!("LifeSpan response for {:?}: bytes={:02X?}", query, data);

    // Response format:
    // bytes[0] = 0xA1 (command echo)
    // bytes[1] = 0xAA (status byte)
    // bytes[2] = 0x00 (header)
    // bytes[3+] = actual data

    match query {
        LifeSpanQuery::Speed => {
            // Speed format: bytes[2] and bytes[3] encode speed in mph
            // bytes[2] = whole mph (0, 1, 2, etc.)
            // bytes[3] = hundredths of mph (0-99)
            // Formula: speed_hundredths = bytes[2] * 100 + bytes[3]
            // Examples:
            //   [A1, AA, 00, 28] = 0*100 + 40 = 40 hundredths = 0.40 mph
            //   [A1, AA, 00, 5A] = 0*100 + 90 = 90 hundredths = 0.90 mph
            //   [A1, AA, 01, 00] = 1*100 + 0 = 100 hundredths = 1.00 mph
            //   [A1, AA, 02, 32] = 2*100 + 50 = 250 hundredths = 2.50 mph
            if data.len() < 4 {
                return Err(anyhow!("LifeSpan speed data too short"));
            }
            let speed_hundredths = (data[2] as f64 * 100.0) + data[3] as f64;
            let speed_mph = speed_hundredths / 100.0;

            // Convert mph to m/s (1 mph = 0.44704 m/s)
            let speed_ms = speed_mph * 0.44704;

            // Validate: speed should be reasonable (0-5 mph for walking pads)
            if (0.0..=5.0).contains(&speed_mph) {
                result.speed = Some(speed_ms);
                debug!("LifeSpan speed: {:.2} mph = {:.2} m/s", speed_mph, speed_ms);
            } else if speed_mph > 5.0 {
                warn!("Walking pad speed {:.2} mph exceeds max (5 mph) - possible data corruption, but recording anyway", speed_mph);
                // Still record it - don't silently discard potentially valid data
                result.speed = Some(speed_ms);
            }
        }

        LifeSpanQuery::Distance => {
            // Distance format: 16-bit big-endian in bytes[2] and bytes[3]
            // Response format: [A1, AA, HIGH_BYTE, LOW_BYTE, ...]
            // Value is in hundredths of miles (2362 = 23.62 miles)
            if data.len() < 4 {
                return Err(anyhow!("LifeSpan distance data too short"));
            }

            // Parse as 16-bit big-endian from bytes[2] and bytes[3]
            let distance_hundredths = u16::from_be_bytes([data[2], data[3]]) as u32;
            let distance_miles = distance_hundredths as f64 / 100.0;
            let distance_meters = (distance_miles * 1609.34) as u32;

            result.distance = Some(distance_meters);
            debug!("LifeSpan distance: {:.2} miles = {} meters (raw: {} hundredths from bytes [0x{:02X}, 0x{:02X}])",
                   distance_miles, distance_meters, distance_hundredths, data[2], data[3]);
        }

        LifeSpanQuery::Calories => {
            // Calories format: 16-bit big-endian in bytes[2] and bytes[3]
            // Response format: [A1, AA, HIGH_BYTE, LOW_BYTE, ...]
            // Value is in kcal (972 = 972 kcal)
            if data.len() < 4 {
                return Err(anyhow!("LifeSpan calories data too short"));
            }

            // Parse as 16-bit big-endian from bytes[2] and bytes[3]
            let calories = u16::from_be_bytes([data[2], data[3]]);

            result.total_energy = Some(calories);
            debug!(
                "LifeSpan calories: {} kcal (raw bytes: [0x{:02X}, 0x{:02X}])",
                calories, data[2], data[3]
            );
        }

        LifeSpanQuery::Steps => {
            // Steps format: 16-bit big-endian in bytes[2] and bytes[3]
            // Response format: [A1, AA, HIGH_BYTE, LOW_BYTE, 00, 00]
            // Example: [A1, AA, 0x61, 0x88] = 0x6188 = 24968 steps
            if data.len() < 4 {
                return Err(anyhow!(
                    "LifeSpan steps data too short: {} bytes",
                    data.len()
                ));
            }

            // Parse as 16-bit big-endian from bytes[2] and bytes[3]
            let steps = u16::from_be_bytes([data[2], data[3]]);

            debug!(
                "LifeSpan steps: {} (raw bytes: [0x{:02X}, 0x{:02X}])",
                steps, data[2], data[3]
            );

            result.steps = Some(steps);
        }

        LifeSpanQuery::Time => {
            // Time format: bytes[3] (hours), bytes[4] (minutes), bytes[5] (seconds)
            if data.len() >= 6 {
                let hours = data[3] as u32;
                let minutes = data[4] as u32;
                let seconds = data[5] as u32;

                // Validate
                if hours < 24 && minutes < 60 && seconds < 60 {
                    // Use u32 for calculation and storage to support long workouts
                    let total_seconds = hours * 3600 + minutes * 60 + seconds;
                    result.elapsed_time = Some(total_seconds);
                    debug!(
                        "LifeSpan time: {}h {}m {}s = {} seconds",
                        hours, minutes, seconds, total_seconds
                    );
                } else {
                    debug!("Invalid time: {}:{}:{}", hours, minutes, seconds);
                }
            }
        }
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lifespan_speed_parsing() {
        // Speed format: [A1, AA, whole_mph, hundredths]
        // 2.50 mph = 2*100 + 50 = 250 hundredths
        let data = vec![0xA1, 0xAA, 0x02, 0x32]; // 2.50 mph
        let result = parse_lifespan_response(&data, LifeSpanQuery::Speed).unwrap();

        assert!(result.speed.is_some());
        let speed_ms = result.speed.unwrap();
        let speed_mph = speed_ms / 0.44704;
        assert!(
            (speed_mph - 2.50).abs() < 0.01,
            "Expected ~2.50 mph, got {}",
            speed_mph
        );
    }

    #[test]
    fn test_lifespan_speed_zero() {
        let data = vec![0xA1, 0xAA, 0x00, 0x00]; // 0 mph
        let result = parse_lifespan_response(&data, LifeSpanQuery::Speed).unwrap();

        // Speed 0 is valid but won't be set (filtered by validation)
        assert!(result.speed.is_none() || result.speed.unwrap() == 0.0);
    }

    #[test]
    fn test_lifespan_distance_parsing() {
        // Distance format: 16-bit big-endian hundredths of miles
        // [A1, AA, HIGH, LOW] where value = 100 = 1.00 miles
        let data = vec![0xA1, 0xAA, 0x00, 0x64]; // 100 hundredths = 1.00 mile
        let result = parse_lifespan_response(&data, LifeSpanQuery::Distance).unwrap();

        assert!(result.distance.is_some());
        let distance_m = result.distance.unwrap();
        let distance_miles = distance_m as f64 / 1609.34;
        assert!(
            (distance_miles - 1.0).abs() < 0.01,
            "Expected ~1.0 mile, got {}",
            distance_miles
        );
    }

    #[test]
    fn test_lifespan_calories_parsing() {
        // Calories format: 16-bit big-endian kcal
        let data = vec![0xA1, 0xAA, 0x01, 0xF4]; // 0x01F4 = 500 kcal
        let result = parse_lifespan_response(&data, LifeSpanQuery::Calories).unwrap();

        assert!(result.total_energy.is_some());
        assert_eq!(result.total_energy.unwrap(), 500);
    }

    #[test]
    fn test_lifespan_steps_parsing() {
        // Steps format: 16-bit big-endian
        let data = vec![0xA1, 0xAA, 0x27, 0x10]; // 0x2710 = 10000 steps
        let result = parse_lifespan_response(&data, LifeSpanQuery::Steps).unwrap();

        assert!(result.steps.is_some());
        assert_eq!(result.steps.unwrap(), 10000);
    }

    #[test]
    fn test_lifespan_time_parsing() {
        // Time format: [A1, AA, ??, hours, minutes, seconds]
        let data = vec![0xA1, 0xAA, 0x00, 0x01, 0x30, 0x00]; // 1h 48m 0s
        let result = parse_lifespan_response(&data, LifeSpanQuery::Time).unwrap();

        assert!(result.elapsed_time.is_some());
        assert_eq!(result.elapsed_time.unwrap(), 1 * 3600 + 48 * 60 + 0);
    }

    #[test]
    fn test_lifespan_data_too_short() {
        let data = vec![0xA1, 0xAA, 0x00]; // Only 3 bytes, need 4+
        assert!(parse_lifespan_response(&data, LifeSpanQuery::Speed).is_err());
    }

    #[test]
    fn test_lifespan_query_commands() {
        // Verify all query commands are correctly defined
        assert_eq!(
            LifeSpanQuery::Speed.command(),
            [0xA1, 0x82, 0x00, 0x00, 0x00]
        );
        assert_eq!(
            LifeSpanQuery::Distance.command(),
            [0xA1, 0x85, 0x00, 0x00, 0x00]
        );
        assert_eq!(
            LifeSpanQuery::Calories.command(),
            [0xA1, 0x87, 0x00, 0x00, 0x00]
        );
        assert_eq!(
            LifeSpanQuery::Steps.command(),
            [0xA1, 0x88, 0x00, 0x00, 0x00]
        );
        assert_eq!(
            LifeSpanQuery::Time.command(),
            [0xA1, 0x89, 0x00, 0x00, 0x00]
        );
    }
}
