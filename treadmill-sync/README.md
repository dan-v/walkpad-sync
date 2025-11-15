# Treadmill Sync Service

A rock-solid Rust service for collecting treadmill workout data via Bluetooth FTMS and syncing it to Apple Health.

## Architecture

```
Treadmill (BLE/FTMS)
    ↓
Raspberry Pi (Rust Service)
    ├─→ SQLite Database
    ├─→ REST API (port 8080)
    └─→ Auto-reconnection
         ↓
    iOS Companion App
         ↓
    Apple Health
```

## Features

- **Automatic Connection**: Discovers and connects to your treadmill when powered on
- **Auto-Reconnection**: Automatically reconnects if connection is lost
- **Complete Data Capture**: Records speed, incline, distance, calories, heart rate at 1Hz
- **SQLite Storage**: Lightweight, reliable local database
- **REST API**: Simple HTTP API for syncing data
- **Systemd Integration**: Runs as a system service, starts on boot
- **Low Resource Usage**: Perfect for Raspberry Pi

## Hardware Requirements

- Raspberry Pi 3 or newer (with Bluetooth LE support)
- FTMS-compatible treadmill (Bluetooth enabled)
- MicroSD card (8GB+)
- Power supply for Raspberry Pi

## Software Requirements

- Raspberry Pi OS (64-bit recommended)
- Rust 1.70+ (will be installed during setup)
- Bluetooth utilities

## Installation

### 1. Set up Raspberry Pi

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required system libraries
sudo apt install -y \
    bluetooth \
    bluez \
    libbluetooth-dev \
    libdbus-1-dev \
    pkg-config \
    build-essential

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### 2. Clone and Build

```bash
# Create directory
mkdir -p ~/treadmill-sync
cd ~/treadmill-sync

# Copy the project files here

# Build in release mode (optimized)
cargo build --release

# This will take 10-20 minutes on Raspberry Pi
```

### 3. Configure

Edit `config.toml` (created automatically on first run):

```toml
[database]
path = "./treadmill.db"

[bluetooth]
# Filter for your treadmill's name
# Common prefixes: "TR" (LifeSpan), "NordicTrack", "Peloton"
device_name_filter = "TR"

[server]
host = "0.0.0.0"
port = 8080
```

### 4. Test Run

```bash
# Run manually first to test
RUST_LOG=info ./target/release/treadmill-sync

# You should see:
# INFO Starting Treadmill Sync Service
# INFO Database initialized at ./treadmill.db
# INFO Starting HTTP server on 0.0.0.0:8080
# INFO Scanning for treadmill: TR
```

Turn on your treadmill and start walking. You should see:
```
INFO Found treadmill, connecting...
INFO Connected to treadmill
INFO Subscribed to treadmill data notifications
INFO Workout started!
```

### 5. Install as System Service

```bash
# Copy service file
sudo cp treadmill-sync.service /etc/systemd/system/

# Edit the service file to match your setup
sudo nano /etc/systemd/system/treadmill-sync.service
# Update User and WorkingDirectory paths

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable treadmill-sync
sudo systemctl start treadmill-sync

# Check status
sudo systemctl status treadmill-sync

# View logs
sudo journalctl -u treadmill-sync -f
```

## API Documentation

### Health Check
```bash
curl http://raspberrypi.local:8080/api/health
```

### Register iOS Device
```bash
curl -X POST http://raspberrypi.local:8080/api/sync/register \
  -H "Content-Type: application/json" \
  -d '{"device_id": "YOUR-UUID", "device_name": "iPhone"}'
```

### Get Pending Workouts
```bash
curl "http://raspberrypi.local:8080/api/workouts/pending?device_id=YOUR-UUID&limit=10"
```

### Get Workout Samples
```bash
curl http://raspberrypi.local:8080/api/workouts/1/samples
```

### Confirm Sync
```bash
curl -X POST http://raspberrypi.local:8080/api/workouts/1/confirm_sync \
  -H "Content-Type: application/json" \
  -d '{"device_id": "YOUR-UUID"}'
```

### Get Live Workout
```bash
curl http://raspberrypi.local:8080/api/workouts/live
```

### Debug Live Workout (Detailed)
```bash
curl http://raspberrypi.local:8080/api/debug/live
```

Returns detailed information including the last 20 samples and full field values.

## Debug Mode

The service includes comprehensive debug logging for troubleshooting Bluetooth data issues.

### Enable Debug Logging

```bash
# Run manually with debug logging
RUST_LOG=debug ./target/release/treadmill-sync

# Or for systemd service, edit the service file:
sudo nano /etc/systemd/system/treadmill-sync.service

# Change Environment line to:
Environment="RUST_LOG=debug"

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart treadmill-sync

# View detailed logs
sudo journalctl -u treadmill-sync -f
```

### Debug Output

With `RUST_LOG=debug`, you'll see:

**Raw Bluetooth Data:**
```
DEBUG FTMS RAW DATA (15 bytes): [86, 00, E8, 03, 64, 00, 00, 0A, 00, 64, 00, ...]
DEBUG FTMS FLAGS: 0x0086 (binary: 0000000010000110)
```

**Parsed Values:**
```
DEBUG FTMS SPEED: raw=1000 (10.00 km/h = 2.78 m/s)
DEBUG FTMS DISTANCE: 100 meters
DEBUG FTMS INCLINE: raw=25 (2.5%)
DEBUG FTMS ENERGY: 10 kcal
DEBUG FTMS HEART RATE: 145 bpm
DEBUG FTMS ELAPSED TIME: 120 seconds
```

**Summary:**
```
DEBUG FTMS PARSED SUMMARY: speed=Some(2.78) m/s, incline=Some(2.5)%,
  distance=Some(100)m, calories=Some(10)kcal, hr=Some(145)bpm,
  elapsed=Some(120)s, power=None W
```

### Debug API Endpoint

Use `/api/debug/live` to get detailed real-time data:

```bash
curl http://raspberrypi.local:8080/api/debug/live | jq
```

Response includes:
- Current workout info
- Current metrics (latest values)
- Last 20 samples with all fields
- Total sample count

Example:
```json
{
  "workout": { "id": 42, "workout_uuid": "...", ... },
  "current_metrics": {
    "current_speed": 2.78,
    "current_incline": 2.5,
    "distance_so_far": 100,
    "calories_so_far": 10,
    "heart_rate": 145
  },
  "recent_samples": [
    {
      "timestamp": "2025-11-18T10:30:00Z",
      "speed": 2.78,
      "incline": 2.5,
      "distance": 100,
      "heart_rate": 145,
      "calories": 10,
      "cadence": null
    },
    ...
  ],
  "sample_count": 187
}
```

## iOS Companion App (Next Step)

The iOS companion app will:
1. Discover the Raspberry Pi on your local network
2. Pull workout data via the REST API
3. Write workouts to Apple Health (including all samples)
4. Run background sync every hour

Sync flow:
- App generates a stable device ID on first launch
- Periodically calls `/api/workouts/pending?device_id=xxx`
- For each workout, fetches samples via `/api/workouts/{id}/samples`
- Writes to HealthKit with full sample fidelity
- Confirms sync via `/api/workouts/{id}/confirm_sync`

## Database Schema

**workouts** table:
- Stores completed workouts with aggregated metrics
- Each workout has a unique UUID

**workout_samples** table:
- Time-series data at ~1Hz resolution
- Linked to workouts via foreign key

**sync_clients** table:
- Tracks sync state per iOS device
- Stores last synced workout ID for efficiency

## Troubleshooting

### Bluetooth Connection Issues

```bash
# Check Bluetooth status
sudo systemctl status bluetooth

# Restart Bluetooth
sudo systemctl restart bluetooth

# Scan manually
sudo bluetoothctl
> scan on
```

### Service Not Starting

```bash
# Check logs
sudo journalctl -u treadmill-sync -n 50

# Run manually to see errors
cd /home/pi/treadmill-sync
RUST_LOG=debug ./target/release/treadmill-sync
```

### Permission Issues

```bash
# Add user to bluetooth group
sudo usermod -a -G bluetooth $USER

# Reboot
sudo reboot
```

## Development

### Running Tests
```bash
cargo test
```

### Watching Logs
```bash
# Service logs
sudo journalctl -u treadmill-sync -f

# Or run manually with debug logging
RUST_LOG=debug cargo run
```

### Database Inspection
```bash
# Install sqlite3
sudo apt install sqlite3

# Open database
sqlite3 treadmill.db

# Query workouts
sqlite> SELECT * FROM workouts ORDER BY start_time DESC LIMIT 5;

# Query samples
sqlite> SELECT * FROM workout_samples WHERE workout_id = 1 ORDER BY timestamp;
```

## Performance

- **CPU Usage**: <5% on Raspberry Pi 4
- **Memory**: ~20MB
- **Storage**: ~1MB per hour of workout data
- **Network**: Minimal (only during iOS sync)

## Future Enhancements

- [ ] Grafana dashboard integration
- [ ] InfluxDB export option
- [ ] Multi-device support (multiple treadmills)
- [ ] Workout session detection improvements
- [ ] mDNS/Bonjour for auto-discovery
- [ ] Web UI for configuration
- [ ] Prometheus metrics endpoint

## License

MIT
