mod api;
mod bluetooth;
mod config;
mod storage;
mod websocket;

use anyhow::Result;
use std::sync::Arc;
use tokio::{signal, sync::broadcast};
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use api::{create_router, AppState};
use bluetooth::{BluetoothManager, ConnectionStatus};
use config::Config;
use storage::Storage;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "treadmill_sync=info,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    info!("🚀 Starting Treadmill Sync Service v2 - Raw Data Capture Mode");

    // Load configuration (file -> env vars -> defaults)
    // Environment variables override config file values
    let config = Config::load("config.toml");
    info!(
        "Configuration: database={}, port={}, device_filter={}",
        config.database.path, config.server.port, config.bluetooth.device_name_filter
    );

    // Initialize storage
    let database_url = format!("sqlite://{}", config.database.path);
    let storage = Arc::new(Storage::new(&database_url).await?);
    info!("✅ Database initialized at {}", config.database.path);

    // Create WebSocket broadcast channel (capacity 100 messages)
    let (ws_tx, _) = broadcast::channel(100);
    info!("✅ WebSocket broadcast channel created");

    // Initialize Bluetooth manager
    let (bluetooth_manager, status_rx) = BluetoothManager::new(
        Arc::clone(&storage),
        config.bluetooth.clone(),
        ws_tx.clone(),
    );
    let bluetooth_manager = Arc::new(bluetooth_manager);

    // Create shared Bluetooth status for API
    let bt_status = Arc::new(tokio::sync::RwLock::new(ConnectionStatus::Disconnected));
    let bt_status_clone = Arc::clone(&bt_status);

    // Spawn task to track Bluetooth status
    let mut status_rx_task = status_rx;
    tokio::spawn(async move {
        while let Ok(status) = status_rx_task.recv().await {
            let mut s = bt_status_clone.write().await;
            *s = status;
        }
    });

    // Start Bluetooth monitoring in background
    let bluetooth_handle = {
        let bluetooth = Arc::clone(&bluetooth_manager);
        tokio::spawn(async move {
            if let Err(e) = bluetooth.run().await {
                error!("Bluetooth manager error: {}", e);
            }
        })
    };

    // Create API router
    let app = create_router(AppState {
        storage: Arc::clone(&storage),
        ws_tx: ws_tx.clone(),
        bluetooth_status: Arc::clone(&bt_status),
    });

    // Start HTTP server
    let addr = format!("{}:{}", config.server.host, config.server.port);
    info!("🌐 Starting HTTP server on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    let server_handle = tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await
        {
            error!("Server error: {}", e);
        }
    });

    info!("✨ Treadmill Sync Service is running!");
    info!(
        "📊 Dashboard: http://{}:{}",
        config.server.host, config.server.port
    );
    info!(
        "📈 API: http://{}:{}/api/health",
        config.server.host, config.server.port
    );
    info!(
        "🔌 WebSocket: ws://{}:{}/ws/live",
        config.server.host, config.server.port
    );
    info!("💾 Database: {}", config.database.path);
    info!("⏹️  Press Ctrl+C to stop");

    // Wait for either task to complete (or Ctrl+C)
    tokio::select! {
        _ = bluetooth_handle => {
            info!("Bluetooth task completed");
        }
        _ = server_handle => {
            info!("Server task completed");
        }
        _ = signal::ctrl_c() => {
            info!("Received Ctrl+C, shutting down gracefully");
        }
    }

    info!("👋 Treadmill Sync Service stopped");
    Ok(())
}

async fn shutdown_signal() {
    if let Err(e) = signal::ctrl_c().await {
        error!("Failed to listen for shutdown signal: {}", e);
    }
}
