use anyhow::{anyhow, Result};
use tracing::debug;
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

#[derive(Debug, Clone, Default)]
pub struct TreadmillData {
    pub speed: Option<f64>,           // m/s
    pub incline: Option<f64>,         // percentage
    pub distance: Option<u32>,        // meters
    pub total_energy: Option<u16>,    // kcal
    pub energy_per_hour: Option<u16>, // kcal/hour
    pub heart_rate: Option<u8>,       // bpm
    pub elapsed_time: Option<u16>,    // seconds
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
        result.elapsed_time = Some(elapsed);
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
