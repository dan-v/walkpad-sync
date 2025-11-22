//! Configuration management for the treadmill sync service.
//!
//! Configuration is loaded in this priority order:
//! 1. Environment variables (highest priority)
//! 2. Config file (config.toml)
//! 3. Built-in defaults (lowest priority)
//!
//! # Environment Variables
//!
//! - `TREADMILL_DB_PATH` - Path to SQLite database
//! - `TREADMILL_DEVICE_FILTER` - Bluetooth device name filter
//! - `TREADMILL_SCAN_TIMEOUT` - Bluetooth scan timeout in seconds
//! - `TREADMILL_RECONNECT_DELAY` - Reconnect delay in seconds
//! - `TREADMILL_HOST` - HTTP server bind address
//! - `TREADMILL_PORT` - HTTP server port

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub database: DatabaseConfig,
    pub bluetooth: BluetoothConfig,
    pub server: ServerConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    #[serde(default = "default_database_path")]
    pub path: String,
}

fn default_database_path() -> String {
    "./treadmill.db".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BluetoothConfig {
    #[serde(default = "default_device_name_filter")]
    pub device_name_filter: String,

    /// Timeout in seconds for scanning for treadmill
    #[serde(default = "default_scan_timeout")]
    pub scan_timeout_secs: u64,

    /// Seconds to wait before reconnecting after disconnection
    #[serde(default = "default_reconnect_delay")]
    pub reconnect_delay_secs: u64,
}

fn default_device_name_filter() -> String {
    "LifeSpan".to_string()
}

fn default_scan_timeout() -> u64 {
    30
}

fn default_reconnect_delay() -> u64 {
    5
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    #[serde(default = "default_host")]
    pub host: String,

    #[serde(default = "default_port")]
    pub port: u16,
}

fn default_host() -> String {
    "0.0.0.0".to_string()
}

fn default_port() -> u16 {
    8080
}

impl Default for Config {
    fn default() -> Self {
        Self {
            database: DatabaseConfig {
                path: default_database_path(),
            },
            bluetooth: BluetoothConfig {
                device_name_filter: default_device_name_filter(),
                scan_timeout_secs: default_scan_timeout(),
                reconnect_delay_secs: default_reconnect_delay(),
            },
            server: ServerConfig {
                host: default_host(),
                port: default_port(),
            },
        }
    }
}

impl Config {
    pub fn from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let config: Config = toml::from_str(&content)?;
        Ok(config)
    }

    pub fn from_file_or_default<P: AsRef<Path>>(path: P) -> Self {
        Self::from_file(path).unwrap_or_default()
    }

    /// Load config from file, then apply environment variable overrides.
    /// Environment variables take precedence over file values.
    pub fn load<P: AsRef<Path>>(config_path: P) -> Self {
        let mut config = Self::from_file_or_default(config_path);
        config.apply_env_overrides();
        config
    }

    /// Apply environment variable overrides to the current config.
    fn apply_env_overrides(&mut self) {
        // Database
        if let Ok(val) = std::env::var("TREADMILL_DB_PATH") {
            self.database.path = val;
        }

        // Bluetooth
        if let Ok(val) = std::env::var("TREADMILL_DEVICE_FILTER") {
            self.bluetooth.device_name_filter = val;
        }
        if let Ok(val) = std::env::var("TREADMILL_SCAN_TIMEOUT") {
            if let Ok(secs) = val.parse() {
                self.bluetooth.scan_timeout_secs = secs;
            }
        }
        if let Ok(val) = std::env::var("TREADMILL_RECONNECT_DELAY") {
            if let Ok(secs) = val.parse() {
                self.bluetooth.reconnect_delay_secs = secs;
            }
        }

        // Server
        if let Ok(val) = std::env::var("TREADMILL_HOST") {
            self.server.host = val;
        }
        if let Ok(val) = std::env::var("TREADMILL_PORT") {
            if let Ok(port) = val.parse() {
                self.server.port = port;
            }
        }
    }
}
