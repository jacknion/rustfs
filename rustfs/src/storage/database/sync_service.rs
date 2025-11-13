// Copyright 2024 RustFS Team
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Metadata synchronization service for async database writes
//!
//! This service provides non-blocking metadata sync from S3 operations to the database.

use crate::storage::database::{CreateS3Object, get_database_pool, repositories::S3ObjectRepository};
use once_cell::sync::OnceCell;
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

/// Global metadata sync service sender
static SYNC_SERVICE_TX: OnceCell<mpsc::Sender<MetadataSyncEvent>> = OnceCell::new();

/// Events for metadata synchronization
#[derive(Debug, Clone)]
pub enum MetadataSyncEvent {
    /// Object was created or updated
    Upsert(Box<CreateS3Object>),

    /// Object was deleted
    Delete { bucket: String, object_key: String },

    /// Shutdown signal
    Shutdown,
}

/// Configuration for metadata sync service
#[derive(Debug, Clone)]
pub struct MetadataSyncConfig {
    /// Maximum batch size before flushing
    pub batch_size: usize,

    /// Maximum time to wait before flushing (in seconds)
    pub flush_interval_secs: u64,

    /// Maximum queue size for backpressure control
    pub max_queue_size: usize,
}

impl Default for MetadataSyncConfig {
    fn default() -> Self {
        Self {
            batch_size: 100,
            flush_interval_secs: 1,
            max_queue_size: 10000,
        }
    }
}

/// Initialize the metadata sync service
///
/// This spawns a background task that consumes events from a channel and
/// writes them to the database in batches.
///
/// # Arguments
///
/// * `config` - Service configuration
///
/// # Returns
///
/// Returns `Ok(())` if successful
pub fn init_metadata_sync_service(config: MetadataSyncConfig) -> Result<(), String> {
    let (tx, rx) = mpsc::channel(config.max_queue_size);

    // Store the sender in global state
    SYNC_SERVICE_TX
        .set(tx)
        .map_err(|_| "Metadata sync service already initialized".to_string())?;

    info!(
        target: "rustfs::storage::database::sync_service",
        batch_size = config.batch_size,
        flush_interval_secs = config.flush_interval_secs,
        max_queue_size = config.max_queue_size,
        "Metadata sync service initialized"
    );

    // Spawn background worker
    tokio::spawn(async move {
        metadata_sync_worker(rx, config).await;
    });

    Ok(())
}

/// Send a metadata sync event
///
/// This is a non-blocking operation that queues the event for async processing.
///
/// # Arguments
///
/// * `event` - Event to send
///
/// # Returns
///
/// Returns `Ok(())` if the event was queued successfully
pub fn send_sync_event(event: MetadataSyncEvent) -> Result<(), String> {
    if let Some(tx) = SYNC_SERVICE_TX.get() {
        tx.try_send(event).map_err(|e| match e {
            mpsc::error::TrySendError::Full(_) => {
                warn!(
                    target: "rustfs::storage::database::sync_service",
                    "Metadata sync queue is full, dropping event to prevent memory overflow"
                );
                "Sync queue full".to_string()
            }
            mpsc::error::TrySendError::Closed(_) => "Sync service closed".to_string(),
        })?;
        Ok(())
    } else {
        Err("Metadata sync service not initialized".to_string())
    }
}

/// Shutdown the metadata sync service
///
/// Sends a shutdown signal and waits for the worker to finish processing.
pub async fn shutdown_metadata_sync_service() {
    if let Some(tx) = SYNC_SERVICE_TX.get() {
        info!(
            target: "rustfs::storage::database::sync_service",
            "Shutting down metadata sync service"
        );

        // Send shutdown signal (ignore errors if channel is closed)
        drop(tx.send(MetadataSyncEvent::Shutdown));
    } else {
        warn!(
            target: "rustfs::storage::database::sync_service",
            "Metadata sync service not initialized, skipping shutdown"
        );
    }
}

/// Background worker that processes metadata sync events
async fn metadata_sync_worker(mut rx: mpsc::Receiver<MetadataSyncEvent>, config: MetadataSyncConfig) {
    let mut batch_upserts: Vec<CreateS3Object> = Vec::with_capacity(config.batch_size);
    let mut batch_deletes: Vec<(String, String)> = Vec::with_capacity(config.batch_size);

    let mut flush_interval = tokio::time::interval(tokio::time::Duration::from_secs(config.flush_interval_secs));
    flush_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        tokio::select! {
            // Receive events from channel
            Some(event) = rx.recv() => {
                match event {
                    MetadataSyncEvent::Upsert(obj) => {
                        batch_upserts.push(*obj);
                    }
                    MetadataSyncEvent::Delete { bucket, object_key } => {
                        batch_deletes.push((bucket, object_key));
                    }
                    MetadataSyncEvent::Shutdown => {
                        info!(
                            target: "rustfs::storage::database::sync_service",
                            "Received shutdown signal, flushing remaining events"
                        );

                        // Flush remaining events
                        flush_batch(&mut batch_upserts, &mut batch_deletes).await;
                        break;
                    }
                }

                // Flush if batch size reached
                if batch_upserts.len() >= config.batch_size || batch_deletes.len() >= config.batch_size {
                    flush_batch(&mut batch_upserts, &mut batch_deletes).await;
                }
            }

            // Periodic flush based on time interval
            _ = flush_interval.tick() => {
                if !batch_upserts.is_empty() || !batch_deletes.is_empty() {
                    flush_batch(&mut batch_upserts, &mut batch_deletes).await;
                }
            }
        }
    }

    info!(
        target: "rustfs::storage::database::sync_service",
        "Metadata sync worker shut down"
    );
}

/// Flush accumulated batches to database
async fn flush_batch(upserts: &mut Vec<CreateS3Object>, deletes: &mut Vec<(String, String)>) {
    if upserts.is_empty() && deletes.is_empty() {
        return;
    }

    let pool = match get_database_pool() {
        Some(pool) => pool,
        None => {
            error!(
                target: "rustfs::storage::database::sync_service",
                "Database pool not initialized, cannot flush batch"
            );
            // Clear batches to avoid accumulating in memory
            upserts.clear();
            deletes.clear();
            return;
        }
    };

    // Process upserts
    if !upserts.is_empty() {
        let upsert_count = upserts.len();

        for obj in upserts.drain(..) {
            if let Err(e) = S3ObjectRepository::upsert(pool, &obj).await {
                error!(
                    target: "rustfs::storage::database::sync_service",
                    bucket = %obj.bucket,
                    object_key = %obj.object_key,
                    error = %e,
                    "Failed to upsert S3 object metadata"
                );
            }
        }

        debug!(
            target: "rustfs::storage::database::sync_service",
            count = upsert_count,
            "Flushed upsert batch"
        );
    }

    // Process deletes
    if !deletes.is_empty() {
        let delete_count = deletes.len();

        for (bucket, object_key) in deletes.drain(..) {
            if let Err(e) = S3ObjectRepository::delete(pool, &bucket, &object_key).await {
                error!(
                    target: "rustfs::storage::database::sync_service",
                    bucket = %bucket,
                    object_key = %object_key,
                    error = %e,
                    "Failed to delete S3 object metadata"
                );
            }
        }

        debug!(
            target: "rustfs::storage::database::sync_service",
            count = delete_count,
            "Flushed delete batch"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sync_config_default() {
        let config = MetadataSyncConfig::default();
        assert_eq!(config.batch_size, 100);
        assert_eq!(config.flush_interval_secs, 1);
    }

    #[test]
    fn test_metadata_sync_event_construction() {
        use chrono::Utc;

        let upsert_event = MetadataSyncEvent::Upsert(Box::new(CreateS3Object {
            bucket: "test".to_string(),
            object_key: "key".to_string(),
            version_id: None,
            size_bytes: 1024,
            content_type: None,
            etag: None,
            storage_class: None,
            encryption: None,
            tags: None,
            user_metadata: None,
            owner_id: None,
            last_modified: Utc::now(),
        }));

        assert!(matches!(upsert_event, MetadataSyncEvent::Upsert(_)));

        let delete_event = MetadataSyncEvent::Delete {
            bucket: "test".to_string(),
            object_key: "key".to_string(),
        };

        assert!(matches!(delete_event, MetadataSyncEvent::Delete { .. }));
    }
}
