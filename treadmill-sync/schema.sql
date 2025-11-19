-- Treadmill Sync Database Schema

-- Workout sessions
CREATE TABLE IF NOT EXISTS workouts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_uuid TEXT NOT NULL UNIQUE,
    start_time TEXT NOT NULL,
    end_time TEXT,
    status TEXT NOT NULL DEFAULT 'in_progress', -- in_progress, completed, failed

    -- Aggregated metrics
    total_duration INTEGER, -- seconds
    total_distance INTEGER, -- meters
    total_steps INTEGER, -- cumulative step count
    avg_speed REAL, -- m/s
    max_speed REAL, -- m/s
    total_calories INTEGER,
    avg_heart_rate REAL, -- bpm
    max_heart_rate INTEGER, -- bpm
    avg_incline REAL, -- percentage
    max_incline REAL, -- percentage

    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Workout samples (time-series data)
CREATE TABLE IF NOT EXISTS workout_samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_id INTEGER NOT NULL,
    timestamp TEXT NOT NULL,

    -- Metrics at this point in time
    speed REAL, -- m/s
    distance INTEGER, -- cumulative meters
    calories INTEGER, -- cumulative
    cadence INTEGER, -- cumulative step count (repurposed from cadence/steps-per-minute)
    heart_rate INTEGER, -- beats per minute
    incline REAL, -- percentage

    FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE
);

-- Sync state for iOS devices
CREATE TABLE IF NOT EXISTS sync_clients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL UNIQUE,
    device_name TEXT,
    last_synced_workout_id INTEGER,
    last_seen TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (last_synced_workout_id) REFERENCES workouts(id) ON DELETE SET NULL
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_workouts_start_time ON workouts(start_time);
CREATE INDEX IF NOT EXISTS idx_workouts_status ON workouts(status);
CREATE INDEX IF NOT EXISTS idx_workout_samples_workout_id ON workout_samples(workout_id);
CREATE INDEX IF NOT EXISTS idx_workout_samples_timestamp ON workout_samples(timestamp);
CREATE INDEX IF NOT EXISTS idx_sync_clients_device_id ON sync_clients(device_id);
