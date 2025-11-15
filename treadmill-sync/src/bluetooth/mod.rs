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

use crate::storage::Storage;
use ftms::{parse_treadmill_data, TreadmillData, TREADMILL_DATA_UUID};

#[derive(Debug, Clone)]
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
    device_name_filter: String,
    status_tx: broadcast::Sender<ConnectionStatus>,
    current_workout_id: Arc<RwLock<Option<i64>>>,
}

impl BluetoothManager {
    pub fn new(storage: Arc<Storage>, device_name_filter: String) -> (Self, broadcast::Receiver<ConnectionStatus>) {
        let (status_tx, status_rx) = broadcast::channel(16);

        (Self {
            storage,
            device_name_filter,
            status_tx,
            current_workout_id: Arc::new(RwLock::new(None)),
        }, status_rx)
    }

    pub async fn run(&self) -> Result<()> {
        info!("Starting Bluetooth manager");

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
            info!("Waiting 5 seconds before reconnection attempt...");
            sleep(Duration::from_secs(5)).await;
        }
    }

    async fn connect_and_monitor(&self) -> Result<()> {
        // Get BLE adapter
        let manager = Manager::new().await?;
        let adapters = manager.adapters().await?;
        let adapter = adapters.into_iter().next().ok_or_else(|| anyhow!("No BLE adapter found"))?;

        // Scan for device
        info!("Scanning for treadmill: {}", self.device_name_filter);
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

        // Scan for up to 30 seconds
        for _ in 0..30 {
            sleep(Duration::from_secs(1)).await;

            let peripherals = adapter.peripherals().await?;
            for peripheral in peripherals {
                if let Ok(Some(props)) = peripheral.properties().await {
                    if let Some(name) = props.local_name {
                        if name.contains(&self.device_name_filter) {
                            adapter.stop_scan().await?;
                            return Ok(peripheral);
                        }
                    }
                }
            }
        }

        adapter.stop_scan().await?;
        Err(anyhow!("Treadmill not found after 30 seconds"))
    }

    async fn monitor_notifications(&self, peripheral: &Peripheral, char: &Characteristic) -> Result<()> {
        let mut notification_stream = peripheral.notifications().await?;
        let mut last_data: Option<TreadmillData> = None;
        let mut workout_started = false;
        let mut sample_count = 0;

        while let Some(notification) = notification_stream.next().await {
            if notification.uuid != char.uuid {
                continue;
            }

            match parse_treadmill_data(&notification.value) {
                Ok(data) => {
                    debug!("Treadmill data: {:?}", data);

                    // Detect workout start (speed > 0)
                    if !workout_started && data.speed.unwrap_or(0.0) > 0.0 {
                        info!("Workout started!");
                        workout_started = true;

                        if let Err(e) = self.start_workout().await {
                            error!("Failed to start workout: {}", e);
                        }
                    }

                    // Record sample if workout is active
                    if workout_started {
                        if let Err(e) = self.record_sample(&data).await {
                            error!("Failed to record sample: {}", e);
                        }
                        sample_count += 1;
                    }

                    // Detect workout end (speed = 0 for a while)
                    if workout_started && data.speed.unwrap_or(0.0) == 0.0 {
                        if let Some(last) = &last_data {
                            if last.speed.unwrap_or(0.0) > 0.0 {
                                // Speed just went to zero
                                info!("Workout might be ending, waiting for confirmation...");
                            }
                        }

                        // Wait a bit to confirm workout end
                        // We'll check after a few more zero-speed samples
                        // For now, let's end the workout after 10 seconds of zero speed
                        // This will be improved with a proper state machine
                    }

                    last_data = Some(data);
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
                warn!("No samples recorded for workout");
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
                    max_speed = max_speed.max(speed);
                    speed_sum += speed;
                    speed_count += 1;
                }
                if let Some(incline) = sample.incline {
                    max_incline = max_incline.max(incline);
                    incline_sum += incline;
                    incline_count += 1;
                }
                if let Some(hr) = sample.heart_rate {
                    heart_rates.push(hr);
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

            info!("Workout completed: {} samples, {} meters, {} seconds",
                  samples.len(), total_distance, duration);

            *current = None;
        }

        Ok(())
    }

    pub async fn get_current_metrics(&self) -> Result<Option<WorkoutMetrics>> {
        let current = self.current_workout_id.read().await;

        if let Some(workout_id) = *current {
            let samples = self.storage.get_samples(workout_id).await?;

            if let Some(last_sample) = samples.last() {
                return Ok(Some(WorkoutMetrics {
                    speed: last_sample.speed,
                    incline: last_sample.incline,
                    distance: last_sample.distance.map(|d| d as u32),
                    calories: last_sample.calories.map(|c| c as u16),
                    heart_rate: last_sample.heart_rate.map(|hr| hr as u8),
                    elapsed_time: None, // Could compute from timestamp
                }));
            }
        }

        Ok(None)
    }
}
