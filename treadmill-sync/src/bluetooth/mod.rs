pub mod ftms;
pub mod protocol;

use anyhow::{anyhow, Result};
use btleplug::api::{Central, Characteristic, Manager as _, Peripheral as _, ScanFilter};
use btleplug::platform::{Adapter, Manager, Peripheral};
use chrono::Utc;
use futures_util::stream::StreamExt;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{broadcast, mpsc, RwLock};
use tokio::time::{sleep, timeout};
use tracing::{debug, error, info, warn};

use crate::config::BluetoothConfig;
use crate::storage::Storage;
use crate::websocket::{broadcast_sample, WsMessage};

// Use the protocol abstraction instead of direct ftms imports
use ftms::TreadmillData;
use protocol::{
    detect_protocol, supported_protocol_uuids, ProtocolMode, QueryType, TreadmillProtocol,
};

#[derive(Debug, Clone)]
pub enum ConnectionStatus {
    Disconnected,
    Scanning,
    Connecting,
    Connected,
    Error,
}

pub struct BluetoothManager {
    storage: Arc<Storage>,
    config: BluetoothConfig,
    status_tx: broadcast::Sender<ConnectionStatus>,
    ws_tx: broadcast::Sender<WsMessage>,
    // Track last seen cumulative values for delta calculation
    last_distance: Arc<RwLock<Option<i64>>>,
    last_calories: Arc<RwLock<Option<i64>>>,
    last_steps: Arc<RwLock<Option<i64>>>,
}

impl BluetoothManager {
    pub fn new(
        storage: Arc<Storage>,
        config: BluetoothConfig,
        ws_tx: broadcast::Sender<WsMessage>,
    ) -> (Self, broadcast::Receiver<ConnectionStatus>) {
        let (status_tx, status_rx) = broadcast::channel(16);

        (
            Self {
                storage,
                config,
                status_tx,
                ws_tx,
                last_distance: Arc::new(RwLock::new(None)),
                last_calories: Arc::new(RwLock::new(None)),
                last_steps: Arc::new(RwLock::new(None)),
            },
            status_rx,
        )
    }

    pub async fn run(&self) -> Result<()> {
        info!(
            "Starting Bluetooth manager (scan_timeout={}s, reconnect_delay={}s)",
            self.config.scan_timeout_secs, self.config.reconnect_delay_secs
        );
        info!("🎯 Simple data capture mode - no workout detection, just raw samples");

        let mut reconnect_attempts = 0u32;

        loop {
            match self.connect_and_monitor().await {
                Ok(_) => {
                    info!("Connection cycle completed normally");
                    reconnect_attempts = 0; // Reset on successful connection cycle
                }
                Err(e) => {
                    reconnect_attempts += 1;
                    error!("Connection error (attempt #{}): {}", reconnect_attempts, e);
                    let _ = self.status_tx.send(ConnectionStatus::Error);
                }
            }

            // Broadcast disconnected status before waiting
            let _ = self.status_tx.send(ConnectionStatus::Disconnected);

            // Wait before reconnecting
            info!(
                "Reconnecting in {} seconds (attempt #{})...",
                self.config.reconnect_delay_secs,
                reconnect_attempts + 1
            );
            sleep(Duration::from_secs(self.config.reconnect_delay_secs)).await;
        }
    }

    async fn connect_and_monitor(&self) -> Result<()> {
        // Get BLE adapter
        let manager = Manager::new().await?;
        let adapters = manager.adapters().await?;
        let adapter = adapters
            .into_iter()
            .next()
            .ok_or_else(|| anyhow!("No BLE adapter found"))?;

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
        let chars: Vec<Characteristic> = peripheral.characteristics().into_iter().collect();

        // Log all discovered services and characteristics for debugging
        info!("Discovered {} characteristics on treadmill", chars.len());
        for (i, char) in chars.iter().enumerate() {
            debug!(
                "  [{}] Service: {}, Characteristic: {}, Properties: {:?}",
                i, char.service_uuid, char.uuid, char.properties
            );
        }

        // Use protocol detection to find a supported protocol
        let protocol = detect_protocol(&chars).ok_or_else(|| {
            let supported = supported_protocol_uuids();
            warn!("No supported treadmill protocol found!");
            warn!("Supported protocols:");
            for (uuid, name) in &supported {
                warn!("  - {} (UUID: {})", name, uuid);
            }
            warn!("Check the characteristic list above to see what your treadmill exposes");
            anyhow!("Treadmill data characteristic not found")
        })?;

        info!(
            "Using {} protocol (UUID: {})",
            protocol.name(),
            protocol.characteristic_uuid()
        );

        // Find the characteristic for this protocol
        let treadmill_char = chars
            .iter()
            .find(|c| c.uuid == protocol.characteristic_uuid())
            .ok_or_else(|| anyhow!("Protocol characteristic not found"))?;

        // Subscribe to notifications
        peripheral.subscribe(treadmill_char).await?;
        info!("Subscribed to treadmill data notifications");

        // Send handshake commands if the protocol requires them
        let handshake_cmds = protocol.handshake_commands();
        if !handshake_cmds.is_empty() {
            info!(
                "Sending {} handshake sequence ({} commands)...",
                protocol.name(),
                handshake_cmds.len()
            );
            for (i, cmd) in handshake_cmds.iter().enumerate() {
                peripheral
                    .write(
                        treadmill_char,
                        &cmd.data,
                        btleplug::api::WriteType::WithResponse,
                    )
                    .await?;
                debug!(
                    "Sent handshake command {}/{}: {:02X?}",
                    i + 1,
                    handshake_cmds.len(),
                    cmd.data
                );
                sleep(Duration::from_millis(cmd.delay_after_ms)).await;
            }
            info!("Handshake complete");
        }

        let _ = self.status_tx.send(ConnectionStatus::Connected);

        // Monitor notifications using the protocol abstraction
        self.monitor_notifications(&peripheral, treadmill_char, protocol.as_ref())
            .await?;

        Ok(())
    }

    async fn scan_for_device(&self, adapter: &Adapter) -> Result<Peripheral> {
        adapter.start_scan(ScanFilter::default()).await?;

        // Scan for configured timeout
        let timeout = self.config.scan_timeout_secs;
        let mut discovered_devices: std::collections::HashSet<String> =
            std::collections::HashSet::new();

        for i in 0..timeout {
            sleep(Duration::from_secs(1)).await;

            let peripherals = adapter.peripherals().await?;
            for peripheral in peripherals {
                if let Ok(Some(props)) = peripheral.properties().await {
                    if let Some(name) = props.local_name {
                        // Log all discovered devices for debugging
                        if discovered_devices.insert(name.clone()) {
                            debug!(
                                "Discovered BLE device: '{}' (address: {:?})",
                                name, props.address
                            );
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
            warn!(
                "Treadmill not found. Discovered {} device(s): {:?}",
                discovered_devices.len(),
                discovered_devices.iter().collect::<Vec<_>>()
            );
            warn!("Hint: Update device_name_filter in config.toml to match your treadmill's name");
        }

        Err(anyhow!("Treadmill not found after {} seconds", timeout))
    }

    async fn monitor_notifications(
        &self,
        peripheral: &Peripheral,
        char: &Characteristic,
        protocol: &dyn TreadmillProtocol,
    ) -> Result<()> {
        let mut notification_stream = peripheral.notifications().await?;
        let mut sample_count = 0;

        // Check if this is a polling or passive protocol
        let is_polling = matches!(protocol.mode(), ProtocolMode::Polling { .. });

        // For polling protocols: track pending queries with shared queue
        let pending_queries = Arc::new(RwLock::new(std::collections::VecDeque::<QueryType>::new()));

        // For polling protocols: accumulate responses from all queries into complete samples
        let mut data_accumulator = if is_polling {
            Some(TreadmillData::default())
        } else {
            None
        };

        // Channel for poll task to signal errors back to main loop
        let (poll_error_tx, mut poll_error_rx) = mpsc::channel::<String>(1);

        // Start polling task if this is a polling protocol
        let mut poll_task: Option<tokio::task::JoinHandle<()>> = if is_polling {
            let peripheral = peripheral.clone();
            let char = char.clone();
            let pending_queries = pending_queries.clone();
            let error_tx = poll_error_tx.clone();
            let queries = protocol.polling_queries();

            // Get polling interval from protocol mode
            let query_delay = match protocol.mode() {
                ProtocolMode::Polling { interval_ms } => Duration::from_millis(interval_ms),
                _ => Duration::from_millis(300), // Fallback
            };

            // We need to get the commands upfront since protocol is not Send
            let query_commands: Vec<(QueryType, Vec<u8>)> = queries
                .iter()
                .filter_map(|q| protocol.query_command(*q).map(|cmd| (*q, cmd)))
                .collect();

            Some(tokio::spawn(async move {
                loop {
                    for (query, cmd) in &query_commands {
                        if let Err(e) = peripheral
                            .write(&char, cmd, btleplug::api::WriteType::WithResponse)
                            .await
                        {
                            let error_msg = format!("Failed to write query {:?}: {}", query, e);
                            error!("{}", error_msg);
                            let _ = error_tx.send(error_msg).await;
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

                        debug!("Sent query: {:?}", query);
                        tokio::time::sleep(query_delay).await;
                    }
                }
            }))
        } else {
            None
        };

        // Drop our copy of the sender so poll_error_rx will close when poll task finishes
        drop(poll_error_tx);

        info!("📊 Capturing raw samples... (no workout detection)");

        // Timeout for receiving notifications - if no data for 30 seconds, consider connection lost
        let notification_timeout = Duration::from_secs(30);

        loop {
            // Use select to handle multiple event sources
            let notification = tokio::select! {
                // Check for poll task errors (polling protocols only)
                Some(error_msg) = poll_error_rx.recv() => {
                    warn!("Poll task reported error: {}", error_msg);
                    if let Some(task) = poll_task.take() {
                        task.abort();
                    }
                    return Err(anyhow!("Poll task failed: {}", error_msg));
                }
                // Receive notification with timeout
                result = timeout(notification_timeout, notification_stream.next()) => {
                    match result {
                        Ok(Some(notification)) => notification,
                        Ok(None) => {
                            // Stream ended
                            info!("Notification stream ended");
                            if let Some(task) = poll_task.take() {
                                task.abort();
                            }
                            return Err(anyhow!("Notification stream closed"));
                        }
                        Err(_) => {
                            // Timeout - no notifications received
                            warn!("No notifications received for {} seconds, assuming connection lost",
                                  notification_timeout.as_secs());
                            if let Some(task) = poll_task.take() {
                                task.abort();
                            }
                            return Err(anyhow!("Notification timeout - connection may be lost"));
                        }
                    }
                }
            };

            if notification.uuid != char.uuid {
                continue;
            }

            // Parse notification data using the protocol
            let data = if is_polling {
                // Dequeue the pending query
                let query = {
                    let mut queue = pending_queries.write().await;
                    queue.pop_front()
                };

                if let Some(query) = query {
                    // Parse response for this specific query
                    match protocol.parse_data(&notification.value, Some(query)) {
                        Ok(partial_data) => {
                            // Accumulate this response into the accumulator
                            if let Some(ref mut acc) = data_accumulator {
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

                                // Check if this is the last query in the cycle
                                if protocol.is_cycle_complete(query) {
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
                            debug!("Failed to parse response for {:?}: {}", query, e);
                            continue;
                        }
                    }
                } else {
                    debug!("Received data with no pending query");
                    continue;
                }
            } else {
                // Passive protocol - parse data directly
                match protocol.parse_data(&notification.value, None) {
                    Ok(data) => data,
                    Err(e) => {
                        warn!("Failed to parse {} data: {}", protocol.name(), e);
                        continue;
                    }
                }
            };

            // Record the raw sample to database (only when moving)
            if data.speed.unwrap_or(0.0) > 0.0 {
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
            }

            // Check if we're still connected
            if !peripheral.is_connected().await? {
                warn!(
                    "Lost connection to treadmill after {} samples",
                    sample_count
                );
                if let Some(task) = poll_task.take() {
                    task.abort();
                }
                return Err(anyhow!("Connection lost"));
            }
        }
    }

    async fn record_sample(&self, data: &TreadmillData) -> Result<()> {
        let timestamp = Utc::now();

        // Compute deltas from last seen values
        let (distance_delta, calories_delta, steps_delta) = {
            let mut last_distance = self.last_distance.write().await;
            let mut last_calories = self.last_calories.write().await;
            let mut last_steps = self.last_steps.write().await;

            // Convert current values to i64
            let current_distance = data.distance.map(|d| d as i64);
            let current_calories = data.total_energy.map(|e| e as i64);
            let current_steps = data.steps.map(|s| s as i64);

            // Compute distance delta
            let distance_delta = if let Some(curr) = current_distance {
                let delta = if let Some(last) = *last_distance {
                    if curr >= last {
                        // Normal increment
                        curr - last
                    } else {
                        // Reset detected - ignore this sample for delta
                        debug!("Distance reset detected: {} -> {}", last, curr);
                        0
                    }
                } else {
                    // First sample - no delta yet
                    0
                };
                *last_distance = Some(curr);
                Some(delta)
            } else {
                None
            };

            // Compute calories delta
            let calories_delta = if let Some(curr) = current_calories {
                let delta = if let Some(last) = *last_calories {
                    if curr >= last {
                        curr - last
                    } else {
                        debug!("Calories reset detected: {} -> {}", last, curr);
                        0
                    }
                } else {
                    0
                };
                *last_calories = Some(curr);
                Some(delta)
            } else {
                None
            };

            // Compute steps delta
            let steps_delta = if let Some(curr) = current_steps {
                let delta = if let Some(last) = *last_steps {
                    if curr >= last {
                        curr - last
                    } else {
                        debug!("Steps reset detected: {} -> {}", last, curr);
                        0
                    }
                } else {
                    0
                };
                *last_steps = Some(curr);
                Some(delta)
            } else {
                None
            };

            (distance_delta, calories_delta, steps_delta)
        };

        // Log deltas for debugging
        if let Some(steps) = steps_delta {
            if steps > 0 {
                debug!("Steps delta: +{}", steps);
            }
        }

        // Store both raw cumulative values (for debugging) and deltas (for queries)
        self.storage
            .add_sample(
                timestamp,
                data.speed,
                data.distance.map(|d| d as i64),
                data.total_energy.map(|e| e as i64),
                data.steps.map(|s| s as i64),
                distance_delta,
                calories_delta,
                steps_delta,
            )
            .await?;

        // Broadcast to WebSocket clients
        let sample = crate::storage::TreadmillSample {
            timestamp: timestamp.timestamp(),
            speed: data.speed,
            distance_total: data.distance.map(|d| d as i64),
            calories_total: data.total_energy.map(|e| e as i64),
            steps_total: data.steps.map(|s| s as i64),
            distance_delta,
            calories_delta,
            steps_delta,
        };
        broadcast_sample(&self.ws_tx, &sample);

        Ok(())
    }
}
