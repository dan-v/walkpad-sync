//! Treadmill Protocol Abstraction
//!
//! This module provides a trait-based abstraction for different treadmill protocols,
//! making it easy to add support for new treadmill models in the future.
//!
//! # Adding Support for a New Treadmill Model
//!
//! 1. Create a new module in `bluetooth/protocols/` (e.g., `bluetooth/protocols/walkingpad.rs`)
//! 2. Implement the `TreadmillProtocol` trait for your protocol
//! 3. Add the protocol detection logic in `detect_protocol()`
//!
//! ## Example Implementation
//!
//! ```rust,ignore
//! pub struct WalkingPadProtocol;
//!
//! impl TreadmillProtocol for WalkingPadProtocol {
//!     fn name(&self) -> &'static str { "WalkingPad" }
//!     fn characteristic_uuid(&self) -> Uuid { /* ... */ }
//!     // ... implement other methods
//! }
//! ```

use anyhow::Result;
use btleplug::api::Characteristic;
use std::fmt::Debug;
use uuid::Uuid;

use super::ftms::{TreadmillData, LIFESPAN_DATA_UUID, TREADMILL_DATA_UUID};

/// Communication mode for the protocol
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ProtocolMode {
    /// Device pushes notifications automatically (FTMS standard)
    Passive,
    /// Need to poll the device for data (LifeSpan proprietary)
    Polling { interval_ms: u64 },
}

/// Handshake command to send during initialization
#[derive(Debug, Clone)]
pub struct HandshakeCommand {
    pub data: Vec<u8>,
    pub delay_after_ms: u64,
}

/// Query command for polling-mode protocols
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum QueryType {
    Speed,
    Distance,
    Calories,
    Steps,
    Time,
    HeartRate,
    Incline,
}

/// Trait for treadmill communication protocols
///
/// Implement this trait to add support for new treadmill models.
pub trait TreadmillProtocol: Send + Sync + Debug {
    /// Human-readable name of the protocol
    fn name(&self) -> &'static str;

    /// UUID of the characteristic to subscribe to for data
    fn characteristic_uuid(&self) -> Uuid;

    /// Communication mode (passive notifications or active polling)
    fn mode(&self) -> ProtocolMode;

    /// Optional handshake commands to send after connecting
    fn handshake_commands(&self) -> Vec<HandshakeCommand> {
        Vec::new()
    }

    /// For polling mode: list of queries to cycle through
    fn polling_queries(&self) -> Vec<QueryType> {
        Vec::new()
    }

    /// Generate a query command for the given query type
    fn query_command(&self, _query: QueryType) -> Option<Vec<u8>> {
        None
    }

    /// Parse raw data from the device into TreadmillData
    fn parse_data(&self, data: &[u8], query: Option<QueryType>) -> Result<TreadmillData>;

    /// Check if this is the last query in a polling cycle
    /// (used to know when to emit a complete sample)
    fn is_cycle_complete(&self, _query: QueryType) -> bool {
        true
    }
}

/// Detect the appropriate protocol based on available characteristics
pub fn detect_protocol(characteristics: &[Characteristic]) -> Option<Box<dyn TreadmillProtocol>> {
    // Try FTMS standard first (preferred)
    if characteristics
        .iter()
        .any(|c| c.uuid == TREADMILL_DATA_UUID)
    {
        return Some(Box::new(FtmsProtocol));
    }

    // Try LifeSpan proprietary
    if characteristics.iter().any(|c| c.uuid == LIFESPAN_DATA_UUID) {
        return Some(Box::new(LifeSpanProtocol));
    }

    None
}

/// Get a list of all supported protocol UUIDs for logging
pub fn supported_protocol_uuids() -> Vec<(Uuid, &'static str)> {
    vec![
        (TREADMILL_DATA_UUID, "FTMS Standard"),
        (LIFESPAN_DATA_UUID, "LifeSpan Proprietary"),
        // Add new protocols here
    ]
}

// ============================================================================
// FTMS Standard Protocol Implementation
// ============================================================================

/// FTMS (Fitness Machine Service) standard protocol
/// Used by many modern treadmills that follow the Bluetooth SIG specification
#[derive(Debug)]
pub struct FtmsProtocol;

impl TreadmillProtocol for FtmsProtocol {
    fn name(&self) -> &'static str {
        "FTMS Standard"
    }

    fn characteristic_uuid(&self) -> Uuid {
        TREADMILL_DATA_UUID
    }

    fn mode(&self) -> ProtocolMode {
        ProtocolMode::Passive
    }

    fn parse_data(&self, data: &[u8], _query: Option<QueryType>) -> Result<TreadmillData> {
        super::ftms::parse_treadmill_data(data)
    }
}

// ============================================================================
// LifeSpan Proprietary Protocol Implementation
// ============================================================================

/// LifeSpan proprietary protocol
/// Used by LifeSpan TR1200-DT3 and similar models
#[derive(Debug)]
pub struct LifeSpanProtocol;

impl TreadmillProtocol for LifeSpanProtocol {
    fn name(&self) -> &'static str {
        "LifeSpan Proprietary"
    }

    fn characteristic_uuid(&self) -> Uuid {
        LIFESPAN_DATA_UUID
    }

    fn mode(&self) -> ProtocolMode {
        ProtocolMode::Polling { interval_ms: 300 }
    }

    fn handshake_commands(&self) -> Vec<HandshakeCommand> {
        super::ftms::LIFESPAN_HANDSHAKE
            .iter()
            .map(|cmd| HandshakeCommand {
                data: cmd.to_vec(),
                delay_after_ms: 100,
            })
            .collect()
    }

    fn polling_queries(&self) -> Vec<QueryType> {
        vec![
            QueryType::Steps,
            QueryType::Distance,
            QueryType::Calories,
            QueryType::Speed,
            QueryType::Time,
        ]
    }

    fn query_command(&self, query: QueryType) -> Option<Vec<u8>> {
        let cmd = match query {
            QueryType::Steps => [0xA1, 0x88, 0x00, 0x00, 0x00],
            QueryType::Distance => [0xA1, 0x85, 0x00, 0x00, 0x00],
            QueryType::Calories => [0xA1, 0x87, 0x00, 0x00, 0x00],
            QueryType::Speed => [0xA1, 0x82, 0x00, 0x00, 0x00],
            QueryType::Time => [0xA1, 0x89, 0x00, 0x00, 0x00],
            _ => return None,
        };
        Some(cmd.to_vec())
    }

    fn parse_data(&self, data: &[u8], query: Option<QueryType>) -> Result<TreadmillData> {
        let query =
            query.ok_or_else(|| anyhow::anyhow!("LifeSpan protocol requires query type"))?;
        let lifespan_query = match query {
            QueryType::Steps => super::ftms::LifeSpanQuery::Steps,
            QueryType::Distance => super::ftms::LifeSpanQuery::Distance,
            QueryType::Calories => super::ftms::LifeSpanQuery::Calories,
            QueryType::Speed => super::ftms::LifeSpanQuery::Speed,
            QueryType::Time => super::ftms::LifeSpanQuery::Time,
            _ => return Err(anyhow::anyhow!("Unsupported query type for LifeSpan")),
        };
        super::ftms::parse_lifespan_response(data, lifespan_query)
    }

    fn is_cycle_complete(&self, query: QueryType) -> bool {
        // Time is the last query in the cycle
        query == QueryType::Time
    }
}

// ============================================================================
// Future Protocol Template
// ============================================================================

// /// Template for adding a new treadmill protocol
// ///
// /// Copy this and modify for your treadmill model:
// ///
// /// ```rust,ignore
// /// #[derive(Debug)]
// /// pub struct MyTreadmillProtocol;
// ///
// /// impl TreadmillProtocol for MyTreadmillProtocol {
// ///     fn name(&self) -> &'static str {
// ///         "My Treadmill Brand"
// ///     }
// ///
// ///     fn characteristic_uuid(&self) -> Uuid {
// ///         Uuid::from_u128(0x0000XXXX_0000_1000_8000_00805F9B34FB)
// ///     }
// ///
// ///     fn mode(&self) -> ProtocolMode {
// ///         ProtocolMode::Passive // or ProtocolMode::Polling { interval_ms: 500 }
// ///     }
// ///
// ///     fn parse_data(&self, data: &[u8], _query: Option<QueryType>) -> Result<TreadmillData> {
// ///         // Parse your device's data format here
// ///         // Return TreadmillData with whatever fields you can extract
// ///         todo!("Implement parsing for your device")
// ///     }
// /// }
// /// ```
