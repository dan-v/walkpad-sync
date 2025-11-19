pub mod ftms;

use anyhow::{anyhow, Result};
use btleplug::api::{
    Central, Characteristic, Manager as _, Peripheral as _, ScanFilter,
};
use btleplug::platform::{Adapter, Manager, Peripheral};
use chrono::Utc;
use futures_util::stream::StreamExt;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{broadcast, RwLock};
use tokio::time::sleep;
use tracing::{debug, error, info, warn};

use crate::config::BluetoothConfig;
use crate::storage::Storage;
use ftms::{
    parse_treadmill_data, parse_lifespan_response, TreadmillData,
    TREADMILL_DATA_UUID, LIFESPAN_DATA_UUID, LIFESPAN_HANDSHAKE, LifeSpanQuery,
};

#[derive(Debug, Clone)]
pub enum ConnectionStatus {
    Disconnected,
    Scanning,
    Connecting,
    Connected,
    Error(String),
}

pub struct BluetoothManager {
    storage: Arc<Storage>,
    config: BluetoothConfig,
    status_tx: broadcast::Sender<ConnectionStatus>,
}

impl BluetoothManager {
    pub fn new(
        storage: Arc<Storage>,
        config: BluetoothConfig,
    ) -> (Self, broadcast::Receiver<ConnectionStatus>) {
        let (status_tx, status_rx) = broadcast::channel(16);

        (Self {
            storage,
            config,
            status_tx,
        }, status_rx)
    }

    pub async fn run(&self) -> Result<()> {
        info!("Starting Bluetooth manager (scan_timeout={}s, reconnect_delay={}s)",
              self.config.scan_timeout_secs, self.config.reconnect_delay_secs);
        info!("🎯 Simple data capture mode - no workout detection, just raw samples");

        loop {
            match self.connect_and_monitor().await {
                Ok(_) => {
                    info!("Connection cycle completed normally");
                }
                Err(e) => {
                    error!("Connection error: {}", e);
                    let _ = self.status_tx.send(ConnectionStatus::Error(e.to_string()));
                }
            }

            // Wait before reconnecting
            info!("Waiting {} seconds before reconnection attempt...", self.config.reconnect_delay_secs);
            sleep(Duration::from_secs(self.config.reconnect_delay_secs)).await;
        }
    }

    async fn connect_and_monitor(&self) -> Result<()> {
        // Get BLE adapter
        let manager = Manager::new().await?;
        let adapters = manager.adapters().await?;
        let adapter = adapters.into_iter().next().ok_or_else(|| anyhow!("No BLE adapter found"))?;

        // Scan for device
        info!("Scanning for treadmill: {}", self.config.device_name_filter);
        let _ = self.status_tx.send(ConnectionStatus::Scanning);

        let peripheral = self.scan_for_device(&adapter).await?;

        // Connect
        info!("Found treadmill, connecting...");
        let _ = self.status_tx.send(ConnectionStatus::Connecting);

        peripheral.connect().await?;
        info!("Connected to treadmill");

        // Discover services and characteristics
        peripheral.discover_services().await?;
        let chars = peripheral.characteristics();

        // Log all discovered services and characteristics for debugging
        info!("Discovered {} characteristics on treadmill", chars.len());
        for (i, char) in chars.iter().enumerate() {
            debug!("  [{}] Service: {}, Characteristic: {}, Properties: {:?}",
                   i, char.service_uuid, char.uuid, char.properties);
        }

        // Try to find FTMS characteristic first, then fall back to LifeSpan proprietary
        let treadmill_char = chars
            .iter()
            .find(|c| c.uuid == TREADMILL_DATA_UUID)
            .or_else(|| {
                debug!("FTMS characteristic not found, trying LifeSpan proprietary protocol...");
                chars.iter().find(|c| c.uuid == LIFESPAN_DATA_UUID)
            })
            .ok_or_else(|| {
                warn!("Neither FTMS (UUID: {}) nor LifeSpan (UUID: {}) characteristic found",
                      TREADMILL_DATA_UUID, LIFESPAN_DATA_UUID);
                warn!("Your treadmill may use a different protocol");
                warn!("Check the characteristic list above to see what your treadmill exposes");
                anyhow!("Treadmill data characteristic not found")
            })?;

        if treadmill_char.uuid == LIFESPAN_DATA_UUID {
            info!("Using LifeSpan proprietary protocol (UUID: {})", LIFESPAN_DATA_UUID);
        } else {
            info!("Using standard FTMS protocol (UUID: {})", TREADMILL_DATA_UUID);
        }

        // Subscribe to notifications
        peripheral.subscribe(treadmill_char).await?;
        info!("Subscribed to treadmill data notifications");

        // Send handshake if using LifeSpan protocol
        if treadmill_char.uuid == LIFESPAN_DATA_UUID {
            info!("Sending LifeSpan handshake sequence ({} commands)...", LIFESPAN_HANDSHAKE.len());
            for (i, cmd) in LIFESPAN_HANDSHAKE.iter().enumerate() {
                peripheral.write(treadmill_char, cmd, btleplug::api::WriteType::WithResponse).await?;
                debug!("Sent handshake command {}/{}: {:02X?}", i + 1, LIFESPAN_HANDSHAKE.len(), cmd);
                sleep(Duration::from_millis(100)).await;
            }
            info!("Handshake complete");
        }

        let _ = self.status_tx.send(ConnectionStatus::Connected);

        // Monitor notifications (will poll for LifeSpan or passively listen for FTMS)
        self.monitor_notifications(&peripheral, treadmill_char).await?;

        Ok(())
    }

    async fn scan_for_device(&self, adapter: &Adapter) -> Result<Peripheral> {
        adapter.start_scan(ScanFilter::default()).await?;

        // Scan for configured timeout
        let timeout = self.config.scan_timeout_secs;
        let mut discovered_devices: std::collections::HashSet<String> = std::collections::HashSet::new();

        for i in 0..timeout {
            sleep(Duration::from_secs(1)).await;

            let peripherals = adapter.peripherals().await?;
            for peripheral in peripherals {
                if let Ok(Some(props)) = peripheral.properties().await {
                    if let Some(name) = props.local_name {
                        // Log all discovered devices for debugging
                        if discovered_devices.insert(name.clone()) {
                            debug!("Discovered BLE device: '{}' (address: {:?})", name, props.address);
                        }

                        if name.contains(&self.config.device_name_filter) {
                            info!("Found treadmill '{}' after {} seconds", name, i + 1);
                            adapter.stop_scan().await?;
                            return Ok(peripheral);
                        }
                    }
                }
            }
        }

        adapter.stop_scan().await?;

        // Log summary of discovered devices for debugging
        if discovered_devices.is_empty() {
            warn!("No BLE devices discovered at all. Is Bluetooth enabled and are there devices nearby?");
        } else {
            warn!("Treadmill not found. Discovered {} device(s): {:?}",
                  discovered_devices.len(),
                  discovered_devices.iter().collect::<Vec<_>>());
            warn!("Hint: Update device_name_filter in config.toml to match your treadmill's name");
        }

        Err(anyhow!("Treadmill not found after {} seconds", timeout))
    }

    async fn monitor_notifications(&self, peripheral: &Peripheral, char: &Characteristic) -> Result<()> {
        let mut notification_stream = peripheral.notifications().await?;
        let mut sample_count = 0;

        // For LifeSpan protocol: track pending queries with shared queue
        let pending_queries = Arc::new(RwLock::new(std::collections::VecDeque::<LifeSpanQuery>::new()));
        let is_lifespan = char.uuid == LIFESPAN_DATA_UUID;

        // For LifeSpan: accumulate responses from all 5 queries into complete samples
        let mut lifespan_accumulator = if is_lifespan {
            Some(TreadmillData::default())
        } else {
            None
        };

        // Start polling task for LifeSpan protocol
        let poll_task = if is_lifespan {
            let peripheral = peripheral.clone();
            let char = char.clone();
            let pending_queries = pending_queries.clone();

            Some(tokio::spawn(async move {
                let queries = LifeSpanQuery::all_queries();
                let query_delay = Duration::from_millis(300);

                loop {
                    for query in &queries {
                        let cmd = query.command();
                        if let Err(e) = peripheral.write(&char, &cmd, btleplug::api::WriteType::WithResponse).await {
                            error!("Failed to write LifeSpan query {:?}: {}", query, e);
                            return;
                        }

                        // Enqueue the query we just sent
                        {
                            let mut queue = pending_queries.write().await;
                            queue.push_back(*query);
                            // Prevent runaway queue if treadmill stops responding
                            if queue.len() > 20 {
                                queue.pop_front();
                            }
                        }

                        debug!("Sent LifeSpan query: {:?}", query);
                        tokio::time::sleep(query_delay).await;
                    }
                }
            }))
        } else {
            None
        };

        info!("📊 Capturing raw samples... (no workout detection)");

        while let Some(notification) = notification_stream.next().await {
            if notification.uuid != char.uuid {
                continue;
            }

            // Handle LifeSpan vs FTMS protocol
            let data = if is_lifespan {
                // Dequeue the pending query
                let query = {
                    let mut queue = pending_queries.write().await;
                    queue.pop_front()
                };

                if let Some(query) = query {
                    // Parse response for this specific query
                    match parse_lifespan_response(&notification.value, query) {
                        Ok(partial_data) => {
                            // Accumulate this response into the accumulator
                            if let Some(ref mut acc) = lifespan_accumulator {
                                // Merge partial_data fields into accumulator
                                if partial_data.speed.is_some() {
                                    acc.speed = partial_data.speed;
                                }
                                if partial_data.distance.is_some() {
                                    acc.distance = partial_data.distance;
                                }
                                if partial_data.steps.is_some() {
                                    acc.steps = partial_data.steps;
                                }
                                if partial_data.total_energy.is_some() {
                                    acc.total_energy = partial_data.total_energy;
                                }
                                if partial_data.elapsed_time.is_some() {
                                    acc.elapsed_time = partial_data.elapsed_time;
                                }

                                // Time query is the last in the cycle - process accumulated data
                                if query == LifeSpanQuery::Time {
                                    let complete_data = acc.clone();
                                    *acc = TreadmillData::default(); // Reset for next cycle
                                    complete_data
                                } else {
                                    // Not ready yet, skip this notification
                                    continue;
                                }
                            } else {
                                continue;
                            }
                        }
                        Err(e) => {
                            debug!("Failed to parse LifeSpan response for {:?}: {}", query, e);
                            continue;
                        }
                    }
                } else {
                    debug!("Received LifeSpan data with no pending query");
                    continue;
                }
            } else {
                // Parse standard FTMS protocol
                match parse_treadmill_data(&notification.value) {
                    Ok(data) => data,
                    Err(e) => {
                        warn!("Failed to parse FTMS treadmill data: {}", e);
                        continue;
                    }
                }
            };

            // Record the raw sample to database
            if let Err(e) = self.record_sample(&data).await {
                error!("Failed to record sample: {}", e);
            } else {
                sample_count += 1;

                // Log every 60 samples (~1 minute at 1 Hz)
                if sample_count % 60 == 0 {
                    info!("📈 Captured {} samples | Latest: speed={:.2} m/s, distance={:?}m, steps={:?}, calories={:?}kcal",
                          sample_count,
                          data.speed.unwrap_or(0.0),
                          data.distance,
                          data.steps,
                          data.total_energy);
                }
            }

            // Check if we're still connected
            if !peripheral.is_connected().await? {
                warn!("Lost connection to treadmill after {} samples", sample_count);
                if let Some(task) = poll_task {
                    task.abort();
                }
                return Err(anyhow!("Connection lost"));
            }
        }

        // Cancel polling task if it exists
        if let Some(task) = poll_task {
            task.abort();
        }

        Ok(())
    }

    async fn record_sample(&self, data: &TreadmillData) -> Result<()> {
        let timestamp = Utc::now();

        // Store raw cumulative values from treadmill
        self.storage.add_sample(
            timestamp,
            data.speed,
            data.distance.map(|d| d as i64),
            data.total_energy.map(|e| e as i64),
            data.steps.map(|s| s as i64),
        ).await?;

        Ok(())
    }
}
