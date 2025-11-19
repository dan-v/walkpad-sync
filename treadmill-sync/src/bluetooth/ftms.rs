use anyhow::{anyhow, Result};
use tracing::{debug, warn};
use uuid::Uuid;

// FTMS Service and Characteristic UUIDs (Standard Protocol)
#[allow(dead_code)]
pub const FTMS_SERVICE_UUID: Uuid = Uuid::from_u128(0x00001826_0000_1000_8000_00805F9B34FB);
pub const TREADMILL_DATA_UUID: Uuid = Uuid::from_u128(0x00002ACD_0000_1000_8000_00805F9B34FB);
#[allow(dead_code)]
pub const INDOOR_BIKE_DATA_UUID: Uuid = Uuid::from_u128(0x00002AD2_0000_1000_8000_00805F9B34FB);
#[allow(dead_code)]
pub const FITNESS_MACHINE_CONTROL_POINT_UUID: Uuid = Uuid::from_u128(0x00002AD9_0000_1000_8000_00805F9B34FB);
#[allow(dead_code)]
pub const FITNESS_MACHINE_STATUS_UUID: Uuid = Uuid::from_u128(0x00002ADA_0000_1000_8000_00805F9B34FB);

// LifeSpan Proprietary Protocol UUIDs
pub const LIFESPAN_SERVICE_UUID: Uuid = Uuid::from_u128(0x0000FFF0_0000_1000_8000_00805F9B34FB);
pub const LIFESPAN_DATA_UUID: Uuid = Uuid::from_u128(0x0000FFF1_0000_1000_8000_00805F9B34FB);
#[allow(dead_code)]
pub const LIFESPAN_CONTROL_UUID: Uuid = Uuid::from_u128(0x0000FFF2_0000_1000_8000_00805F9B34FB);

// LifeSpan Proprietary Protocol Commands
pub const LIFESPAN_HANDSHAKE: [[u8; 5]; 4] = [
    [0x02, 0x00, 0x00, 0x00, 0x00],
    [0xC2, 0x00, 0x00, 0x00, 0x00],
    [0xE9, 0xFF, 0x00, 0x00, 0x00],
    [0xE4, 0x00, 0xF4, 0x00, 0x00],
];

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LifeSpanQuery {
    Steps,
    Distance,
    Calories,
    Speed,
    Time,
}

impl LifeSpanQuery {
    pub fn command(&self) -> [u8; 5] {
        match self {
            LifeSpanQuery::Steps => [0xA1, 0x88, 0x00, 0x00, 0x00],
            LifeSpanQuery::Distance => [0xA1, 0x85, 0x00, 0x00, 0x00],
            LifeSpanQuery::Calories => [0xA1, 0x87, 0x00, 0x00, 0x00],
            LifeSpanQuery::Speed => [0xA1, 0x82, 0x00, 0x00, 0x00],
            LifeSpanQuery::Time => [0xA1, 0x89, 0x00, 0x00, 0x00],
        }
    }

    pub fn all_queries() -> [LifeSpanQuery; 5] {
        [
            LifeSpanQuery::Steps,
            LifeSpanQuery::Distance,
            LifeSpanQuery::Calories,
            LifeSpanQuery::Speed,
            LifeSpanQuery::Time,
        ]
    }
}

#[derive(Debug, Clone, Default)]
pub struct TreadmillData {
    pub speed: Option<f64>,           // m/s
    pub incline: Option<f64>,         // percentage
    pub distance: Option<u32>,        // meters
    pub steps: Option<u16>,           // step count
    pub total_energy: Option<u16>,    // kcal
    pub energy_per_hour: Option<u16>, // kcal/hour
    pub heart_rate: Option<u8>,       // bpm
    pub elapsed_time: Option<u32>,    // seconds (changed from u16 to support long workouts)
    pub remaining_time: Option<u16>,  // seconds
    pub force_on_belt: Option<i16>,   // newtons
    pub power_output: Option<i16>,    // watts
}

pub fn parse_treadmill_data(data: &[u8]) -> Result<TreadmillData> {
    if data.len() < 2 {
        return Err(anyhow!("Data too short"));
    }

    // DEBUG: Log raw data bytes
    debug!("FTMS RAW DATA ({} bytes): {:02X?}", data.len(), data);

    let mut result = TreadmillData::default();
    let mut offset = 0;

    // Parse flags (2 bytes, little-endian)
    let flags = u16::from_le_bytes([data[0], data[1]]);
    debug!("FTMS FLAGS: 0x{:04X} (binary: {:016b})", flags, flags);
    offset += 2;

    // Bit 0: More Data
    let _more_data = (flags & 0x0001) != 0;

    // Bit 1: Average Speed Present
    if (flags & 0x0002) != 0 {
        if data.len() < offset + 2 {
            return Err(anyhow!("Not enough data for average speed"));
        }
        let raw_speed = u16::from_le_bytes([data[offset], data[offset + 1]]);
        let speed_kmh = raw_speed as f64 / 100.0;
        let speed_ms = speed_kmh / 3.6; // km/h to m/s
        result.speed = Some(speed_ms);
        debug!("FTMS SPEED: raw={} ({:.2} km/h = {:.2} m/s)", raw_speed, speed_kmh, speed_ms);
        offset += 2;
    }

    // Bit 2: Total Distance Present
    let total_distance_present = (flags & 0x0004) != 0;
    if total_distance_present {
        if data.len() < offset + 3 {
            return Err(anyhow!("Not enough data for total distance"));
        }
        let raw_distance = u32::from_le_bytes([data[offset], data[offset + 1], data[offset + 2], 0]);
        result.distance = Some(raw_distance); // already in meters
        debug!("FTMS DISTANCE: {} meters", raw_distance);
        offset += 3;
    }

    // Bit 3: Inclination and Ramp Angle Setting Present
    if (flags & 0x0008) != 0 {
        if data.len() < offset + 4 {
            return Err(anyhow!("Not enough data for inclination"));
        }
        let raw_incline = i16::from_le_bytes([data[offset], data[offset + 1]]);
        let incline_pct = raw_incline as f64 / 10.0; // 0.1% resolution
        result.incline = Some(incline_pct);
        debug!("FTMS INCLINE: raw={} ({:.1}%)", raw_incline, incline_pct);
        offset += 4; // Skip ramp angle (2 bytes) + inclination (2 bytes)
    }

    // Bit 4: Elevation Gain Present
    if (flags & 0x0010) != 0 {
        if data.len() < offset + 4 {
            return Err(anyhow!("Not enough data for elevation gain"));
        }
        offset += 4; // Skip positive (2 bytes) and negative (2 bytes) elevation
    }

    // Bit 5: Instantaneous Pace Present
    if (flags & 0x0020) != 0 {
        if data.len() < offset + 1 {
            return Err(anyhow!("Not enough data for pace"));
        }
        offset += 1;
    }

    // Bit 6: Average Pace Present
    if (flags & 0x0040) != 0 {
        if data.len() < offset + 1 {
            return Err(anyhow!("Not enough data for average pace"));
        }
        offset += 1;
    }

    // Bit 7: Expended Energy Present
    if (flags & 0x0080) != 0 {
        if data.len() < offset + 2 {
            return Err(anyhow!("Not enough data for energy"));
        }
        let total_energy = u16::from_le_bytes([data[offset], data[offset + 1]]);
        result.total_energy = Some(total_energy);
        debug!("FTMS ENERGY: {} kcal", total_energy);
        offset += 2;

        if data.len() >= offset + 2 {
            let energy_per_hour = u16::from_le_bytes([data[offset], data[offset + 1]]);
            result.energy_per_hour = Some(energy_per_hour);
            debug!("FTMS ENERGY/HR: {} kcal/h", energy_per_hour);
            offset += 2;
        }

        if data.len() >= offset + 1 {
            offset += 1; // Skip energy per minute
        }
    }

    // Bit 8: Heart Rate Present
    if (flags & 0x0100) != 0 {
        if data.len() < offset + 1 {
            return Err(anyhow!("Not enough data for heart rate"));
        }
        result.heart_rate = Some(data[offset]);
        debug!("FTMS HEART RATE: {} bpm", data[offset]);
        offset += 1;
    }

    // Bit 9: Metabolic Equivalent Present
    if (flags & 0x0200) != 0 {
        if data.len() < offset + 1 {
            return Err(anyhow!("Not enough data for metabolic equivalent"));
        }
        offset += 1;
    }

    // Bit 10: Elapsed Time Present
    if (flags & 0x0400) != 0 {
        if data.len() < offset + 2 {
            return Err(anyhow!("Not enough data for elapsed time"));
        }
        let elapsed = u16::from_le_bytes([data[offset], data[offset + 1]]);
        result.elapsed_time = Some(elapsed as u32);
        debug!("FTMS ELAPSED TIME: {} seconds", elapsed);
        offset += 2;
    }

    // Bit 11: Remaining Time Present
    if (flags & 0x0800) != 0 {
        if data.len() < offset + 2 {
            return Err(anyhow!("Not enough data for remaining time"));
        }
        let remaining = u16::from_le_bytes([data[offset], data[offset + 1]]);
        result.remaining_time = Some(remaining);
        debug!("FTMS REMAINING TIME: {} seconds", remaining);
        offset += 2;
    }

    // Bit 12: Force on Belt and Power Output Present
    if (flags & 0x1000) != 0 {
        if data.len() < offset + 2 {
            return Err(anyhow!("Not enough data for force on belt"));
        }
        let force = i16::from_le_bytes([data[offset], data[offset + 1]]);
        result.force_on_belt = Some(force);
        debug!("FTMS FORCE ON BELT: {} N", force);
        offset += 2;

        if data.len() >= offset + 2 {
            let power = i16::from_le_bytes([data[offset], data[offset + 1]]);
            result.power_output = Some(power);
            debug!("FTMS POWER OUTPUT: {} W", power);
        }
    }

    // Validate parsed data for sanity
    if let Some(speed) = result.speed {
        if speed < 0.0 || speed > 50.0 {  // 50 m/s = 180 km/h (impossible for treadmill)
            return Err(anyhow!("Invalid speed: {} m/s", speed));
        }
    }

    if let Some(incline) = result.incline {
        if incline < -15.0 || incline > 40.0 {  // Reasonable treadmill limits
            return Err(anyhow!("Invalid incline: {}%", incline));
        }
    }

    if let Some(hr) = result.heart_rate {
        if hr == 0 || hr > 220 {  // Invalid heart rate
            result.heart_rate = None;  // Discard invalid HR
        }
    }

    if let Some(distance) = result.distance {
        if distance > 1_000_000 {  // 1000 km seems like a reasonable max
            return Err(anyhow!("Invalid distance: {} meters", distance));
        }
    }

    // DEBUG: Summary of all parsed values
    debug!(
        "FTMS PARSED SUMMARY: speed={:?} m/s, incline={:?}%, distance={:?}m, calories={:?}kcal, hr={:?}bpm, elapsed={:?}s, power={:?}W",
        result.speed,
        result.incline,
        result.distance,
        result.total_energy,
        result.heart_rate,
        result.elapsed_time,
        result.power_output
    );

    Ok(result)
}

/// Parse LifeSpan proprietary protocol response
pub fn parse_lifespan_response(data: &[u8], query: LifeSpanQuery) -> Result<TreadmillData> {
    if data.len() < 4 {
        return Err(anyhow!("LifeSpan data too short: {} bytes", data.len()));
    }

    let mut result = TreadmillData::default();

    // Log raw response
    debug!(
        "LifeSpan response for {:?}: bytes={:02X?}",
        query, data
    );

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
            if speed_mph >= 0.0 && speed_mph <= 5.0 {
                result.speed = Some(speed_ms);
                debug!("LifeSpan speed: {:.2} mph = {:.2} m/s", speed_mph, speed_ms);
            } else if speed_mph > 5.0 {
                warn!("Walking pad speed {:.2} mph exceeds max (5 mph) - possible data corruption, but recording anyway", speed_mph);
                // Still record it - don't silently discard potentially valid data
                result.speed = Some(speed_ms);
            }
        }

        LifeSpanQuery::Distance => {
            // Distance format: bytes[3-4] as 16-bit LE representing hundredths of miles
            // Example: 0x0001 = 1 hundredth = 0.01 miles
            if data.len() < 5 {
                return Err(anyhow!("LifeSpan distance data too short"));
            }
            let distance_hundredths = u16::from_le_bytes([data[3], data[4]]);
            let distance_miles = distance_hundredths as f64 / 100.0;

            // Convert miles to meters (1 mile = 1609.34 meters)
            let distance_meters = (distance_miles * 1609.34) as u32;

            // Validate: distance should be reasonable (0-50 miles = 0-5000 hundredths)
            if distance_hundredths <= 5000 {
                result.distance = Some(distance_meters);
                debug!("LifeSpan distance: {:.2} miles = {} meters", distance_miles, distance_meters);
            } else {
                debug!("Invalid distance: {} hundredths ({:.2} miles)", distance_hundredths, distance_miles);
            }
        }

        LifeSpanQuery::Calories => {
            // Calories format: 16-bit little-endian in bytes[3] and bytes[4]
            if data.len() < 5 {
                return Err(anyhow!("LifeSpan calories data too short"));
            }
            let calories = u16::from_le_bytes([data[3], data[4]]);

            // Validate: calories should be reasonable (0-5000)
            if calories <= 5000 {
                result.total_energy = Some(calories);
                debug!("LifeSpan calories: {} kcal", calories);
            } else {
                debug!("Invalid calories: {}", calories);
            }
        }

        LifeSpanQuery::Steps => {
            // Steps format: 16-bit little-endian in bytes[3] and bytes[4]
            if data.len() < 5 {
                return Err(anyhow!("LifeSpan steps data too short"));
            }
            let steps = u16::from_le_bytes([data[3], data[4]]);
            debug!("LifeSpan steps: {}", steps);
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
                    debug!("LifeSpan time: {}h {}m {}s = {} seconds", hours, minutes, seconds, total_seconds);
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
    fn test_parse_basic_treadmill_data() {
        // Example data with speed, distance, and energy
        let data = vec![
            0x86, 0x00, // Flags: speed + distance + energy
            0xE8, 0x03, // Speed: 1000 (10.00 km/h)
            0x64, 0x00, 0x00, // Distance: 100 meters
            0x0A, 0x00, // Total energy: 10 kcal
            0x64, 0x00, // Energy per hour: 100 kcal/h
        ];

        let result = parse_treadmill_data(&data).unwrap();
        assert!(result.speed.is_some());
        assert!(result.distance.is_some());
        assert_eq!(result.distance.unwrap(), 100);
    }
}
