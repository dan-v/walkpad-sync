# Treadmill Sync - Docker Build
#
# IMPORTANT: Bluetooth in Docker only works on Linux hosts.
# macOS Docker runs in a VM without Bluetooth access.
#
# For Linux, run with:
#   docker run --net=host --privileged \
#     -v /var/run/dbus:/var/run/dbus \
#     -v ./data:/data \
#     -e TREADMILL_DB_PATH=/data/treadmill.db \
#     treadmill-sync
#
# Or use docker-compose.yml which sets this up for you.

FROM rust:1.82 AS builder

WORKDIR /usr/src/app

# Install system dependencies for build
RUN apt-get update && apt-get install -y \
    libdbus-1-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Copy manifests
COPY Cargo.toml Cargo.lock ./

# Copy source and embedded files
COPY src ./src
COPY schema_v2.sql ./
COPY static ./static

# Build release
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libdbus-1-3 \
    ca-certificates \
    bluez \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /usr/src/app/target/release/treadmill-sync /usr/local/bin/treadmill-sync

# Create data directory
RUN mkdir -p /data

WORKDIR /data

# Environment variable defaults (can be overridden at runtime)
ENV TREADMILL_DB_PATH=/data/treadmill.db
ENV TREADMILL_HOST=0.0.0.0
ENV TREADMILL_PORT=8080
ENV TREADMILL_DEVICE_FILTER=LifeSpan

EXPOSE 8080

CMD ["treadmill-sync"]
