# WalkPad Sync

Sync your LifeSpan walking pad data to Apple Health.

## What It Does

- **Rust server** runs on any device with Bluetooth near your treadmill
- **Captures data** via Bluetooth from your LifeSpan treadmill (TR1200-DT3 tested)
- **iOS app** syncs daily summaries to Apple Health (steps, distance, calories, duration)

## Requirements

- LifeSpan treadmill with Bluetooth (TR1200-DT3 or similar)
- Linux device with Bluetooth (Raspberry Pi, mini PC, laptop, etc.)
- iPhone with iOS 17+
- Apple Developer account (for App Store or TestFlight distribution)

## Server Setup

```bash
cd treadmill-sync

# Copy and edit config
cp config.example.toml config.toml

# Run with Docker
docker build -t walkpadsync .
docker run -d --net=host --privileged -v $(pwd)/config.toml:/app/config.toml walkpadsync

# Or run directly (requires Rust and libdbus-1-dev)
cargo run --release
```

The server exposes a REST API on port 8080.

## iOS App

Open `TreadmillSync.xcodeproj` in Xcode, update the bundle identifier and team, then build and run.

Configure the server address in the app settings.

## API

```bash
# Health check
curl http://localhost:8080/api/health

# Get all daily summaries
curl http://localhost:8080/api/dates/summaries

# Get summary for a specific date
curl http://localhost:8080/api/dates/2025-01-15/summary
```

## License

MIT
