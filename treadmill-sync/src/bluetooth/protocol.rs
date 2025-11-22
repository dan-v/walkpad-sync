//! Treadmill Protocol Abstraction
//!
//! This module provides a trait-based abstraction for different treadmill protocols,
//! making it easy to add support for new treadmill models in the future.
//!
//! # Currently Supported Protocols
//!
//! - **LifeSpan Proprietary**: Polling-based protocol for LifeSpan TR1200-DT3 and similar
//!
//! # Adding Support for a New Treadmill Model
//!
//! To add support for a new treadmill:
//!
//! 1. **Discover the protocol**: Use a BLE scanner app to find your treadmill's
//!    service and characteristic UUIDs. Note whether it pushes data (passive)
//!    or requires polling.
//!
//! 2. **Add UUID constant**: In `ftms.rs`, add your characteristic UUID:
//!    ```rust,ignore
//!    pub const MY_TREADMILL_UUID: Uuid = Uuid::from_u128(0x0000XXXX_0000_1000_8000_00805F9B34FB);
//!    ```
//!
//! 3. **Implement parser**: In `ftms.rs`, add a parsing function for your data format:
//!    ```rust,ignore
//!    pub fn parse_my_treadmill_data(data: &[u8]) -> Result<TreadmillData> { ... }
//!    ```
//!
//! 4. **Create protocol struct**: Below, implement `TreadmillProtocol`:
//!    ```rust,ignore
//!    #[derive(Debug)]
//!    pub struct MyTreadmillProtocol;
//!
//!    impl TreadmillProtocol for MyTreadmillProtocol {
//!        fn name(&self) -> &'static str { "My Treadmill" }
//!        fn characteristic_uuid(&self) -> Uuid { MY_TREADMILL_UUID }
//!        fn mode(&self) -> ProtocolMode { ProtocolMode::Passive }
//!        fn parse_data(&self, data: &[u8], _: Option<QueryType>) -> Result<TreadmillData> {
//!            parse_my_treadmill_data(data)
//!        }
//!    }
//!    ```
//!
//! 5. **Register protocol**: Add detection in `detect_protocol()` and
//!    `supported_protocol_uuids()`.

use anyhow::Result;
use btleplug::api::Characteristic;
use std::fmt::Debug;
use uuid::Uuid;

use super::ftms::{LifeSpanQuery, TreadmillData, LIFESPAN_CHAR_UUID};

/// Communication mode for the protocol
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ProtocolMode {
    /// Device pushes notifications automatically
    Passive,
    /// Need to poll the device for data
    Polling { interval_ms: u64 },
}

/// Handshake command to send during initialization
#[derive(Debug, Clone)]
pub struct HandshakeCommand {
    pub data: Vec<u8>,
    pub delay_after_ms: u64,
}

/// Query command for polling-mode protocols
///
/// Note: HeartRate and Incline are included for future protocol support
#[derive(Debug, Clone, Copy, PartialEq)]
#[allow(dead_code)]
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
    // Try LifeSpan proprietary protocol
    if characteristics.iter().any(|c| c.uuid == LIFESPAN_CHAR_UUID) {
        return Some(Box::new(LifeSpanProtocol));
    }

    // Add detection for new protocols here:
    // if characteristics.iter().any(|c| c.uuid == MY_TREADMILL_UUID) {
    //     return Some(Box::new(MyTreadmillProtocol));
    // }

    None
}

/// Get a list of all supported protocol UUIDs for logging
pub fn supported_protocol_uuids() -> Vec<(Uuid, &'static str)> {
    vec![
        (LIFESPAN_CHAR_UUID, "LifeSpan Proprietary"),
        // Add new protocols here
    ]
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
        LIFESPAN_CHAR_UUID
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
        // Delegate to LifeSpanQuery to avoid duplicating command bytes
        let lifespan_query = match query {
            QueryType::Steps => LifeSpanQuery::Steps,
            QueryType::Distance => LifeSpanQuery::Distance,
            QueryType::Calories => LifeSpanQuery::Calories,
            QueryType::Speed => LifeSpanQuery::Speed,
            QueryType::Time => LifeSpanQuery::Time,
            _ => return None,
        };
        Some(lifespan_query.command().to_vec())
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
