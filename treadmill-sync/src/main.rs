mod api;
mod bluetooth;
mod config;
mod storage;

use anyhow::Result;
use std::sync::Arc;
use tokio::signal;
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use api::{create_router, AppState};
use bluetooth::BluetoothManager;
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

    info!("Starting Treadmill Sync Service");

    // Load configuration
    let config = Config::from_file_or_default("config.toml");
    info!("Configuration loaded: database={}, port={}, device_filter={}",
          config.database.path, config.server.port, config.bluetooth.device_name_filter);

    // Save default config if it doesn't exist
    if !std::path::Path::new("config.toml").exists() {
        config.save("config.toml")?;
        info!("Created default config.toml");
    }

    // Initialize storage
    let database_url = format!("sqlite://{}", config.database.path);
    let storage = Arc::new(Storage::new(&database_url).await?);
    info!("Database initialized at {}", config.database.path);

    // Initialize Bluetooth manager
    let (bluetooth_manager, _status_rx) = BluetoothManager::new(
        Arc::clone(&storage),
        config.bluetooth.clone(),
    );
    let bluetooth_manager = Arc::new(bluetooth_manager);

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
        bluetooth: Arc::clone(&bluetooth_manager),
    });

    // Start HTTP server
    let addr = format!("{}:{}", config.server.host, config.server.port);
    info!("Starting HTTP server on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    let server_handle = tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await
        {
            error!("Server error: {}", e);
        }
    });

    info!("Treadmill Sync Service is running!");
    info!("API available at http://localhost:{}", config.server.port);
    info!("Press Ctrl+C to stop");

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

    info!("Treadmill Sync Service stopped");
    Ok(())
}

async fn shutdown_signal() {
    if let Err(e) = signal::ctrl_c().await {
        error!("Failed to listen for shutdown signal: {}", e);
    }
}
