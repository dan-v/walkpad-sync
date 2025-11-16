# TreadmillSync

> A complete solution for tracking walking pad workouts throughout your day and syncing them to Apple Health.

**Perfect for home office desk walkers** who use their treadmill multiple times per day and want automatic, reliable workout tracking.

---

## 🎯 Overview

TreadmillSync consists of two components:

1. **Rust Server** - Always-on service that connects to your treadmill via Bluetooth and captures all workout data
2. **iOS App** - Beautiful companion app to view workouts and sync them to Apple Health

```
Walking Pad (Bluetooth)
    ↓
Rust Server (Raspberry Pi / Mac / Linux)
    ├─→ SQLite Database
    ├─→ REST API + WebSocket
    └─→ Auto-reconnection
         ↓
    iOS App
         ↓
    Apple Health
```

### Why This Architecture?

- **Server runs 24/7** - Captures every workout, even when your phone isn't nearby
- **Reliable BLE** - Dedicated hardware connection prevents drops
- **iOS app is lightweight** - Just pulls data and syncs to Health
- **Real-time updates** - See live workout metrics via WebSocket

---

## ✨ Features

### Rust Server
- ✅ **Automatic BLE connection** - Discovers and connects to treadmill when powered on
- ✅ **Auto-reconnection** - Reconnects after BLE drops or treadmill power cycles
- ✅ **Smart workout detection** - Auto-starts when you step on, auto-ends after inactivity
- ✅ **Treadmill reset detection** - Handles counter resets gracefully
- ✅ **Dual protocol support** - Standard FTMS + LifeSpan proprietary
- ✅ **Data validation** - Filters BLE glitches and impossible values
- ✅ **Delta tracking** - Prevents double-counting steps
- ✅ **REST API** - Clean HTTP endpoints for data access
- ✅ **WebSocket events** - Real-time workout updates
- ✅ **Graceful shutdown** - Saves active workouts on Ctrl+C

### iOS App
- ✅ **Live workout view** - See current speed, distance, steps, calories in real-time
- ✅ **Workout history** - Browse all completed workouts
- ✅ **Interactive charts** - Speed trends and detailed analytics
- ✅ **HealthKit integration** - Proper workout builder with samples
- ✅ **Manual sync** - Review workouts before adding to Apple Health
- ✅ **Server configuration** - Easy setup and connection testing
- ✅ **WebSocket support** - Live updates without polling
- ✅ **Modern SwiftUI** - Clean, native iOS design

---

## 🚀 Quick Start

### Prerequisites

**For Server:**
- Raspberry Pi 3/4 or Mac/Linux computer with Bluetooth LE
- FTMS-compatible treadmill (most modern Bluetooth treadmills)
- Rust 1.70+ (will install during setup)

**For iOS App:**
- iPhone running iOS 17.0+
- Xcode 16.0+ (for building)
- Apple Developer account (for HealthKit)

### Server Setup

```bash
# 1. Install system dependencies (Raspberry Pi / Linux)
sudo apt update && sudo apt upgrade -y
sudo apt install -y bluetooth bluez libbluetooth-dev libdbus-1-dev pkg-config build-essential

# 2. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# 3. Build the server
cd treadmill-sync
cargo build --release

# 4. Configure
cp config.example.toml config.toml
nano config.toml  # Edit device_name_filter for your treadmill

# 5. Run
RUST_LOG=info ./target/release/treadmill-sync
```

**Expected Output:**
```
INFO Starting Treadmill Sync Service
INFO Database initialized at ./treadmill.db
INFO Starting HTTP server on 0.0.0.0:8080
INFO Scanning for treadmill: LifeSpan
INFO Found treadmill, connecting...
INFO Connected to treadmill
```

Turn on your treadmill and start walking - you should see:
```
INFO Workout started! Initial speed: 1.34 m/s
```

### iOS App Setup

```bash
# 1. Open Xcode project
open TreadmillSync.xcodeproj

# 2. Configure signing
# - Select TreadmillSync target
# - Update Team and Bundle Identifier
# - Ensure HealthKit capability is enabled

# 3. Build and run on device
# iOS Simulator won't work - HealthKit requires a real device

# 4. Configure server connection
# - Open Settings tab
# - Enter server host (e.g., raspberrypi.local or 192.168.1.100)
# - Port: 8080
# - Test connection

# 5. Grant HealthKit permissions when prompted
```

---

## 📖 Configuration

### Server Configuration (`config.toml`)

```toml
[database]
path = "./treadmill.db"

[bluetooth]
# Filter for your treadmill's Bluetooth name
# Examples: "LifeSpan", "TR", "NordicTrack", "Peloton"
device_name_filter = "LifeSpan"

# Seconds of zero speed before ending workout
workout_end_timeout_secs = 30

# Scan timeout when searching for treadmill
scan_timeout_secs = 30

# Delay before reconnecting after disconnection
reconnect_delay_secs = 5

[server]
# Bind to all network interfaces (allows iOS app to connect)
host = "0.0.0.0"
port = 8080
```

### iOS App Configuration

Settings are stored in UserDefaults and can be configured via the Settings tab:
- **Server Host** - IP address or hostname (e.g., `192.168.1.100` or `raspberrypi.local`)
- **Server Port** - Default: `8080`
- **Use HTTPS** - Enable for secure connections (requires SSL setup on server)

---

## 🔧 Running as a System Service

### Linux / Raspberry Pi (systemd)

```bash
# 1. Create service file
sudo nano /etc/systemd/system/treadmill-sync.service
```

```ini
[Unit]
Description=TreadmillSync Server
After=bluetooth.target network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/treadmill-sync
ExecStart=/home/pi/treadmill-sync/target/release/treadmill-sync
Restart=always
RestartSec=10
Environment="RUST_LOG=info"

[Install]
WantedBy=multi-user.target
```

```bash
# 2. Enable and start
sudo systemctl daemon-reload
sudo systemctl enable treadmill-sync
sudo systemctl start treadmill-sync

# 3. Check status
sudo systemctl status treadmill-sync

# 4. View logs
sudo journalctl -u treadmill-sync -f
```

### macOS (launchd)

```bash
# 1. Create plist file
nano ~/Library/LaunchAgents/com.treadmillsync.server.plist
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.treadmillsync.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOUR_USERNAME/treadmill-sync/target/release/treadmill-sync</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/YOUR_USERNAME/treadmill-sync</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/treadmill-sync.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/treadmill-sync-error.log</string>
</dict>
</plist>
```

```bash
# 2. Load service
launchctl load ~/Library/LaunchAgents/com.treadmillsync.server.plist

# 3. Check status
launchctl list | grep treadmill
```

---

## 📡 API Reference

### Health Check
```bash
GET /api/health

Response: {"status": "ok", "server_time": "2025-11-19T12:00:00Z"}
```

### Register iOS Device
```bash
POST /api/sync/register
Content-Type: application/json

{
  "device_id": "YOUR-UUID",
  "device_name": "iPhone"
}
```

### Get Pending Workouts
```bash
GET /api/workouts/pending?device_id=YOUR-UUID&limit=10

Response: {
  "workouts": [...],
  "has_more": false
}
```

### Get Workout Samples
```bash
GET /api/workouts/{id}/samples

Response: {
  "samples": [
    {
      "timestamp": "2025-11-19T10:00:00Z",
      "speed": 1.34,
      "distance": 100,
      "calories": 10,
      "cadence": 45
    },
    ...
  ]
}
```

### Confirm Sync
```bash
POST /api/workouts/{id}/confirm_sync
Content-Type: application/json

{
  "device_id": "YOUR-UUID",
  "healthkit_uuid": "OPTIONAL-HK-UUID"
}
```

### Get Live Workout
```bash
GET /api/workouts/live

Response: {
  "workout": {...},
  "current_metrics": {
    "current_speed": 1.34,
    "distance_so_far": 1200,
    "steps_so_far": 850,
    "calories_so_far": 85
  }
}
```

### WebSocket (Real-time Events)
```bash
ws://your-server:8080/ws/live

Events:
- workout_started
- workout_sample
- workout_completed
- workout_failed
- connection_status
```

---

## 🐛 Troubleshooting

### Server Issues

**Bluetooth not connecting:**
```bash
# Check Bluetooth status
sudo systemctl status bluetooth

# Restart Bluetooth
sudo systemctl restart bluetooth

# Scan manually
sudo bluetoothctl
> scan on
# Look for your treadmill in the list
```

**Permission errors:**
```bash
# Add user to bluetooth group
sudo usermod -a -G bluetooth $USER
sudo reboot
```

**Service won't start:**
```bash
# Check logs
sudo journalctl -u treadmill-sync -n 50

# Run manually to see errors
cd ~/treadmill-sync
RUST_LOG=debug ./target/release/treadmill-sync
```

**Treadmill not found:**
- Ensure treadmill is powered on and in Bluetooth pairing mode
- Check `device_name_filter` in `config.toml` matches your treadmill's name
- Try running with `RUST_LOG=debug` to see discovered devices

### iOS App Issues

**Can't connect to server:**
- Ensure server is running: `sudo systemctl status treadmill-sync`
- Check server is accessible: `curl http://SERVER-IP:8080/api/health`
- Verify iPhone is on same network as server
- Try IP address instead of hostname
- Check firewall isn't blocking port 8080

**HealthKit permission denied:**
- Open Settings → Privacy & Security → Health → TreadmillSync
- Ensure all permissions are granted

**Duplicate workouts in Health:**
- Set TreadmillSync as #1 data source priority
- Settings → Health → Steps → Data Sources & Access → Edit
- Drag TreadmillSync to top

---

## 🗄️ Database

### Schema

**workouts**
- `id` - Primary key
- `workout_uuid` - Unique UUID
- `start_time` - ISO8601 timestamp
- `end_time` - ISO8601 timestamp (null if in progress)
- `status` - 'in_progress', 'completed', 'failed'
- `total_duration` - Seconds
- `total_distance` - Meters
- `total_steps` - Step count
- `avg_speed` - m/s
- `max_speed` - m/s
- `total_calories` - kcal

**workout_samples**
- `id` - Primary key
- `workout_id` - Foreign key to workouts
- `timestamp` - ISO8601 timestamp
- `speed` - m/s (instantaneous)
- `distance` - Meters (cumulative from workout start)
- `calories` - kcal (cumulative from workout start)
- `cadence` - Steps (cumulative from workout start)

**sync_clients**
- `id` - Primary key
- `device_id` - iOS device UUID
- `device_name` - Optional device name
- `last_synced_workout_id` - Last workout synced to this device
- `last_seen` - ISO8601 timestamp

### Inspection

```bash
# Install sqlite3
sudo apt install sqlite3

# Open database
sqlite3 treadmill.db

# View recent workouts
SELECT id, start_time, total_duration, total_distance, total_steps
FROM workouts
ORDER BY start_time DESC
LIMIT 5;

# View samples for a workout
SELECT timestamp, speed, distance, calories, cadence
FROM workout_samples
WHERE workout_id = 1
ORDER BY timestamp;
```

---

## 🏗️ Architecture Details

### Rust Server Components

```
treadmill-sync/
├── src/
│   ├── main.rs              # Entry point, service orchestration
│   ├── config.rs            # Configuration management
│   ├── api/
│   │   ├── mod.rs           # REST API endpoints
│   │   └── websocket.rs     # WebSocket event broadcasting
│   ├── bluetooth/
│   │   ├── mod.rs           # BLE manager, connection handling
│   │   └── ftms.rs          # FTMS + LifeSpan protocol parsers
│   └── storage/
│       └── mod.rs           # SQLite database operations
├── Cargo.toml
└── schema.sql               # Database schema
```

### iOS App Components

```
TreadmillSync/
├── TreadmillSyncApp.swift   # App entry point
├── Models/
│   ├── Workout.swift        # Data models
│   └── ServerConfig.swift   # Configuration
├── Services/
│   ├── APIClient.swift      # HTTP API client (actor)
│   ├── HealthKitManager.swift  # HealthKit integration
│   ├── SyncManager.swift    # Sync orchestration
│   └── WebSocketManager.swift  # Real-time updates
└── Views/
    ├── ContentView.swift         # Tab navigation
    ├── WorkoutListView.swift     # Workout list with live banner
    ├── WorkoutDetailView.swift   # Workout details + charts
    ├── LiveWorkoutDetailView.swift  # Live workout view
    ├── LiveWorkoutBanner.swift   # Live workout banner
    ├── SettingsView.swift        # Server configuration
    └── OnboardingView.swift      # First-run setup
```

---

## 🔒 Security & Privacy

### What Gets Stored

**Server (Local Only):**
- Workout data (time, distance, speed, calories, steps)
- Database is local to the server machine
- No cloud sync, no external services

**iOS App (Local Only):**
- Server connection details (host, port)
- Device UUID (generated on first launch)
- HealthKit authorization status
- Temporary workout data (cleared after sync)

**Apple Health:**
- Workout data synced from iOS app
- Stored in Apple's encrypted HealthKit database
- Synced to iCloud (user-controlled, encrypted)

### Network Security

- **Default configuration:** HTTP on local network only
- **No authentication:** API is open (acceptable for home network)
- **HTTPS support:** Available if configured with certificates
- **Binding to 0.0.0.0:** Exposes to network - use firewall if concerned

**Recommendation:** Keep server on local network only. Do not expose to internet without adding authentication.

---

## 📊 Performance

### Server (Raspberry Pi 4)
- **CPU Usage:** < 5%
- **Memory:** ~20 MB
- **Storage:** ~1 MB per hour of workout data
- **Network:** Minimal (only during iOS sync)
- **Battery:** N/A (powered device)

### iOS App
- **CPU Usage:** Minimal (polling only when active)
- **Memory:** ~30 MB
- **Battery:** Low impact (background sync disabled by default)
- **Network:** ~100 KB per workout sync

---

## 🛣️ Roadmap

### Planned Features
- [ ] Server health monitoring dashboard
- [ ] iOS home screen widget
- [ ] Daily workout consolidation
- [ ] Auto-sync at end of day
- [ ] Workout completion notifications
- [ ] Weekly/monthly stats & trends
- [ ] Data export (CSV)
- [ ] Apple Watch complications

### Potential Enhancements
- [ ] Prometheus metrics endpoint
- [ ] Grafana dashboard integration
- [ ] Multi-treadmill support
- [ ] Heart rate zones (if treadmill supports HR)
- [ ] Goals & achievements
- [ ] Siri Shortcuts

---

## 🤝 Contributing

This is a personal project, but contributions are welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly (especially BLE changes)
5. Submit a pull request

---

## 📝 License

MIT License - See LICENSE file for details

---

## 🙏 Acknowledgments

- Built with Rust, SwiftUI, and love for desk walking
- Uses [btleplug](https://github.com/deviceplug/btleplug) for Bluetooth LE
- Uses [axum](https://github.com/tokio-rs/axum) for REST API
- Uses [sqlx](https://github.com/launchbadge/sqlx) for database operations

---

**Built for desk walkers, by desk walkers** 🚶‍♂️💻
