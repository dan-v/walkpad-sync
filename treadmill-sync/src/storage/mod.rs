use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{
    sqlite::{SqliteConnectOptions, SqliteJournalMode, SqliteSynchronous},
    FromRow, SqlitePool,
};
use std::str::FromStr;
use std::time::Duration;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Workout {
    pub id: i64,
    pub workout_uuid: String,
    pub start_time: String,
    pub end_time: Option<String>,
    pub status: String,
    pub total_duration: Option<i64>,
    pub total_distance: Option<i64>,
    pub avg_speed: Option<f64>,
    pub max_speed: Option<f64>,
    pub avg_incline: Option<f64>,
    pub max_incline: Option<f64>,
    pub total_calories: Option<i64>,
    pub avg_heart_rate: Option<i64>,
    pub max_heart_rate: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct WorkoutSample {
    pub id: i64,
    pub workout_id: i64,
    pub timestamp: String,
    pub speed: Option<f64>,
    pub incline: Option<f64>,
    pub distance: Option<i64>,
    pub heart_rate: Option<i64>,
    pub calories: Option<i64>,
    pub cadence: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct SyncClient {
    pub id: i64,
    pub device_id: String,
    pub device_name: Option<String>,
    pub last_synced_workout_id: Option<i64>,
    pub last_seen: String,
    pub created_at: String,
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
        let pool = SqlitePool::connect_with(options)
            .max_connections(5)
            .await?;

        // Run migrations (execute each statement separately for safety)
        let schema = include_str!("../../schema.sql");
        for statement in schema.split(';').filter(|s| !s.trim().is_empty()) {
            sqlx::query(statement).execute(&pool).await?;
        }

        Ok(Self { pool })
    }

    // Workout operations
    pub async fn create_workout(&self, workout_uuid: &str, start_time: DateTime<Utc>) -> Result<i64> {
        let start_time_str = start_time.to_rfc3339();
        let result = sqlx::query(
            "INSERT INTO workouts (workout_uuid, start_time, status) VALUES (?, ?, 'in_progress')"
        )
        .bind(workout_uuid)
        .bind(&start_time_str)
        .execute(&self.pool)
        .await?;

        Ok(result.last_insert_rowid())
    }

    pub async fn complete_workout(
        &self,
        workout_id: i64,
        end_time: DateTime<Utc>,
        total_duration: i64,
        total_distance: i64,
        avg_speed: f64,
        max_speed: f64,
        avg_incline: f64,
        max_incline: f64,
        total_calories: i64,
        avg_heart_rate: Option<i64>,
        max_heart_rate: Option<i64>,
    ) -> Result<()> {
        let end_time_str = end_time.to_rfc3339();
        let updated_at = Utc::now().to_rfc3339();

        sqlx::query(
            "UPDATE workouts SET
                end_time = ?,
                status = 'completed',
                total_duration = ?,
                total_distance = ?,
                avg_speed = ?,
                max_speed = ?,
                avg_incline = ?,
                max_incline = ?,
                total_calories = ?,
                avg_heart_rate = ?,
                max_heart_rate = ?,
                updated_at = ?
             WHERE id = ?"
        )
        .bind(&end_time_str)
        .bind(total_duration)
        .bind(total_distance)
        .bind(avg_speed)
        .bind(max_speed)
        .bind(avg_incline)
        .bind(max_incline)
        .bind(total_calories)
        .bind(avg_heart_rate)
        .bind(max_heart_rate)
        .bind(&updated_at)
        .bind(workout_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_current_workout(&self) -> Result<Option<Workout>> {
        let workout = sqlx::query_as::<_, Workout>(
            "SELECT * FROM workouts WHERE status = 'in_progress' ORDER BY start_time DESC LIMIT 1"
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(workout)
    }

    #[allow(dead_code)]
    pub async fn get_workout(&self, id: i64) -> Result<Option<Workout>> {
        let workout = sqlx::query_as::<_, Workout>("SELECT * FROM workouts WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await?;

        Ok(workout)
    }

    pub async fn get_workouts_after(&self, workout_id: i64, limit: i64) -> Result<Vec<Workout>> {
        let workouts = sqlx::query_as::<_, Workout>(
            "SELECT * FROM workouts WHERE id > ? AND status = 'completed' ORDER BY id ASC LIMIT ?"
        )
        .bind(workout_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        Ok(workouts)
    }

    // Sample operations
    pub async fn add_sample(
        &self,
        workout_id: i64,
        timestamp: DateTime<Utc>,
        speed: Option<f64>,
        incline: Option<f64>,
        distance: Option<i64>,
        heart_rate: Option<i64>,
        calories: Option<i64>,
        cadence: Option<i64>,
    ) -> Result<()> {
        let timestamp_str = timestamp.to_rfc3339();

        sqlx::query(
            "INSERT INTO workout_samples
             (workout_id, timestamp, speed, incline, distance, heart_rate, calories, cadence)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        )
        .bind(workout_id)
        .bind(&timestamp_str)
        .bind(speed)
        .bind(incline)
        .bind(distance)
        .bind(heart_rate)
        .bind(calories)
        .bind(cadence)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_samples(&self, workout_id: i64) -> Result<Vec<WorkoutSample>> {
        let samples = sqlx::query_as::<_, WorkoutSample>(
            "SELECT * FROM workout_samples WHERE workout_id = ? ORDER BY timestamp ASC"
        )
        .bind(workout_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(samples)
    }

    // Sync client operations
    pub async fn register_sync_client(&self, device_id: &str, device_name: Option<&str>) -> Result<()> {
        let last_seen = Utc::now().to_rfc3339();

        sqlx::query(
            "INSERT INTO sync_clients (device_id, device_name, last_seen)
             VALUES (?, ?, ?)
             ON CONFLICT(device_id) DO UPDATE SET
                device_name = COALESCE(excluded.device_name, device_name),
                last_seen = excluded.last_seen"
        )
        .bind(device_id)
        .bind(device_name)
        .bind(&last_seen)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_sync_client(&self, device_id: &str) -> Result<Option<SyncClient>> {
        let client = sqlx::query_as::<_, SyncClient>(
            "SELECT * FROM sync_clients WHERE device_id = ?"
        )
        .bind(device_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(client)
    }

    pub async fn update_sync_checkpoint(&self, device_id: &str, workout_id: i64) -> Result<()> {
        sqlx::query(
            "UPDATE sync_clients SET last_synced_workout_id = ? WHERE device_id = ?"
        )
        .bind(workout_id)
        .bind(device_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    // Workout cleanup operations
    pub async fn delete_workout(&self, workout_id: i64) -> Result<()> {
        sqlx::query("DELETE FROM workouts WHERE id = ?")
            .bind(workout_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    pub async fn mark_workout_failed(&self, workout_id: i64, reason: &str) -> Result<()> {
        let updated_at = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            "UPDATE workouts SET status = 'failed', updated_at = ? WHERE id = ?"
        )
        .bind(&updated_at)
        .bind(workout_id)
        .execute(&self.pool)
        .await?;

        tracing::warn!("Marked workout {} as failed: {}", workout_id, reason);
        Ok(())
    }

    // Database aggregation for performance
    pub async fn get_workout_aggregates(&self, workout_id: i64) -> Result<WorkoutAggregates> {
        let result = sqlx::query!(
            r#"
            SELECT
                COUNT(*) as "count!",
                MAX(distance) as max_distance,
                MAX(calories) as max_calories,
                AVG(CASE WHEN speed > 0 THEN speed END) as avg_speed,
                MAX(speed) as max_speed,
                AVG(incline) as avg_incline,
                MAX(incline) as max_incline,
                AVG(CASE WHEN heart_rate > 0 THEN heart_rate END) as avg_hr,
                MAX(heart_rate) as max_hr,
                MIN(timestamp) as first_timestamp,
                MAX(timestamp) as last_timestamp
            FROM workout_samples
            WHERE workout_id = ?
            "#,
            workout_id
        )
        .fetch_one(&self.pool)
        .await?;

        Ok(WorkoutAggregates {
            sample_count: result.count as usize,
            total_distance: result.max_distance.unwrap_or(0),
            total_calories: result.max_calories.unwrap_or(0),
            avg_speed: result.avg_speed.unwrap_or(0.0),
            max_speed: result.max_speed.unwrap_or(0.0),
            avg_incline: result.avg_incline.unwrap_or(0.0),
            max_incline: result.max_incline.unwrap_or(0.0),
            avg_heart_rate: result.avg_hr.map(|hr| hr as i64),
            max_heart_rate: result.max_hr,
            first_timestamp: result.first_timestamp,
            last_timestamp: result.last_timestamp,
        })
    }
}

#[derive(Debug)]
pub struct WorkoutAggregates {
    pub sample_count: usize,
    pub total_distance: i64,
    pub total_calories: i64,
    pub avg_speed: f64,
    pub max_speed: f64,
    pub avg_incline: f64,
    pub max_incline: f64,
    pub avg_heart_rate: Option<i64>,
    pub max_heart_rate: Option<i64>,
    pub first_timestamp: Option<String>,
    pub last_timestamp: Option<String>,
}
