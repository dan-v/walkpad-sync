# Database Migrations

This directory contains database migration scripts for updating existing installations.

## How to Run Migrations

### Option 1: Using sqlite3 command line

```bash
# Navigate to the directory containing your database
cd /path/to/treadmill-sync

# Run the migration
sqlite3 treadmill.db < migrations/001_add_heart_rate_incline.sql

# Verify migration was successful
sqlite3 treadmill.db "PRAGMA table_info(workout_samples);"
sqlite3 treadmill.db "PRAGMA table_info(workouts);"
```

### Option 2: Automatic migration on next start

The server will automatically detect and apply missing columns when it starts. However, for best results, it's recommended to run migrations manually.

## Migration List

- **001_add_heart_rate_incline.sql** - Adds heart rate and incline tracking to workout samples and aggregate statistics to workouts table.

## Notes

- Always backup your database before running migrations: `cp treadmill.db treadmill.db.backup`
- Migrations are idempotent and safe to run multiple times
- The SQLite `ALTER TABLE` command is used, which is non-destructive
