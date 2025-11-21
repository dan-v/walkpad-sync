FROM rust:1.91 AS builder

WORKDIR /usr/src/app

# Install system dependencies for build
RUN apt-get update && apt-get install -y \
    libdbus-1-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Copy manifests
COPY Cargo.toml Cargo.lock ./

# Copy source
COPY src ./src
COPY schema_v2.sql ./

# Build release
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libdbus-1-3 \
    ca-certificates \
    curl \
    bluez \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /usr/src/app/target/release/treadmill-sync /usr/local/bin/treadmill-sync

# Create data directory
RUN mkdir -p /data

# Copy config template (will be overridden by docker-compose volume)
COPY config.example.toml /etc/treadmill-sync/config.toml

WORKDIR /data

EXPOSE 8080

CMD ["treadmill-sync"]
