use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use chrono::{NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::{error, info, warn};

use crate::storage::{DailySummary, Storage, TreadmillSample};
use crate::websocket::WsMessage;

// Validation constants
const MAX_DATE_RANGE_DAYS: i64 = 365;

#[derive(Clone)]
pub struct AppState {
    pub storage: Arc<Storage>,
    pub ws_tx: broadcast::Sender<WsMessage>,
}

pub fn create_router(state: AppState) -> Router {
    Router::new()
        .route("/api/health", get(health_check))
        .route("/api/dates", get(get_activity_dates))
        .route("/api/dates/:date/summary", get(get_date_summary))
        .route("/api/dates/:date/samples", get(get_date_samples))
        .route("/api/samples", get(get_samples_by_range))
        .route("/api/stats", get(get_stats))
        .route("/ws/live", get(crate::websocket::ws_handler))
        .with_state(state)
}

// Health check endpoint
async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "server_time": Utc::now().to_rfc3339(),
    }))
}

// Get all dates with activity
#[derive(Debug, Serialize)]
struct ActivityDatesResponse {
    dates: Vec<String>,  // YYYY-MM-DD format
}

#[derive(Debug, Deserialize)]
struct TimezoneQuery {
    #[serde(default)]
    tz_offset: Option<i32>,  // Timezone offset in seconds (e.g., -28800 for PST/UTC-8)
}

async fn get_activity_dates(
    State(state): State<AppState>,
    Query(query): Query<TimezoneQuery>,
) -> Result<Json<ActivityDatesResponse>, ApiError> {
    let tz_offset = query.tz_offset.unwrap_or(0);  // Default to UTC
    info!("Getting all activity dates (tz_offset={})", tz_offset);

    let dates = state.storage.get_activity_dates(tz_offset).await?;

    Ok(Json(ActivityDatesResponse { dates }))
}

// Get daily summary for a specific date
async fn get_date_summary(
    State(state): State<AppState>,
    axum::extract::Path(date_str): axum::extract::Path<String>,
    Query(query): Query<TimezoneQuery>,
) -> Result<Json<DailySummary>, ApiError> {
    let date = validate_date(&date_str)?;
    let tz_offset = query.tz_offset.unwrap_or(0);  // Default to UTC
    info!("Getting summary for date: {} (tz_offset={})", date_str, tz_offset);

    let summary = state.storage.get_daily_summary(date, tz_offset).await?;

    match summary {
        Some(s) => Ok(Json(s)),
        None => Err(ApiError::NotFound(format!("No activity found for date: {}", date_str))),
    }
}

// Get all samples for a specific date
#[derive(Debug, Serialize)]
struct SamplesResponse {
    date: String,
    samples: Vec<SampleResponse>,
}

#[derive(Debug, Serialize)]
struct SampleResponse {
    timestamp: i64,           // Unix epoch
    speed: Option<f64>,       // m/s
    distance_total: Option<i64>,  // Cumulative (for debugging)
    calories_total: Option<i64>,  // Cumulative (for debugging)
    steps_total: Option<i64>,     // Cumulative (for debugging)
    distance_delta: Option<i64>,  // Delta since last sample (USE THIS!)
    calories_delta: Option<i64>,  // Delta since last sample (USE THIS!)
    steps_delta: Option<i64>,     // Delta since last sample (USE THIS!)
}

impl From<TreadmillSample> for SampleResponse {
    fn from(s: TreadmillSample) -> Self {
        Self {
            timestamp: s.timestamp,
            speed: s.speed,
            distance_total: s.distance_total,
            calories_total: s.calories_total,
            steps_total: s.steps_total,
            distance_delta: s.distance_delta,
            calories_delta: s.calories_delta,
            steps_delta: s.steps_delta,
        }
    }
}

async fn get_date_samples(
    State(state): State<AppState>,
    Query(query): Query<TimezoneQuery>,
    axum::extract::Path(date_str): axum::extract::Path<String>,
) -> Result<Json<SamplesResponse>, ApiError> {
    let date = validate_date(&date_str)?;
    let tz_offset = query.tz_offset.unwrap_or(0);
    info!("Getting samples for date: {} with tz_offset: {}", date_str, tz_offset);

    let samples = state.storage.get_samples_for_date(date, tz_offset).await?;

    if samples.is_empty() {
        return Err(ApiError::NotFound(format!("No samples found for date: {}", date_str)));
    }

    let samples: Vec<SampleResponse> = samples.into_iter().map(SampleResponse::from).collect();

    Ok(Json(SamplesResponse {
        date: date_str,
        samples,
    }))
}

// Get samples by date range (for bulk queries)
#[derive(Debug, Deserialize)]
struct SamplesRangeQuery {
    start_date: String,  // YYYY-MM-DD
    end_date: String,    // YYYY-MM-DD
}

async fn get_samples_by_range(
    State(state): State<AppState>,
    Query(query): Query<SamplesRangeQuery>,
) -> Result<Json<SamplesResponse>, ApiError> {
    let start_date = validate_date(&query.start_date)?;
    let end_date = validate_date(&query.end_date)?;

    // Validate range
    let days_diff = (end_date - start_date).num_days();
    if days_diff < 0 {
        return Err(ApiError::Validation(ValidationError::new("start_date must be before end_date")));
    }
    if days_diff > MAX_DATE_RANGE_DAYS {
        return Err(ApiError::Validation(ValidationError::new(
            format!("Date range too large (max {} days)", MAX_DATE_RANGE_DAYS)
        )));
    }

    info!("Getting samples from {} to {}", query.start_date, query.end_date);

    let start = start_date.and_hms_opt(0, 0, 0)
        .ok_or_else(|| ApiError::Validation(ValidationError::new("Invalid start date time")))?
        .and_utc();
    let end = end_date.and_hms_opt(23, 59, 59)
        .ok_or_else(|| ApiError::Validation(ValidationError::new("Invalid end date time")))?
        .and_utc();

    let samples = state.storage.get_samples_by_date_range(start, end).await?;
    let samples: Vec<SampleResponse> = samples.into_iter().map(SampleResponse::from).collect();

    Ok(Json(SamplesResponse {
        date: format!("{} to {}", query.start_date, query.end_date),
        samples,
    }))
}

// Get general stats
#[derive(Debug, Serialize)]
struct StatsResponse {
    total_samples: i64,
    latest_sample_time: Option<String>,
    server_time: String,
}

async fn get_stats(
    State(state): State<AppState>,
) -> Result<Json<StatsResponse>, ApiError> {
    info!("Getting stats");

    let total_samples = state.storage.get_total_sample_count().await?;
    let latest_sample = state.storage.get_latest_sample().await?;

    let latest_sample_time = latest_sample.and_then(|s| {
        chrono::DateTime::<Utc>::from_timestamp(s.timestamp, 0)
            .map(|dt| dt.to_rfc3339())
    });

    Ok(Json(StatsResponse {
        total_samples,
        latest_sample_time,
        server_time: Utc::now().to_rfc3339(),
    }))
}

// Validation helpers
fn validate_date(date_str: &str) -> Result<NaiveDate, ValidationError> {
    NaiveDate::parse_from_str(date_str, "%Y-%m-%d")
        .map_err(|_| ValidationError::new("Invalid date format (expected YYYY-MM-DD)"))
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
    NotFound(String),
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
            ApiError::NotFound(msg) => {
                warn!("Not found: {}", msg);
                (
                    StatusCode::NOT_FOUND,
                    Json(serde_json::json!({
                        "error": msg
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
