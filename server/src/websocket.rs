use axum::{
    extract::{
        ws::{Message, WebSocket},
        State, WebSocketUpgrade,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::sync::broadcast;
use tracing::{debug, error, info, warn};

use crate::api::AppState;
use crate::storage::TreadmillSample;

/// Interval for sending heartbeat messages to keep connection alive
const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(30);

/// Message sent to WebSocket clients when a new sample arrives
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsMessage {
    /// A new sample has been added
    NewSample { sample: WsSample },
    /// Heartbeat to keep connection alive
    Heartbeat,
}

/// Simplified sample format for WebSocket
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsSample {
    pub timestamp: i64,
    pub speed: Option<f64>,
    pub distance_delta: Option<i64>,
    pub calories_delta: Option<i64>,
    pub steps_delta: Option<i64>,
}

impl From<TreadmillSample> for WsSample {
    fn from(s: TreadmillSample) -> Self {
        Self {
            timestamp: s.timestamp,
            speed: s.speed,
            distance_delta: s.distance_delta,
            calories_delta: s.calories_delta,
            steps_delta: s.steps_delta,
        }
    }
}

/// WebSocket handler
pub async fn ws_handler(ws: WebSocketUpgrade, State(state): State<AppState>) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

/// Handle a WebSocket connection
async fn handle_socket(socket: WebSocket, state: AppState) {
    info!("WebSocket client connected");

    // Subscribe to the broadcast channel
    let mut rx = state.ws_tx.subscribe();

    // Split the socket into sender and receiver
    let (mut sender, mut receiver) = socket.split();

    // Spawn a task to handle incoming messages from client
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            // Handle ping/pong to keep connection alive
            if let Message::Close(_) = msg {
                break;
            }
        }
    });

    // Spawn a task to send broadcast messages and heartbeats to client
    let mut send_task = tokio::spawn(async move {
        let mut heartbeat_interval = tokio::time::interval(HEARTBEAT_INTERVAL);

        loop {
            tokio::select! {
                // Send heartbeat at regular intervals
                _ = heartbeat_interval.tick() => {
                    let heartbeat_json = match serde_json::to_string(&WsMessage::Heartbeat) {
                        Ok(j) => j,
                        Err(e) => {
                            error!("Failed to serialize heartbeat: {}", e);
                            continue;
                        }
                    };
                    if sender.send(Message::Text(heartbeat_json)).await.is_err() {
                        debug!("Failed to send heartbeat - client likely disconnected");
                        break;
                    }
                }
                // Forward broadcast messages
                result = rx.recv() => {
                    match result {
                        Ok(msg) => {
                            let json = match serde_json::to_string(&msg) {
                                Ok(j) => j,
                                Err(e) => {
                                    error!("Failed to serialize WebSocket message: {}", e);
                                    continue;
                                }
                            };
                            if sender.send(Message::Text(json)).await.is_err() {
                                warn!("Failed to send message to WebSocket client");
                                break;
                            }
                        }
                        Err(broadcast::error::RecvError::Lagged(n)) => {
                            warn!("WebSocket client lagged behind by {} messages", n);
                            // Continue receiving - we'll just skip the lagged messages
                        }
                        Err(broadcast::error::RecvError::Closed) => {
                            info!("Broadcast channel closed");
                            break;
                        }
                    }
                }
            }
        }
    });

    // Wait for either task to finish
    tokio::select! {
        _ = &mut send_task => {
            recv_task.abort();
        }
        _ = &mut recv_task => {
            send_task.abort();
        }
    }

    info!("WebSocket client disconnected");
}

/// Broadcast a new sample to all connected WebSocket clients
pub fn broadcast_sample(tx: &broadcast::Sender<WsMessage>, sample: &TreadmillSample) {
    let ws_sample = WsSample::from(sample.clone());
    let msg = WsMessage::NewSample { sample: ws_sample };

    // Send ignores errors (no receivers is fine)
    let _ = tx.send(msg);
}
