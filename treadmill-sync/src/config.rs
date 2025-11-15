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
}

fn default_device_name_filter() -> String {
    "TR".to_string() // Common prefix for treadmills
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

    pub fn save<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }
}
