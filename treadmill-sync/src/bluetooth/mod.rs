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
    #[allow(dead_code)]
    pub elapsed_time: Option<u16>,
}

pub struct BluetoothManager {
    storage: Arc<Storage>,
    config: BluetoothConfig,
    status_tx: broadcast::Sender<ConnectionStatus>,
    current_workout_id: Arc<RwLock<Option<i64>>>,
    workout_baseline: Arc<RwLock<Option<WorkoutBaseline>>>,
}

#[derive(Debug, Clone)]
struct WorkoutBaseline {
    start_distance: Option<u32>,
    start_calories: Option<u16>,
}

impl BluetoothManager {
    pub fn new(storage: Arc<Storage>, config: BluetoothConfig) -> (Self, broadcast::Receiver<ConnectionStatus>) {
        let (status_tx, status_rx) = broadcast::channel(16);

        (Self {
            storage,
            config,
            status_tx,
            current_workout_id: Arc::new(RwLock::new(None)),
            workout_baseline: Arc::new(RwLock::new(None)),
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
        let mut workout_started = false;
        let mut sample_count = 0;
        let mut zero_speed_count = 0;
        let zero_speed_threshold = self.config.workout_end_timeout_secs;
        let mut last_distance: Option<u32> = None;
        let mut last_calories: Option<u16> = None;

        while let Some(notification) = notification_stream.next().await {
            if notification.uuid != char.uuid {
                continue;
            }

            match parse_treadmill_data(&notification.value) {
                Ok(data) => {
                    let current_speed = data.speed.unwrap_or(0.0);
                    debug!("Treadmill data: speed={:.2} m/s, incline={:.1}%, distance={:?}m, samples={}",
                           current_speed, data.incline.unwrap_or(0.0), data.distance, sample_count);

                    // Detect treadmill reset (cumulative values decreased significantly)
                    if workout_started {
                        let mut reset_detected = false;

                        if let (Some(current_distance), Some(prev_distance)) = (data.distance, last_distance) {
                            // If distance decreased by more than 10 meters, consider it a reset
                            if current_distance < prev_distance.saturating_sub(10) {
                                warn!("Treadmill reset detected: distance dropped from {}m to {}m",
                                      prev_distance, current_distance);
                                reset_detected = true;
                            }
                        }

                        if let (Some(current_calories), Some(prev_calories)) = (data.total_energy, last_calories) {
                            // If calories decreased by more than 5, consider it a reset
                            if current_calories < prev_calories.saturating_sub(5) {
                                warn!("Treadmill reset detected: calories dropped from {} to {}",
                                      prev_calories, current_calories);
                                reset_detected = true;
                            }
                        }

                        if reset_detected {
                            info!("Ending current workout due to treadmill reset (samples: {})", sample_count);

                            // End the current workout (this clears baseline too)
                            if let Err(e) = self.end_workout().await {
                                error!("Failed to end workout after reset: {}", e);
                            }

                            // Reset state
                            workout_started = false;
                            sample_count = 0;
                            zero_speed_count = 0;
                            last_distance = None;
                            last_calories = None;

                            // If treadmill is still moving, start a new workout immediately
                            if current_speed > 0.1 {
                                info!("Starting new workout after reset (speed: {:.2} m/s)", current_speed);
                                if let Err(e) = self.start_workout().await {
                                    error!("Failed to start workout after reset: {}", e);
                                    continue;
                                }
                                workout_started = true;

                                // Capture new baseline for the new workout
                                let mut baseline = self.workout_baseline.write().await;
                                *baseline = Some(WorkoutBaseline {
                                    start_distance: data.distance,
                                    start_calories: data.total_energy,
                                });
                                info!("New workout baseline after reset: distance={:?}m, calories={:?}kcal",
                                      data.distance, data.total_energy);
                            }
                        }
                    }

                    // Track last cumulative values for reset detection
                    last_distance = data.distance;
                    last_calories = data.total_energy;

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

                        // Capture baseline cumulative values on first sample
                        let mut baseline = self.workout_baseline.write().await;
                        *baseline = Some(WorkoutBaseline {
                            start_distance: data.distance,
                            start_calories: data.total_energy,
                        });
                        info!("Workout baseline: distance={:?}m, calories={:?}kcal",
                              data.distance, data.total_energy);
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
                                    last_distance = None;
                                    last_calories = None;
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
        // Check for and clean up any orphaned in-progress workouts
        if let Some(existing) = self.storage.get_current_workout().await? {
            warn!("Found existing in-progress workout {} (possible crash recovery). Marking as failed.", existing.id);
            self.storage.mark_workout_failed(existing.id, "New workout started - possible service restart").await?;
        }

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

            // Calculate deltas from workout baseline
            let baseline = self.workout_baseline.read().await;
            let (delta_distance, delta_calories) = if let Some(ref baseline) = *baseline {
                let delta_dist = match (data.distance, baseline.start_distance) {
                    (Some(curr), Some(start)) => Some(curr.saturating_sub(start) as i64),
                    _ => None,
                };
                let delta_cal = match (data.total_energy, baseline.start_calories) {
                    (Some(curr), Some(start)) => Some(curr.saturating_sub(start) as i64),
                    _ => None,
                };
                (delta_dist, delta_cal)
            } else {
                // No baseline yet - store raw values (shouldn't happen normally)
                (data.distance.map(|d| d as i64), data.total_energy.map(|e| e as i64))
            };

            self.storage.add_sample(
                workout_id,
                timestamp,
                data.speed,
                data.incline,
                delta_distance,
                data.heart_rate.map(|hr| hr as i64),
                delta_calories,
                None, // cadence not available from treadmill
            ).await?;
        }

        Ok(())
    }

    async fn end_workout(&self) -> Result<()> {
        // Get workout ID and clear state immediately (minimize lock time)
        let workout_id = {
            let mut current = self.current_workout_id.write().await;
            let id = *current;
            *current = None; // Clear immediately to allow new workouts
            id
        };

        // Clear baseline for next workout
        {
            let mut baseline = self.workout_baseline.write().await;
            *baseline = None;
        }

        if let Some(workout_id) = workout_id {
            info!("Ending workout {}", workout_id);

            // Use database aggregation instead of loading all samples (memory efficient)
            let agg = match self.storage.get_workout_aggregates(workout_id).await {
                Ok(agg) => agg,
                Err(e) => {
                    error!("Failed to get workout aggregates: {}", e);
                    self.storage.mark_workout_failed(workout_id, "Failed to compute aggregates").await?;
                    return Ok(());
                }
            };

            // Validate minimum workout requirements
            const MIN_SAMPLES: usize = 10;
            if agg.sample_count == 0 {
                warn!("No samples recorded for workout {}, deleting", workout_id);
                self.storage.delete_workout(workout_id).await?;
                return Ok(());
            }

            if agg.sample_count < MIN_SAMPLES {
                warn!("Workout {} too short: only {} samples (minimum {}). Deleting.",
                      workout_id, agg.sample_count, MIN_SAMPLES);
                self.storage.delete_workout(workout_id).await?;
                return Ok(());
            }

            // Calculate duration from timestamps
            let duration = if let (Some(first), Some(last)) = (&agg.first_timestamp, &agg.last_timestamp) {
                match (
                    chrono::DateTime::parse_from_rfc3339(first),
                    chrono::DateTime::parse_from_rfc3339(last)
                ) {
                    (Ok(first_ts), Ok(last_ts)) => (last_ts - first_ts).num_seconds(),
                    _ => {
                        error!("Failed to parse timestamps for workout {}", workout_id);
                        self.storage.mark_workout_failed(workout_id, "Invalid timestamps").await?;
                        return Ok(());
                    }
                }
            } else {
                error!("Missing timestamps for workout {}", workout_id);
                self.storage.mark_workout_failed(workout_id, "Missing timestamps").await?;
                return Ok(());
            };

            // Additional validation
            if duration < 10 {
                warn!("Workout {} too short: only {} seconds. Deleting.", workout_id, duration);
                self.storage.delete_workout(workout_id).await?;
                return Ok(());
            }

            let end_time = Utc::now();

            // Complete the workout
            if let Err(e) = self.storage.complete_workout(
                workout_id,
                end_time,
                duration,
                agg.total_distance,
                agg.avg_speed,
                agg.max_speed,
                agg.avg_incline,
                agg.max_incline,
                agg.total_calories,
                agg.avg_heart_rate,
                agg.max_heart_rate,
            ).await {
                error!("Failed to complete workout {}: {}", workout_id, e);
                self.storage.mark_workout_failed(workout_id, &format!("DB error: {}", e)).await?;
                return Ok(());
            }

            // Log success
            info!("Workout {} completed successfully:", workout_id);
            info!("  Duration: {}:{:02} ({} seconds)", duration / 60, duration % 60, duration);
            info!("  Distance: {} meters ({:.2} km)", agg.total_distance, agg.total_distance as f64 / 1000.0);
            info!("  Avg Speed: {:.2} m/s ({:.2} km/h)", agg.avg_speed, agg.avg_speed * 3.6);
            info!("  Max Speed: {:.2} m/s ({:.2} km/h)", agg.max_speed, agg.max_speed * 3.6);
            info!("  Avg Incline: {:.1}% (Max: {:.1}%)", agg.avg_incline, agg.max_incline);
            info!("  Calories: {} kcal", agg.total_calories);
            if let Some(avg_hr) = agg.avg_heart_rate {
                info!("  Heart Rate: {} avg / {} max bpm", avg_hr, agg.max_heart_rate.unwrap_or(0));
            }
            info!("  Samples: {}", agg.sample_count);
        }

        Ok(())
    }

    pub async fn get_current_metrics(&self) -> Result<Option<WorkoutMetrics>> {
        let current = self.current_workout_id.read().await;

        if let Some(workout_id) = *current {
            // Fetch only the latest sample (memory efficient)
            let last_sample = self.storage.get_latest_sample(workout_id).await?;

            if let Some(last_sample) = last_sample {
                // Calculate elapsed time from first to last sample
                let elapsed_time = if let Some(first_timestamp) = self.storage.get_first_sample_timestamp(workout_id).await? {
                    match (
                        chrono::DateTime::parse_from_rfc3339(&first_timestamp),
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
