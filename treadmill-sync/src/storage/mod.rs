use anyhow::Result;
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{
    sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous},
    FromRow, Row, SqlitePool,
};
use std::str::FromStr;
use std::time::Duration;

/// A single raw sample from the treadmill
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct TreadmillSample {
    pub timestamp: i64,           // Unix epoch seconds
    pub speed: Option<f64>,       // m/s
    pub distance_total: Option<i64>, // cumulative meters (raw, for debugging)
    pub calories_total: Option<i64>, // cumulative kcal (raw, for debugging)
    pub steps_total: Option<i64>,    // cumulative steps (raw, for debugging)
    pub distance_delta: Option<i64>, // meters since last sample
    pub calories_delta: Option<i64>, // kcal since last sample
    pub steps_delta: Option<i64>,    // steps since last sample
}

/// Summary of activity for a specific date
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailySummary {
    pub date: String,            // YYYY-MM-DD
    pub total_samples: i64,
    pub duration_seconds: i64,
    pub distance_meters: i64,
    pub calories: i64,
    pub steps: i64,
    pub avg_speed: f64,          // m/s
    pub max_speed: f64,
    pub is_synced: bool,
    pub synced_at: Option<i64>,  // Unix timestamp when synced (None if not synced)
}

/// Health sync record
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct HealthSync {
    pub sync_date: String,       // YYYY-MM-DD
    pub synced_at: i64,          // Unix timestamp
}

pub struct Storage {
    pool: SqlitePool,
}

impl Storage {
    pub async fn new(database_url: &str) -> Result<Self> {
        // Configure SQLite for optimal performance and reliability
        let options = SqliteConnectOptions::from_str(database_url)?
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal) // WAL mode for better concurrency
            .synchronous(SqliteSynchronous::Normal) // Faster but still safe
            .busy_timeout(Duration::from_secs(5)); // Wait up to 5s for locks

        // Create pool with limited connections (SQLite doesn't need many)
        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .connect_with(options)
            .await?;

        // Run migrations using the new v2 schema
        let schema = include_str!("../../schema_v2.sql");
        for statement in schema.split(';').filter(|s| !s.trim().is_empty()) {
            sqlx::query(statement).execute(&pool).await?;
        }

        Ok(Self { pool })
    }

    /// Add a raw sample from the treadmill
    pub async fn add_sample(
        &self,
        timestamp: DateTime<Utc>,
        speed: Option<f64>,
        distance_total: Option<i64>,
        calories_total: Option<i64>,
        steps_total: Option<i64>,
        distance_delta: Option<i64>,
        calories_delta: Option<i64>,
        steps_delta: Option<i64>,
    ) -> Result<()> {
        let timestamp_unix = timestamp.timestamp();

        sqlx::query(
            "INSERT OR REPLACE INTO treadmill_samples
             (timestamp, speed, distance_total, calories_total, steps_total,
              distance_delta, calories_delta, steps_delta)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(timestamp_unix)
        .bind(speed)
        .bind(distance_total)
        .bind(calories_total)
        .bind(steps_total)
        .bind(distance_delta)
        .bind(calories_delta)
        .bind(steps_delta)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Get all samples for a specific date range
    pub async fn get_samples_by_date_range(
        &self,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<TreadmillSample>> {
        let start_unix = start.timestamp();
        let end_unix = end.timestamp();

        let samples = sqlx::query_as::<_, TreadmillSample>(
            "SELECT timestamp, speed, distance_total, calories_total, steps_total,
                    distance_delta, calories_delta, steps_delta
             FROM treadmill_samples
             WHERE timestamp >= ? AND timestamp < ?
             ORDER BY timestamp ASC"
        )
        .bind(start_unix)
        .bind(end_unix)
        .fetch_all(&self.pool)
        .await?;

        Ok(samples)
    }

    /// Get samples for a specific date (convenience method)
    pub async fn get_samples_for_date(&self, date: NaiveDate) -> Result<Vec<TreadmillSample>> {
        let start = date.and_hms_opt(0, 0, 0)
            .ok_or_else(|| anyhow::anyhow!("Invalid date time"))?
            .and_utc();
        let end = start + chrono::Duration::days(1);
        self.get_samples_by_date_range(start, end).await
    }

    /// Get a daily summary for a specific date
    /// Uses delta columns for accurate summation regardless of resets
    pub async fn get_daily_summary(&self, date: NaiveDate) -> Result<Option<DailySummary>> {
        let date_str = date.format("%Y-%m-%d").to_string();
        let start = date.and_hms_opt(0, 0, 0)
            .ok_or_else(|| anyhow::anyhow!("Invalid date time"))?
            .and_utc();
        let end = start + chrono::Duration::days(1);
        let start_unix = start.timestamp();
        let end_unix = end.timestamp();

        // Get aggregated stats using delta columns
        let summary = sqlx::query(
            r#"
            SELECT
                COUNT(*) as total_samples,
                COALESCE(SUM(distance_delta), 0) as distance_meters,
                COALESCE(SUM(calories_delta), 0) as calories,
                COALESCE(SUM(steps_delta), 0) as steps,
                COALESCE(AVG(speed), 0) as avg_speed,
                COALESCE(MAX(speed), 0) as max_speed,
                MIN(timestamp) as first_timestamp,
                MAX(timestamp) as last_timestamp
            FROM treadmill_samples
            WHERE timestamp >= ? AND timestamp < ?
              AND speed > 0.0
            "#
        )
        .bind(start_unix)
        .bind(end_unix)
        .fetch_one(&self.pool)
        .await?;

        let total_samples: i64 = summary.get("total_samples");

        if total_samples == 0 {
            return Ok(None);
        }

        let distance_meters: i64 = summary.get("distance_meters");
        let calories: i64 = summary.get("calories");
        let steps: i64 = summary.get("steps");
        let avg_speed: f64 = summary.get("avg_speed");
        let max_speed: f64 = summary.get("max_speed");
        let first_timestamp: i64 = summary.get("first_timestamp");
        let last_timestamp: i64 = summary.get("last_timestamp");

        // Calculate duration based on number of active samples (speed > 0)
        // Each sample represents ~1 second of activity, which is more accurate than
        // using timestamp difference (which would count idle time if treadmill is left on)
        let duration_seconds = total_samples;

        // Check if this date has been synced and get timestamp
        let synced_at = self.get_sync_timestamp(&date_str).await?;
        let is_synced = synced_at.is_some();

        Ok(Some(DailySummary {
            date: date_str,
            total_samples,
            duration_seconds,
            distance_meters,
            calories,
            steps,
            avg_speed,
            max_speed,
            is_synced,
            synced_at,
        }))
    }

    /// Get all dates that have activity (samples with speed > 0)
    pub async fn get_activity_dates(&self) -> Result<Vec<String>> {
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT DATE(timestamp, 'unixepoch') as date
            FROM treadmill_samples
            WHERE speed > 0.0
            ORDER BY date DESC
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        let dates = rows.iter().map(|row| row.get::<String, _>("date")).collect();
        Ok(dates)
    }

    /// Mark a date as synced to Apple Health
    pub async fn mark_date_synced(&self, date: &str) -> Result<()> {
        let synced_at = Utc::now().timestamp();

        sqlx::query(
            "INSERT OR REPLACE INTO health_syncs (sync_date, synced_at) VALUES (?, ?)"
        )
        .bind(date)
        .bind(synced_at)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Check if a date has been synced to Apple Health
    pub async fn is_date_synced(&self, date: &str) -> Result<bool> {
        let row = sqlx::query("SELECT sync_date FROM health_syncs WHERE sync_date = ?")
            .bind(date)
            .fetch_optional(&self.pool)
            .await?;

        Ok(row.is_some())
    }

    /// Get sync info for a date (returns timestamp if synced)
    pub async fn get_sync_timestamp(&self, date: &str) -> Result<Option<i64>> {
        let row = sqlx::query("SELECT synced_at FROM health_syncs WHERE sync_date = ?")
            .bind(date)
            .fetch_optional(&self.pool)
            .await?;

        Ok(row.map(|r| r.get("synced_at")))
    }

    /// Get all synced dates
    pub async fn get_synced_dates(&self) -> Result<Vec<HealthSync>> {
        let syncs = sqlx::query_as::<_, HealthSync>(
            "SELECT sync_date, synced_at FROM health_syncs ORDER BY sync_date DESC"
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(syncs)
    }

    /// Get the latest sample (for debugging/status)
    pub async fn get_latest_sample(&self) -> Result<Option<TreadmillSample>> {
        let sample = sqlx::query_as::<_, TreadmillSample>(
            "SELECT timestamp, speed, distance_total, calories_total, steps_total
             FROM treadmill_samples
             ORDER BY timestamp DESC
             LIMIT 1"
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(sample)
    }

    /// Get total sample count (for debugging/stats)
    pub async fn get_total_sample_count(&self) -> Result<i64> {
        let row = sqlx::query("SELECT COUNT(*) as count FROM treadmill_samples")
            .fetch_one(&self.pool)
            .await?;

        Ok(row.get("count"))
    }
}
