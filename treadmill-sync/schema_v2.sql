-- Treadmill Sync Database Schema v2
-- Simplified schema focused on raw data capture

-- Core table: raw time-series samples from treadmill
CREATE TABLE IF NOT EXISTS treadmill_samples (
    timestamp INTEGER PRIMARY KEY,  -- Unix epoch (seconds)
    speed REAL,                     -- m/s (instantaneous speed)
    distance_total INTEGER,         -- cumulative meters from treadmill (raw, for debugging)
    calories_total INTEGER,         -- cumulative kcal from treadmill (raw, for debugging)
    steps_total INTEGER,            -- cumulative steps from treadmill (raw, for debugging)
    distance_delta INTEGER,         -- meters walked since last sample
    calories_delta INTEGER,         -- kcal burned since last sample
    steps_delta INTEGER             -- steps taken since last sample
);

-- Index for time-range queries (critical for Grafana and iOS app)
CREATE INDEX IF NOT EXISTS idx_timestamp ON treadmill_samples(timestamp);

-- Track what dates have been synced to Apple Health
CREATE TABLE IF NOT EXISTS health_syncs (
    sync_date TEXT PRIMARY KEY,     -- YYYY-MM-DD format
    synced_at INTEGER NOT NULL      -- Unix timestamp when sync occurred
);
