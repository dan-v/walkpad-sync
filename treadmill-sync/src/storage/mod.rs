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
    pub timestamp: i64,              // Unix epoch seconds
    pub speed: Option<f64>,          // m/s
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
    pub date: String, // YYYY-MM-DD
    pub total_samples: i64,
    pub duration_seconds: i64,
    pub distance_meters: i64,
    pub calories: i64,
    pub steps: i64,
    pub avg_speed: f64, // m/s
    pub max_speed: f64,
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
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
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
             ORDER BY timestamp ASC",
        )
        .bind(start_unix)
        .bind(end_unix)
        .fetch_all(&self.pool)
        .await?;

        Ok(samples)
    }

    /// Get samples for a specific date in the user's local timezone
    ///
    /// # Arguments
    /// * `date` - The date in the user's local timezone
    /// * `tz_offset_seconds` - Timezone offset from UTC in seconds (e.g., PST = -28800 for UTC-8)
    pub async fn get_samples_for_date(
        &self,
        date: NaiveDate,
        tz_offset_seconds: i32,
    ) -> Result<Vec<TreadmillSample>> {
        // Convert local date to UTC timestamp range (same logic as get_daily_summary)
        let start_local = date
            .and_hms_opt(0, 0, 0)
            .ok_or_else(|| anyhow::anyhow!("Invalid date time"))?;
        let end_local = start_local + chrono::Duration::days(1);

        // Apply timezone offset to get UTC timestamps
        let start_unix = start_local.and_utc().timestamp() - tz_offset_seconds as i64;
        let end_unix = end_local.and_utc().timestamp() - tz_offset_seconds as i64;

        // Convert back to DateTime<Utc>
        let start = DateTime::from_timestamp(start_unix, 0)
            .ok_or_else(|| anyhow::anyhow!("Invalid start timestamp"))?;
        let end = DateTime::from_timestamp(end_unix, 0)
            .ok_or_else(|| anyhow::anyhow!("Invalid end timestamp"))?;

        self.get_samples_by_date_range(start, end).await
    }

    /// Get a daily summary for a specific date
    /// Uses delta columns for accurate summation regardless of resets
    ///
    /// # Arguments
    /// * `date` - The date in the user's local timezone
    /// * `tz_offset_seconds` - Timezone offset from UTC in seconds (e.g., PST = -28800 for UTC-8)
    pub async fn get_daily_summary(
        &self,
        date: NaiveDate,
        tz_offset_seconds: i32,
    ) -> Result<Option<DailySummary>> {
        let date_str = date.format("%Y-%m-%d").to_string();

        // Convert local date to UTC timestamp range
        // e.g., 2025-11-19 00:00 PST (-8h) = 2025-11-19 08:00 UTC
        let start_local = date
            .and_hms_opt(0, 0, 0)
            .ok_or_else(|| anyhow::anyhow!("Invalid date time"))?;
        let end_local = start_local + chrono::Duration::days(1);

        // Apply timezone offset to get UTC timestamps
        let start_unix = start_local.and_utc().timestamp() - tz_offset_seconds as i64;
        let end_unix = end_local.and_utc().timestamp() - tz_offset_seconds as i64;

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
            "#,
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

        // Calculate duration as actual time elapsed (last_timestamp - first_timestamp)
        // Since we're only querying samples where speed > 0, this represents actual active time
        let duration_seconds = last_timestamp - first_timestamp;

        Ok(Some(DailySummary {
            date: date_str,
            total_samples,
            duration_seconds,
            distance_meters,
            calories,
            steps,
            avg_speed,
            max_speed,
        }))
    }

    /// Get all dates that have activity (samples with speed > 0)
    ///
    /// # Arguments
    /// * `tz_offset_seconds` - Timezone offset from UTC in seconds (e.g., PST = -28800 for UTC-8)
    pub async fn get_activity_dates(&self, tz_offset_seconds: i32) -> Result<Vec<String>> {
        // Apply timezone offset to timestamps before extracting date
        // e.g., UTC timestamp + (-28800 seconds) = PST time
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT DATE(timestamp + ?, 'unixepoch') as date
            FROM treadmill_samples
            WHERE speed > 0.0
            ORDER BY date DESC
            "#,
        )
        .bind(tz_offset_seconds)
        .fetch_all(&self.pool)
        .await?;

        let dates = rows
            .iter()
            .map(|row| row.get::<String, _>("date"))
            .collect();
        Ok(dates)
    }

    /// Get the latest sample (for debugging/status)
    pub async fn get_latest_sample(&self) -> Result<Option<TreadmillSample>> {
        let sample = sqlx::query_as::<_, TreadmillSample>(
            "SELECT timestamp, speed, distance_total, calories_total, steps_total
             FROM treadmill_samples
             ORDER BY timestamp DESC
             LIMIT 1",
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

    /// Get all daily summaries at once (more efficient than N+1 queries)
    ///
    /// # Arguments
    /// * `tz_offset_seconds` - Timezone offset from UTC in seconds
    pub async fn get_all_daily_summaries(
        &self,
        tz_offset_seconds: i32,
    ) -> Result<Vec<DailySummary>> {
        let rows = sqlx::query(
            r#"
            SELECT
                DATE(timestamp + ?, 'unixepoch') as date,
                COUNT(*) as total_samples,
                COALESCE(SUM(distance_delta), 0) as distance_meters,
                COALESCE(SUM(calories_delta), 0) as calories,
                COALESCE(SUM(steps_delta), 0) as steps,
                COALESCE(AVG(speed), 0) as avg_speed,
                COALESCE(MAX(speed), 0) as max_speed,
                MIN(timestamp) as first_timestamp,
                MAX(timestamp) as last_timestamp
            FROM treadmill_samples
            WHERE speed > 0.0
            GROUP BY DATE(timestamp + ?, 'unixepoch')
            ORDER BY date DESC
            "#,
        )
        .bind(tz_offset_seconds)
        .bind(tz_offset_seconds)
        .fetch_all(&self.pool)
        .await?;

        let summaries = rows
            .iter()
            .map(|row| {
                let first_timestamp: i64 = row.get("first_timestamp");
                let last_timestamp: i64 = row.get("last_timestamp");
                DailySummary {
                    date: row.get("date"),
                    total_samples: row.get("total_samples"),
                    duration_seconds: last_timestamp - first_timestamp,
                    distance_meters: row.get("distance_meters"),
                    calories: row.get("calories"),
                    steps: row.get("steps"),
                    avg_speed: row.get("avg_speed"),
                    max_speed: row.get("max_speed"),
                }
            })
            .collect();

        Ok(summaries)
    }
}
