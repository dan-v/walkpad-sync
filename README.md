# Treadmill Sync

Captures raw data from your treadmill via Bluetooth and visualizes it in Grafana.

## Quick Start

```bash
docker-compose up
```

That's it! Open http://localhost:3000 to see your Grafana dashboard (admin/admin).

## What You Get

- **Rust server** capturing BLE treadmill data → SQLite
- **Grafana** with pre-configured dashboards showing:
  - Steps per day
  - Distance per day
  - Calories per day
  - Active time per day

## API

The Rust server exposes a REST API on port 8080:

```bash
# Get all dates with activity
curl http://localhost:8080/api/dates

# Get summary for a date
curl http://localhost:8080/api/dates/2025-03-21/summary

# Get raw samples for a date
curl http://localhost:8080/api/dates/2025-03-21/samples

# Mark date as synced to Apple Health
curl -X POST http://localhost:8080/api/dates/2025-03-21/sync
```

## Configuration

Edit `treadmill-sync/config.toml` to change your treadmill's name:

```toml
[bluetooth]
device_name_filter = "LifeSpan"  # Change to your treadmill's name
```

## Data

All data is stored in `./data/treadmill.db` (SQLite). Grafana reads from this same database.

## iOS App (TODO)

The iOS app needs to be updated to use the new date-based API. Currently it still uses the old workout-based API.

## Architecture

- **v1 (old)**: Server detects workouts, iOS syncs workouts → Complex, inflexible
- **v2 (new)**: Server captures raw samples, you decide what's a workout → Simple, flexible

The database now just stores raw samples with timestamps. No workout detection, no complex state management. Just reliable data capture.

## Migration from v1

If you have existing v1 data:

```bash
sqlite3 data/treadmill.db < treadmill-sync/migrate_to_v2.sql
```

Or just start fresh (delete `data/treadmill.db` and restart).

## Troubleshooting

### Server won't connect to treadmill
```bash
# Check logs
docker-compose logs treadmill-sync

# Check Bluetooth
docker-compose exec treadmill-sync hciconfig
```

### Grafana shows no data
- Make sure you have some treadmill data first (walk on it!)
- Check the time range in Grafana (top right)
- Verify database exists: `ls -la data/treadmill.db`
