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
use ftms::{parse_treadmill_data, TreadmillData, TREADMILL_DATA_UUID};

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub enum ConnectionStatus {
    Disconnected,
    Scanning,
    Connecting,
    Connected,
    Error(String),
}

#[derive(Debug, Clone)]
pub struct WorkoutMetrics {
    pub speed: Option<f64>,
    pub incline: Option<f64>,
    pub distance: Option<u32>,
    pub calories: Option<u16>,
    pub heart_rate: Option<u8>,
    pub elapsed_time: Option<u16>,
}

pub struct BluetoothManager {
    storage: Arc<Storage>,
    config: BluetoothConfig,
    status_tx: broadcast::Sender<ConnectionStatus>,
    current_workout_id: Arc<RwLock<Option<i64>>>,
}

impl BluetoothManager {
    pub fn new(storage: Arc<Storage>, config: BluetoothConfig) -> (Self, broadcast::Receiver<ConnectionStatus>) {
        let (status_tx, status_rx) = broadcast::channel(16);

        (Self {
            storage,
            config,
            status_tx,
            current_workout_id: Arc::new(RwLock::new(None)),
        }, status_rx)
    }

    pub async fn run(&self) -> Result<()> {
        info!("Starting Bluetooth manager (scan_timeout={}s, workout_end_timeout={}s, reconnect_delay={}s)",
              self.config.scan_timeout_secs, self.config.workout_end_timeout_secs, self.config.reconnect_delay_secs);

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

        let treadmill_char = chars
            .iter()
            .find(|c| c.uuid == TREADMILL_DATA_UUID)
            .ok_or_else(|| anyhow!("Treadmill data characteristic not found"))?;

        // Subscribe to notifications
        peripheral.subscribe(treadmill_char).await?;
        info!("Subscribed to treadmill data notifications");

        let _ = self.status_tx.send(ConnectionStatus::Connected);

        // Monitor notifications
        self.monitor_notifications(&peripheral, treadmill_char).await?;

        Ok(())
    }

    async fn scan_for_device(&self, adapter: &Adapter) -> Result<Peripheral> {
        adapter.start_scan(ScanFilter::default()).await?;

        // Scan for configured timeout
        let timeout = self.config.scan_timeout_secs;
        for i in 0..timeout {
            sleep(Duration::from_secs(1)).await;

            let peripherals = adapter.peripherals().await?;
            for peripheral in peripherals {
                if let Ok(Some(props)) = peripheral.properties().await {
                    if let Some(name) = props.local_name {
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
        Err(anyhow!("Treadmill not found after {} seconds", timeout))
    }

    async fn monitor_notifications(&self, peripheral: &Peripheral, char: &Characteristic) -> Result<()> {
        let mut notification_stream = peripheral.notifications().await?;
        let mut workout_started = false;
        let mut sample_count = 0;
        let mut zero_speed_count = 0;
        let zero_speed_threshold = self.config.workout_end_timeout_secs;

        while let Some(notification) = notification_stream.next().await {
            if notification.uuid != char.uuid {
                continue;
            }

            match parse_treadmill_data(&notification.value) {
                Ok(data) => {
                    let current_speed = data.speed.unwrap_or(0.0);
                    debug!("Treadmill data: speed={:.2} m/s, incline={:.1}%, distance={:?}m, samples={}",
                           current_speed, data.incline.unwrap_or(0.0), data.distance, sample_count);

                    // Detect workout start (speed > 0)
                    if !workout_started && current_speed > 0.1 {
                        info!("Workout started! Initial speed: {:.2} m/s", current_speed);
                        workout_started = true;
                        sample_count = 0;
                        zero_speed_count = 0;

                        if let Err(e) = self.start_workout().await {
                            error!("Failed to start workout: {}", e);
                            continue;
                        }
                    }

                    // Record sample if workout is active
                    if workout_started {
                        if let Err(e) = self.record_sample(&data).await {
                            error!("Failed to record sample: {}", e);
                        } else {
                            sample_count += 1;
                        }

                        // Detect workout end (speed = 0 for sustained period)
                        if current_speed < 0.1 {
                            zero_speed_count += 1;

                            if zero_speed_count == 10 {
                                info!("Workout might be ending, waiting for confirmation... ({}/{}s)",
                                      zero_speed_count, zero_speed_threshold);
                            }

                            if zero_speed_count >= zero_speed_threshold {
                                info!("Workout ended after {} seconds of zero speed. Total samples: {}",
                                      zero_speed_count, sample_count);

                                if let Err(e) = self.end_workout().await {
                                    error!("Failed to end workout: {}", e);
                                } else {
                                    workout_started = false;
                                    sample_count = 0;
                                    zero_speed_count = 0;
                                }
                            }
                        } else {
                            // Reset counter if speed picks back up
                            if zero_speed_count > 0 {
                                debug!("Speed resumed, resetting end-workout timer");
                                zero_speed_count = 0;
                            }
                        }
                    }
                }
                Err(e) => {
                    warn!("Failed to parse treadmill data: {}", e);
                }
            }

            // Check if we're still connected
            if !peripheral.is_connected().await? {
                warn!("Lost connection to treadmill");

                // End current workout if active
                if workout_started {
                    info!("Ending workout due to connection loss (samples recorded: {})", sample_count);
                    if let Err(e) = self.end_workout().await {
                        error!("Failed to end workout after disconnection: {}", e);
                    }
                }

                return Err(anyhow!("Connection lost"));
            }
        }

        Ok(())
    }

    async fn start_workout(&self) -> Result<()> {
        let workout_uuid = uuid::Uuid::new_v4().to_string();
        let start_time = Utc::now();

        let workout_id = self.storage.create_workout(&workout_uuid, start_time).await?;

        let mut current = self.current_workout_id.write().await;
        *current = Some(workout_id);

        info!("Created workout with ID: {}", workout_id);
        Ok(())
    }

    async fn record_sample(&self, data: &TreadmillData) -> Result<()> {
        let current = self.current_workout_id.read().await;

        if let Some(workout_id) = *current {
            let timestamp = Utc::now();

            self.storage.add_sample(
                workout_id,
                timestamp,
                data.speed,
                data.incline,
                data.distance.map(|d| d as i64),
                data.heart_rate.map(|hr| hr as i64),
                data.total_energy.map(|e| e as i64),
                None, // cadence not available from treadmill
            ).await?;
        }

        Ok(())
    }

    async fn end_workout(&self) -> Result<()> {
        let mut current = self.current_workout_id.write().await;

        if let Some(workout_id) = *current {
            info!("Ending workout {}", workout_id);

            // Get all samples to compute aggregates
            let samples = self.storage.get_samples(workout_id).await?;

            if samples.is_empty() {
                warn!("No samples recorded for workout {}, discarding", workout_id);
                *current = None;
                return Ok(());
            }

            // Validate minimum workout requirements
            const MIN_SAMPLES: usize = 10; // At least 10 seconds of data
            if samples.len() < MIN_SAMPLES {
                warn!("Workout {} too short: only {} samples, minimum is {}. Discarding.",
                      workout_id, samples.len(), MIN_SAMPLES);
                *current = None;
                return Ok(());
            }

            // Compute aggregates
            let mut total_distance = 0i64;
            let mut total_calories = 0i64;
            let mut max_speed = 0.0f64;
            let mut max_incline = 0.0f64;
            let mut speed_sum = 0.0f64;
            let mut incline_sum = 0.0f64;
            let mut speed_count = 0u32;
            let mut incline_count = 0u32;
            let mut heart_rates = Vec::new();

            for sample in &samples {
                if let Some(dist) = sample.distance {
                    total_distance = total_distance.max(dist);
                }
                if let Some(cal) = sample.calories {
                    total_calories = total_calories.max(cal);
                }
                if let Some(speed) = sample.speed {
                    if speed > 0.0 {
                        max_speed = max_speed.max(speed);
                        speed_sum += speed;
                        speed_count += 1;
                    }
                }
                if let Some(incline) = sample.incline {
                    max_incline = max_incline.max(incline);
                    incline_sum += incline;
                    incline_count += 1;
                }
                if let Some(hr) = sample.heart_rate {
                    if hr > 0 {
                        heart_rates.push(hr);
                    }
                }
            }

            let avg_speed = if speed_count > 0 { speed_sum / speed_count as f64 } else { 0.0 };
            let avg_incline = if incline_count > 0 { incline_sum / incline_count as f64 } else { 0.0 };

            let avg_heart_rate = if !heart_rates.is_empty() {
                Some(heart_rates.iter().sum::<i64>() / heart_rates.len() as i64)
            } else {
                None
            };

            let max_heart_rate = heart_rates.iter().max().copied();

            // Duration from first to last sample
            let first_timestamp = chrono::DateTime::parse_from_rfc3339(&samples.first().unwrap().timestamp)?;
            let last_timestamp = chrono::DateTime::parse_from_rfc3339(&samples.last().unwrap().timestamp)?;
            let duration = (last_timestamp - first_timestamp).num_seconds();

            // Additional validation
            if duration < 10 {
                warn!("Workout {} too short: only {} seconds. Discarding.", workout_id, duration);
                *current = None;
                return Ok(());
            }

            let end_time = Utc::now();

            self.storage.complete_workout(
                workout_id,
                end_time,
                duration,
                total_distance,
                avg_speed,
                max_speed,
                avg_incline,
                max_incline,
                total_calories,
                avg_heart_rate,
                max_heart_rate,
            ).await?;

            info!("✓ Workout {} completed successfully:", workout_id);
            info!("  Duration: {}:{:02} ({} seconds)", duration / 60, duration % 60, duration);
            info!("  Distance: {} meters ({:.2} km)", total_distance, total_distance as f64 / 1000.0);
            info!("  Avg Speed: {:.2} m/s ({:.2} km/h)", avg_speed, avg_speed * 3.6);
            info!("  Max Speed: {:.2} m/s ({:.2} km/h)", max_speed, max_speed * 3.6);
            info!("  Avg Incline: {:.1}% (Max: {:.1}%)", avg_incline, max_incline);
            info!("  Calories: {} kcal", total_calories);
            if let Some(avg_hr) = avg_heart_rate {
                info!("  Heart Rate: {} avg / {} max bpm", avg_hr, max_heart_rate.unwrap_or(0));
            }
            info!("  Samples: {}", samples.len());

            *current = None;
        }

        Ok(())
    }

    pub async fn get_current_metrics(&self) -> Result<Option<WorkoutMetrics>> {
        let current = self.current_workout_id.read().await;

        if let Some(workout_id) = *current {
            let samples = self.storage.get_samples(workout_id).await?;

            if let Some(last_sample) = samples.last() {
                // Calculate elapsed time from first to last sample
                let elapsed_time = if let Some(first_sample) = samples.first() {
                    match (
                        chrono::DateTime::parse_from_rfc3339(&first_sample.timestamp),
                        chrono::DateTime::parse_from_rfc3339(&last_sample.timestamp)
                    ) {
                        (Ok(first), Ok(last)) => Some((last - first).num_seconds() as u16),
                        _ => None,
                    }
                } else {
                    None
                };

                return Ok(Some(WorkoutMetrics {
                    speed: last_sample.speed,
                    incline: last_sample.incline,
                    distance: last_sample.distance.map(|d| d as u32),
                    calories: last_sample.calories.map(|c| c as u16),
                    heart_rate: last_sample.heart_rate.map(|hr| hr as u8),
                    elapsed_time,
                }));
            }
        }

        Ok(None)
    }
}
