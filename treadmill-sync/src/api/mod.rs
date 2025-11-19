use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{delete, get, post},
    Json, Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::{error, info, warn};

use crate::bluetooth::BluetoothManager;
use crate::storage::{Storage, Workout, WorkoutSample};

mod websocket;
pub use websocket::{create_event_channel, WorkoutEvent};

// Validation constants
const MAX_DEVICE_ID_LENGTH: usize = 128;
const MAX_DEVICE_NAME_LENGTH: usize = 256;
const MAX_LIMIT: i64 = 100;
const MAX_WORKOUT_ID: i64 = i64::MAX / 2; // Reasonable upper bound

#[derive(Clone)]
pub struct AppState {
    pub storage: Arc<Storage>,
    pub bluetooth: Arc<BluetoothManager>,
    pub event_tx: broadcast::Sender<WorkoutEvent>,
}

pub fn create_router(state: AppState) -> Router {
    Router::new()
        .route("/api/health", get(health_check))
        .route("/api/sync/register", post(register_sync_client))
        .route("/api/workouts/pending", get(get_pending_workouts))
        .route("/api/workouts/:id/samples", get(get_workout_samples))
        .route("/api/workouts/:id/confirm_sync", post(confirm_sync))
        .route("/api/workouts/:id", delete(delete_workout))
        .route("/api/workouts/live", get(get_live_workout))
        .route("/api/debug/live", get(get_debug_live))
        .route("/ws/live", get(websocket::ws_handler))
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
    // Validate inputs
    validate_device_id(&req.device_id)?;
    if let Some(ref name) = req.device_name {
        validate_device_name(name)?;
    }

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
    total_steps: Option<i64>,
    avg_speed: Option<f64>,
    max_speed: Option<f64>,
    total_calories: Option<i64>,
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
            total_steps: w.total_steps,
            avg_speed: w.avg_speed,
            max_speed: w.max_speed,
            total_calories: w.total_calories,
            samples_url: format!("/api/workouts/{}/samples", w.id),
        }
    }
}

async fn get_pending_workouts(
    State(state): State<AppState>,
    Query(query): Query<PendingWorkoutsQuery>,
) -> Result<Json<PendingWorkoutsResponse>, ApiError> {
    // Validate inputs
    validate_device_id(&query.device_id)?;
    validate_limit(query.limit)?;

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
    distance: Option<i64>,
    calories: Option<i64>,
    cadence: Option<i64>,
}

impl From<WorkoutSample> for SampleResponse {
    fn from(s: WorkoutSample) -> Self {
        Self {
            timestamp: s.timestamp,
            speed: s.speed,
            distance: s.distance,
            calories: s.calories,
            cadence: s.cadence,
        }
    }
}

async fn get_workout_samples(
    State(state): State<AppState>,
    axum::extract::Path(workout_id): axum::extract::Path<i64>,
) -> Result<Json<SamplesResponse>, ApiError> {
    // Validate input
    validate_workout_id(workout_id)?;

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
    // Validate inputs
    validate_workout_id(workout_id)?;
    validate_device_id(&req.device_id)?;

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

// Delete workout
#[derive(Debug, Serialize)]
struct DeleteWorkoutResponse {
    status: String,
}

async fn delete_workout(
    State(state): State<AppState>,
    axum::extract::Path(workout_id): axum::extract::Path<i64>,
) -> Result<Json<DeleteWorkoutResponse>, ApiError> {
    // Validate input
    validate_workout_id(workout_id)?;

    info!("Deleting workout {}", workout_id);

    state.storage.delete_workout(workout_id).await?;

    Ok(Json(DeleteWorkoutResponse {
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
    distance_so_far: Option<u32>,
    steps_so_far: Option<u16>,
    calories_so_far: Option<u16>,
}

async fn get_live_workout(
    State(state): State<AppState>,
) -> Result<Json<LiveWorkoutResponse>, ApiError> {
    let current_workout = state.storage.get_current_workout().await?;
    let current_metrics = state.bluetooth.get_current_metrics().await?;

    let workout = current_workout.map(WorkoutResponse::from);
    let metrics = current_metrics.map(|m| CurrentMetrics {
        current_speed: m.speed,
        distance_so_far: m.distance,
        steps_so_far: m.steps,
        calories_so_far: m.calories,
    });

    Ok(Json(LiveWorkoutResponse {
        workout,
        current_metrics: metrics,
    }))
}

// Debug endpoint - detailed live workout info
#[derive(Debug, Serialize)]
struct DebugLiveResponse {
    workout: Option<WorkoutResponse>,
    current_metrics: Option<CurrentMetrics>,
    recent_samples: Vec<DebugSampleResponse>,
    sample_count: usize,
}

#[derive(Debug, Serialize)]
struct DebugSampleResponse {
    timestamp: String,
    speed: Option<f64>,
    distance: Option<i64>,
    calories: Option<i64>,
    cadence: Option<i64>,
}

impl From<WorkoutSample> for DebugSampleResponse {
    fn from(s: WorkoutSample) -> Self {
        Self {
            timestamp: s.timestamp,
            speed: s.speed,
            distance: s.distance,
            calories: s.calories,
            cadence: s.cadence,
        }
    }
}

async fn get_debug_live(
    State(state): State<AppState>,
) -> Result<Json<DebugLiveResponse>, ApiError> {
    let current_workout = state.storage.get_current_workout().await?;
    let current_metrics = state.bluetooth.get_current_metrics().await?;

    let (recent_samples, sample_count) = if let Some(ref workout) = current_workout {
        // Efficiently fetch only the recent samples and count (no need to load all samples)
        let recent_samples = state.storage.get_recent_samples(workout.id, 20).await?;
        let count = state.storage.get_sample_count(workout.id).await? as usize;

        // Convert to response format
        let recent: Vec<DebugSampleResponse> = recent_samples
            .into_iter()
            .map(DebugSampleResponse::from)
            .collect();

        (recent, count)
    } else {
        (vec![], 0)
    };

    let workout = current_workout.map(WorkoutResponse::from);
    let metrics = current_metrics.map(|m| CurrentMetrics {
        current_speed: m.speed,
        distance_so_far: m.distance,
        steps_so_far: m.steps,
        calories_so_far: m.calories,
    });

    Ok(Json(DebugLiveResponse {
        workout,
        current_metrics: metrics,
        recent_samples,
        sample_count,
    }))
}

// Validation helpers
fn validate_device_id(device_id: &str) -> Result<(), ValidationError> {
    if device_id.is_empty() {
        return Err(ValidationError::new("device_id cannot be empty"));
    }

    if device_id.len() > MAX_DEVICE_ID_LENGTH {
        return Err(ValidationError::new(
            format!("device_id too long (max {} characters)", MAX_DEVICE_ID_LENGTH)
        ));
    }

    // Allow alphanumeric, hyphens, underscores, and dots (common for device IDs/UUIDs)
    if !device_id.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == '.') {
        return Err(ValidationError::new("device_id contains invalid characters"));
    }

    Ok(())
}

fn validate_device_name(name: &str) -> Result<(), ValidationError> {
    if name.len() > MAX_DEVICE_NAME_LENGTH {
        return Err(ValidationError::new(
            format!("device_name too long (max {} characters)", MAX_DEVICE_NAME_LENGTH)
        ));
    }
    Ok(())
}

fn validate_limit(limit: i64) -> Result<(), ValidationError> {
    if limit <= 0 {
        return Err(ValidationError::new("limit must be positive"));
    }

    if limit > MAX_LIMIT {
        return Err(ValidationError::new(
            format!("limit too large (max {})", MAX_LIMIT)
        ));
    }

    Ok(())
}

fn validate_workout_id(workout_id: i64) -> Result<(), ValidationError> {
    if workout_id <= 0 {
        return Err(ValidationError::new("workout_id must be positive"));
    }

    if workout_id > MAX_WORKOUT_ID {
        return Err(ValidationError::new("workout_id out of valid range"));
    }

    Ok(())
}

// Error handling
#[derive(Debug)]
struct ValidationError {
    message: String,
}

impl ValidationError {
    fn new<S: Into<String>>(message: S) -> Self {
        Self {
            message: message.into(),
        }
    }
}

#[derive(Debug)]
enum ApiError {
    Validation(ValidationError),
    Internal(anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> axum::response::Response {
        match self {
            ApiError::Validation(e) => {
                warn!("Validation error: {}", e.message);
                (
                    StatusCode::BAD_REQUEST,
                    Json(serde_json::json!({
                        "error": e.message
                    })),
                )
                    .into_response()
            }
            ApiError::Internal(e) => {
                error!("Internal server error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({
                        "error": "Internal server error"
                    })),
                )
                    .into_response()
            }
        }
    }
}

impl From<ValidationError> for ApiError {
    fn from(err: ValidationError) -> Self {
        ApiError::Validation(err)
    }
}

impl<E> From<E> for ApiError
where
    E: Into<anyhow::Error>,
{
    fn from(err: E) -> Self {
        ApiError::Internal(err.into())
    }
}
