use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::Response,
};
use futures_util::{sink::SinkExt, stream::StreamExt};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;
use tracing::{error, info};

use super::{AppState, WorkoutResponse};
use crate::storage::WorkoutSample;

// WebSocket events that can be broadcast to clients
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WorkoutEvent {
    WorkoutStarted { workout: WorkoutResponse },
    WorkoutSample { workout_id: i64, sample: WorkoutSample },
    WorkoutCompleted { workout: WorkoutResponse },
    WorkoutFailed { workout_id: i64, reason: String },
    ConnectionStatus { connected: bool },
}

// WebSocket upgrade handler
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> Response {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

// Handle individual WebSocket connection
async fn handle_socket(socket: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = socket.split();

    // Subscribe to workout events
    let mut rx = state.event_tx.subscribe();

    info!("📡 WebSocket client connected");

    // Send initial connection confirmation
    let welcome = WorkoutEvent::ConnectionStatus { connected: true };
    if let Ok(msg) = serde_json::to_string(&welcome) {
        let _ = sender.send(Message::Text(msg)).await;
    }

    // Send current live workout if any
    info!("🔍 Checking for current live workout to send to new client...");
    match state.bluetooth.get_current_metrics().await {
        Ok(Some(current_data)) => {
            info!("  Found current metrics: workout_id={:?}", current_data.workout_id);
            // Send current workout state
            if let Some(workout_id) = current_data.workout_id {
                match state.storage.get_workout(workout_id).await {
                    Ok(Some(workout)) => {
                        info!("  ✅ Found workout {}, sending WorkoutStarted event", workout_id);
                        let workout_response = WorkoutResponse::from(workout);
                        let event = WorkoutEvent::WorkoutStarted { workout: workout_response };
                        match serde_json::to_string(&event) {
                            Ok(msg) => {
                                if let Err(e) = sender.send(Message::Text(msg)).await {
                                    error!("  ❌ Failed to send WorkoutStarted: {}", e);
                                } else {
                                    info!("  📤 Sent WorkoutStarted event to client");
                                }
                            }
                            Err(e) => error!("  ❌ Failed to serialize WorkoutStarted: {}", e),
                        }
                    }
                    Ok(None) => {
                        error!("  ❌ Workout {} not found in storage", workout_id);
                    }
                    Err(e) => {
                        error!("  ❌ Failed to get workout {}: {}", workout_id, e);
                    }
                }
            } else {
                info!("  No workout_id in current metrics");
            }
        }
        Ok(None) => {
            info!("  No current workout active");
        }
        Err(e) => {
            error!("  ❌ Failed to get current metrics: {}", e);
        }
    }

    // Spawn task to handle incoming messages (for ping/pong)
    let mut send_task = tokio::spawn(async move {
        while let Ok(event) = rx.recv().await {
            // Serialize and send event
            match serde_json::to_string(&event) {
                Ok(msg) => {
                    if sender.send(Message::Text(msg)).await.is_err() {
                        // Client disconnected
                        break;
                    }
                }
                Err(e) => {
                    error!("Failed to serialize event: {}", e);
                }
            }
        }
    });

    // Handle incoming messages (mainly for ping/pong)
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                Message::Close(_) => {
                    info!("📡 WebSocket client disconnected");
                    break;
                }
                Message::Ping(_data) => {
                    // Echo back pong
                    // (sender is moved, can't respond here - axum handles this automatically)
                }
                _ => {
                    // Ignore other messages for now
                }
            }
        }
    });

    // Wait for either task to finish
    tokio::select! {
        _ = (&mut send_task) => recv_task.abort(),
        _ = (&mut recv_task) => send_task.abort(),
    }

    info!("📡 WebSocket connection closed");
}

// Helper to create broadcast channel
pub fn create_event_channel() -> broadcast::Sender<WorkoutEvent> {
    // Buffer of 100 events
    let (tx, _rx) = broadcast::channel(100);
    tx
}
