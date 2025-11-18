use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{error, info};

use crate::bluetooth::BluetoothManager;
use crate::storage::{Storage, Workout, WorkoutSample};

#[derive(Clone)]
pub struct AppState {
    pub storage: Arc<Storage>,
    pub bluetooth: Arc<BluetoothManager>,
}

pub fn create_router(state: AppState) -> Router {
    Router::new()
        .route("/api/health", get(health_check))
        .route("/api/sync/register", post(register_sync_client))
        .route("/api/workouts/pending", get(get_pending_workouts))
        .route("/api/workouts/:id/samples", get(get_workout_samples))
        .route("/api/workouts/:id/confirm_sync", post(confirm_sync))
        .route("/api/workouts/live", get(get_live_workout))
        .with_state(state)
}

// Health check endpoint
async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "server_time": Utc::now().to_rfc3339(),
    }))
}

// Register/update sync client
#[derive(Debug, Deserialize)]
struct RegisterRequest {
    device_id: String,
    device_name: Option<String>,
}

#[derive(Debug, Serialize)]
struct RegisterResponse {
    status: String,
    server_time: String,
}

async fn register_sync_client(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<Json<RegisterResponse>, ApiError> {
    info!("Registering sync client: {} ({})", req.device_id, req.device_name.as_deref().unwrap_or("unnamed"));

    state.storage
        .register_sync_client(&req.device_id, req.device_name.as_deref())
        .await?;

    Ok(Json(RegisterResponse {
        status: "ok".to_string(),
        server_time: Utc::now().to_rfc3339(),
    }))
}

// Get pending workouts for sync
#[derive(Debug, Deserialize)]
struct PendingWorkoutsQuery {
    device_id: String,
    #[serde(default = "default_limit")]
    limit: i64,
}

fn default_limit() -> i64 {
    10
}

#[derive(Debug, Serialize)]
struct PendingWorkoutsResponse {
    workouts: Vec<WorkoutResponse>,
    has_more: bool,
}

#[derive(Debug, Serialize)]
struct WorkoutResponse {
    id: i64,
    workout_uuid: String,
    start_time: String,
    end_time: Option<String>,
    total_duration: Option<i64>,
    total_distance: Option<i64>,
    avg_speed: Option<f64>,
    max_speed: Option<f64>,
    avg_incline: Option<f64>,
    max_incline: Option<f64>,
    total_calories: Option<i64>,
    avg_heart_rate: Option<i64>,
    max_heart_rate: Option<i64>,
    samples_url: String,
}

impl From<Workout> for WorkoutResponse {
    fn from(w: Workout) -> Self {
        Self {
            id: w.id,
            workout_uuid: w.workout_uuid,
            start_time: w.start_time,
            end_time: w.end_time,
            total_duration: w.total_duration,
            total_distance: w.total_distance,
            avg_speed: w.avg_speed,
            max_speed: w.max_speed,
            avg_incline: w.avg_incline,
            max_incline: w.max_incline,
            total_calories: w.total_calories,
            avg_heart_rate: w.avg_heart_rate,
            max_heart_rate: w.max_heart_rate,
            samples_url: format!("/api/workouts/{}/samples", w.id),
        }
    }
}

async fn get_pending_workouts(
    State(state): State<AppState>,
    Query(query): Query<PendingWorkoutsQuery>,
) -> Result<Json<PendingWorkoutsResponse>, ApiError> {
    info!("Getting pending workouts for device: {}", query.device_id);

    // Get or create sync client
    let client = state.storage.get_sync_client(&query.device_id).await?;

    let last_synced_id = client
        .and_then(|c| c.last_synced_workout_id)
        .unwrap_or(0);

    // Get workouts after last synced ID
    let workouts = state.storage
        .get_workouts_after(last_synced_id, query.limit + 1)
        .await?;

    let has_more = workouts.len() > query.limit as usize;
    let workouts: Vec<WorkoutResponse> = workouts
        .into_iter()
        .take(query.limit as usize)
        .map(WorkoutResponse::from)
        .collect();

    Ok(Json(PendingWorkoutsResponse {
        workouts,
        has_more,
    }))
}

// Get workout samples
#[derive(Debug, Serialize)]
struct SamplesResponse {
    samples: Vec<SampleResponse>,
}

#[derive(Debug, Serialize)]
struct SampleResponse {
    timestamp: String,
    speed: Option<f64>,
    incline: Option<f64>,
    distance: Option<i64>,
    heart_rate: Option<i64>,
    calories: Option<i64>,
    cadence: Option<i64>,
}

impl From<WorkoutSample> for SampleResponse {
    fn from(s: WorkoutSample) -> Self {
        Self {
            timestamp: s.timestamp,
            speed: s.speed,
            incline: s.incline,
            distance: s.distance,
            heart_rate: s.heart_rate,
            calories: s.calories,
            cadence: s.cadence,
        }
    }
}

async fn get_workout_samples(
    State(state): State<AppState>,
    axum::extract::Path(workout_id): axum::extract::Path<i64>,
) -> Result<Json<SamplesResponse>, ApiError> {
    info!("Getting samples for workout: {}", workout_id);

    let samples = state.storage.get_samples(workout_id).await?;
    let samples: Vec<SampleResponse> = samples.into_iter().map(SampleResponse::from).collect();

    Ok(Json(SamplesResponse { samples }))
}

// Confirm sync
#[derive(Debug, Deserialize)]
struct ConfirmSyncRequest {
    device_id: String,
    healthkit_uuid: Option<String>,
}

#[derive(Debug, Serialize)]
struct ConfirmSyncResponse {
    status: String,
}

async fn confirm_sync(
    State(state): State<AppState>,
    axum::extract::Path(workout_id): axum::extract::Path<i64>,
    Json(req): Json<ConfirmSyncRequest>,
) -> Result<Json<ConfirmSyncResponse>, ApiError> {
    if let Some(ref hk_uuid) = req.healthkit_uuid {
        info!("Confirming sync for workout {} from device {} (HealthKit UUID: {})",
              workout_id, req.device_id, hk_uuid);
    } else {
        info!("Confirming sync for workout {} from device {}", workout_id, req.device_id);
    }

    state.storage
        .update_sync_checkpoint(&req.device_id, workout_id)
        .await?;

    Ok(Json(ConfirmSyncResponse {
        status: "ok".to_string(),
    }))
}

// Get current live workout
#[derive(Debug, Serialize)]
struct LiveWorkoutResponse {
    workout: Option<WorkoutResponse>,
    current_metrics: Option<CurrentMetrics>,
}

#[derive(Debug, Serialize)]
struct CurrentMetrics {
    current_speed: Option<f64>,
    current_incline: Option<f64>,
    distance_so_far: Option<u32>,
    calories_so_far: Option<u16>,
    heart_rate: Option<u8>,
}

async fn get_live_workout(
    State(state): State<AppState>,
) -> Result<Json<LiveWorkoutResponse>, ApiError> {
    let current_workout = state.storage.get_current_workout().await?;
    let current_metrics = state.bluetooth.get_current_metrics().await?;

    let workout = current_workout.map(WorkoutResponse::from);
    let metrics = current_metrics.map(|m| CurrentMetrics {
        current_speed: m.speed,
        current_incline: m.incline,
        distance_so_far: m.distance,
        calories_so_far: m.calories,
        heart_rate: m.heart_rate,
    });

    Ok(Json(LiveWorkoutResponse {
        workout,
        current_metrics: metrics,
    }))
}

// Error handling
struct ApiError(anyhow::Error);

impl IntoResponse for ApiError {
    fn into_response(self) -> axum::response::Response {
        error!("API error: {}", self.0);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({
                "error": self.0.to_string()
            })),
        )
            .into_response()
    }
}

impl<E> From<E> for ApiError
where
    E: Into<anyhow::Error>,
{
    fn from(err: E) -> Self {
        Self(err.into())
    }
}
