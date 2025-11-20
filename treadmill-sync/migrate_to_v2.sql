-- Migration script from schema v1 to v2
-- This script converts the old workout-based schema to the new raw-sample schema

-- Step 1: Create new tables with v2 schema
CREATE TABLE IF NOT EXISTS treadmill_samples_new (
    timestamp INTEGER PRIMARY KEY,
    speed REAL,
    distance_total INTEGER,
    calories_total INTEGER,
    steps_total INTEGER
);

CREATE TABLE IF NOT EXISTS health_syncs (
    sync_date TEXT PRIMARY KEY,
    synced_at INTEGER NOT NULL
);

-- Step 2: Migrate data from old workout_samples to new treadmill_samples
-- This converts the workout-relative samples to absolute timestamp samples
INSERT INTO treadmill_samples_new (timestamp, speed, distance_total, calories_total, steps_total)
SELECT
    CAST(strftime('%s', ws.timestamp) AS INTEGER) as timestamp,
    ws.speed,
    ws.distance as distance_total,
    ws.calories as calories_total,
    ws.cadence as steps_total
FROM workout_samples ws
WHERE ws.timestamp IS NOT NULL
ORDER BY ws.timestamp;

-- Step 3: Backup old tables (rename them instead of dropping)
ALTER TABLE workouts RENAME TO workouts_backup_v1;
ALTER TABLE workout_samples RENAME TO workout_samples_backup_v1;
ALTER TABLE sync_clients RENAME TO sync_clients_backup_v1;

-- Step 4: Rename new table to final name
ALTER TABLE treadmill_samples_new RENAME TO treadmill_samples;

-- Step 5: Create indexes
CREATE INDEX IF NOT EXISTS idx_timestamp ON treadmill_samples(timestamp);

-- Step 6: Verify migration
-- Run this to check data was migrated:
-- SELECT COUNT(*) FROM treadmill_samples;
-- SELECT COUNT(*) FROM workout_samples_backup_v1;
-- SELECT MIN(datetime(timestamp, 'unixepoch')), MAX(datetime(timestamp, 'unixepoch')) FROM treadmill_samples;

-- After verifying, you can drop the backup tables with:
-- DROP TABLE workouts_backup_v1;
-- DROP TABLE workout_samples_backup_v1;
-- DROP TABLE sync_clients_backup_v1;
