# WalkPad Sync

Sync your LifeSpan treadmill data to Apple Health.

## Overview

- **Server** (`server/`) - Rust backend that connects to your treadmill via Bluetooth
- **iOS App** (`ios/`) - Syncs data to Apple Health

## Requirements

- LifeSpan treadmill with Bluetooth (TR1200-DT3 tested)
- Linux device with Bluetooth (for the server)
- iPhone with iOS 17+

## Server Setup

The server captures treadmill data via Bluetooth and exposes a REST API.

### Option 1: Run Directly

```bash
cd server
cargo build --release
./target/release/walkpad-server
```

### Option 2: Docker (Linux only)

```bash
cd server
docker-compose up -d
```

Note: Docker requires `--privileged` and host network for Bluetooth access. See `server/docker-compose.yml`.

### Option 3: Systemd Service

```bash
# Build and install
cd server
cargo build --release
sudo cp target/release/walkpad-server /usr/local/bin/

# Install service
sudo cp walkpad-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now walkpad-server
```

### Configuration

Configure via environment variables (no config file needed):

| Variable | Default | Description |
|----------|---------|-------------|
| `TREADMILL_DB_PATH` | `./treadmill.db` | SQLite database path |
| `TREADMILL_PORT` | `8080` | HTTP server port |
| `TREADMILL_HOST` | `0.0.0.0` | Bind address |
| `TREADMILL_DEVICE_FILTER` | `LifeSpan` | Bluetooth device name filter |

Or use `config.toml` (environment variables override file values).

## iOS App

Open `WalkPadSync.xcodeproj` in Xcode, update the bundle identifier and team, then build and run.

Configure the server address in the app settings.

## API

```bash
# Health check
curl http://localhost:8080/api/health

# All daily summaries
curl http://localhost:8080/api/dates/summaries

# Single day summary
curl http://localhost:8080/api/dates/2025-01-15/summary
```

## License

MIT
