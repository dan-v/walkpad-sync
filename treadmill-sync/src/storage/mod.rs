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
    pub distance_total: Option<i64>, // cumulative meters
    pub calories_total: Option<i64>, // cumulative kcal
    pub steps_total: Option<i64>,    // cumulative steps
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
    ) -> Result<()> {
        let timestamp_unix = timestamp.timestamp();

        sqlx::query(
            "INSERT OR REPLACE INTO treadmill_samples
             (timestamp, speed, distance_total, calories_total, steps_total)
             VALUES (?, ?, ?, ?, ?)"
        )
        .bind(timestamp_unix)
        .bind(speed)
        .bind(distance_total)
        .bind(calories_total)
        .bind(steps_total)
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
            "SELECT timestamp, speed, distance_total, calories_total, steps_total
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
    /// Handles mid-day resets by detecting when counters go backward and summing segments
    pub async fn get_daily_summary(&self, date: NaiveDate) -> Result<Option<DailySummary>> {
        let date_str = date.format("%Y-%m-%d").to_string();
        let start = date.and_hms_opt(0, 0, 0)
            .ok_or_else(|| anyhow::anyhow!("Invalid date time"))?
            .and_utc();
        let end = start + chrono::Duration::days(1);
        let start_unix = start.timestamp();
        let end_unix = end.timestamp();

        // Get all samples for the day, ordered by timestamp
        let samples = sqlx::query(
            r#"
            SELECT timestamp, speed, distance_total, calories_total, steps_total
            FROM treadmill_samples
            WHERE timestamp >= ? AND timestamp < ?
              AND speed > 0.0
            ORDER BY timestamp ASC
            "#
        )
        .bind(start_unix)
        .bind(end_unix)
        .fetch_all(&self.pool)
        .await?;

        if samples.is_empty() {
            return Ok(None);
        }

        // Calculate metrics handling resets (when counters go backward)
        let mut total_distance: i64 = 0;
        let mut total_calories: i64 = 0;
        let mut total_steps: i64 = 0;

        let mut segment_start_distance: Option<i64> = None;
        let mut segment_start_calories: Option<i64> = None;
        let mut segment_start_steps: Option<i64> = None;

        let mut prev_distance: Option<i64> = None;
        let mut prev_calories: Option<i64> = None;
        let mut prev_steps: Option<i64> = None;

        let mut sum_speed: f64 = 0.0;
        let mut max_speed: f64 = 0.0;
        let mut sample_count: i64 = 0;

        for row in &samples {
            let distance = row.try_get::<Option<i64>, _>("distance_total").ok().flatten();
            let calories = row.try_get::<Option<i64>, _>("calories_total").ok().flatten();
            let steps = row.try_get::<Option<i64>, _>("steps_total").ok().flatten();
            let speed = row.try_get::<Option<f64>, _>("speed").ok().flatten().unwrap_or(0.0);

            sample_count += 1;
            sum_speed += speed;
            if speed > max_speed {
                max_speed = speed;
            }

            // Handle distance with reset detection
            if let Some(d) = distance {
                if let Some(prev_d) = prev_distance {
                    // Reset detected: current value < previous value
                    if d < prev_d {
                        // Add completed segment to total
                        if let Some(start_d) = segment_start_distance {
                            total_distance += prev_d - start_d;
                        }
                        // Start new segment
                        segment_start_distance = Some(d);
                    }
                } else {
                    // First sample
                    segment_start_distance = Some(d);
                }
                prev_distance = Some(d);
            }

            // Handle calories with reset detection
            if let Some(c) = calories {
                if let Some(prev_c) = prev_calories {
                    if c < prev_c {
                        if let Some(start_c) = segment_start_calories {
                            total_calories += prev_c - start_c;
                        }
                        segment_start_calories = Some(c);
                    }
                } else {
                    segment_start_calories = Some(c);
                }
                prev_calories = Some(c);
            }

            // Handle steps with reset detection
            if let Some(s) = steps {
                if let Some(prev_s) = prev_steps {
                    if s < prev_s {
                        if let Some(start_s) = segment_start_steps {
                            total_steps += prev_s - start_s;
                        }
                        segment_start_steps = Some(s);
                    }
                } else {
                    segment_start_steps = Some(s);
                }
                prev_steps = Some(s);
            }
        }

        // Add final segment
        if let (Some(end), Some(start)) = (prev_distance, segment_start_distance) {
            total_distance += end - start;
        }
        if let (Some(end), Some(start)) = (prev_calories, segment_start_calories) {
            total_calories += end - start;
        }
        if let (Some(end), Some(start)) = (prev_steps, segment_start_steps) {
            total_steps += end - start;
        }

        // Calculate duration from first to last sample
        let first_timestamp: i64 = samples[0].get("timestamp");
        let last_timestamp: i64 = samples[samples.len() - 1].get("timestamp");
        let duration_seconds = last_timestamp - first_timestamp;

        let avg_speed = if sample_count > 0 { sum_speed / sample_count as f64 } else { 0.0 };

        // Check if this date has been synced
        let is_synced = self.is_date_synced(&date_str).await?;

        Ok(Some(DailySummary {
            date: date_str,
            total_samples: sample_count,
            duration_seconds,
            distance_meters: total_distance,
            calories: total_calories,
            steps: total_steps,
            avg_speed,
            max_speed,
            is_synced,
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
