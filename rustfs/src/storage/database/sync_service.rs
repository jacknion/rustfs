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

use crate::storage::database::{CreateS3Object, UpdateS3Object, get_database_pool, repositories::S3ObjectRepository};
use once_cell::sync::OnceCell;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

/// Global metadata sync service sender
static SYNC_SERVICE_TX: OnceCell<mpsc::Sender<MetadataSyncEvent>> = OnceCell::new();

/// Global sync service statistics
static SYNC_STATS: OnceCell<Arc<SyncServiceStats>> = OnceCell::new();

/// Statistics for metadata sync service
#[derive(Debug, Default)]
pub struct SyncServiceStats {
    /// Total upsert events processed
    pub upsert_success: AtomicU64,
    /// Total upsert failures
    pub upsert_failed: AtomicU64,
    /// Total delete events processed
    pub delete_success: AtomicU64,
    /// Total delete failures
    pub delete_failed: AtomicU64,
    /// Total events dropped due to channel full
    pub events_dropped: AtomicU64,
}

/// Events for metadata synchronization
#[derive(Debug, Clone)]
pub enum MetadataSyncEvent {
    /// Object was created or updated
    Upsert(Box<CreateS3Object>),

    /// Object metadata was updated (partial update)
    Update {
        bucket: String,
        object_key: String,
        update: Box<UpdateS3Object>,
    },

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

    /// Maximum number of retry attempts for failed database operations
    pub max_retries: usize,

    /// Base delay between retries in milliseconds (uses exponential backoff)
    pub retry_delay_ms: u64,
}

impl Default for MetadataSyncConfig {
    fn default() -> Self {
        Self {
            batch_size: 100,
            flush_interval_secs: 1,
            max_queue_size: 10000,
            max_retries: 3,
            retry_delay_ms: 100,
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

    // Initialize statistics
    let stats = Arc::new(SyncServiceStats::default());
    SYNC_STATS
        .set(stats.clone())
        .map_err(|_| "Sync stats already initialized".to_string())?;

    // Store the sender in global state
    SYNC_SERVICE_TX
        .set(tx)
        .map_err(|_| "Metadata sync service already initialized".to_string())?;

    info!(
        target: "rustfs::storage::database::sync_service",
        batch_size = config.batch_size,
        flush_interval_secs = config.flush_interval_secs,
        max_queue_size = config.max_queue_size,
        max_retries = config.max_retries,
        retry_delay_ms = config.retry_delay_ms,
        "Metadata sync service initialized"
    );

    // Spawn background worker
    tokio::spawn(async move {
        sync_worker(rx, config, stats).await;
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
                // Record dropped event
                if let Some(stats) = SYNC_STATS.get() {
                    stats.events_dropped.fetch_add(1, Ordering::Relaxed);
                }

                warn!(
                    target: "rustfs::storage::database::sync_service",
                    "Metadata sync queue is full, dropping event to prevent memory overflow"
                );
                "Channel full - metadata sync queue is overloaded. Consider increasing max_queue_size or reducing write rate."
                    .to_string()
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

/// Get current sync service statistics
///
/// Returns None if service is not initialized
pub fn get_sync_stats() -> Option<SyncServiceSnapshot> {
    SYNC_STATS.get().map(|stats| SyncServiceSnapshot {
        upsert_success: stats.upsert_success.load(Ordering::Relaxed),
        upsert_failed: stats.upsert_failed.load(Ordering::Relaxed),
        delete_success: stats.delete_success.load(Ordering::Relaxed),
        delete_failed: stats.delete_failed.load(Ordering::Relaxed),
        events_dropped: stats.events_dropped.load(Ordering::Relaxed),
    })
}

/// Snapshot of sync service statistics
#[derive(Debug, Clone, serde::Serialize)]
pub struct SyncServiceSnapshot {
    pub upsert_success: u64,
    pub upsert_failed: u64,
    pub delete_success: u64,
    pub delete_failed: u64,
    pub events_dropped: u64,
}

impl SyncServiceSnapshot {
    /// Calculate total events processed
    pub fn total_processed(&self) -> u64 {
        self.upsert_success + self.delete_success
    }

    /// Calculate total failures
    pub fn total_failed(&self) -> u64 {
        self.upsert_failed + self.delete_failed
    }

    /// Calculate success rate (0.0 to 1.0)
    pub fn success_rate(&self) -> f64 {
        let total = self.total_processed() + self.total_failed();
        if total == 0 {
            1.0
        } else {
            self.total_processed() as f64 / total as f64
        }
    }

    /// Check if service is healthy (success rate > 95%)
    pub fn is_healthy(&self) -> bool {
        self.success_rate() > 0.95 && self.events_dropped < 1000
    }
}

/// Background worker that processes sync events
async fn sync_worker(mut rx: mpsc::Receiver<MetadataSyncEvent>, config: MetadataSyncConfig, stats: Arc<SyncServiceStats>) {
    let mut batch_upserts: Vec<CreateS3Object> = Vec::with_capacity(config.batch_size);
    let mut batch_updates: Vec<(String, String, UpdateS3Object)> = Vec::with_capacity(config.batch_size); // (bucket, key, update)
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
                    MetadataSyncEvent::Update { bucket, object_key, update } => {
                        batch_updates.push((bucket, object_key, *update));
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
                        flush_batch(&mut batch_upserts, &mut batch_updates, &mut batch_deletes, &config, &stats).await;
                        break;
                    }
                }

                // Flush if batch size reached
                if batch_upserts.len() >= config.batch_size || batch_updates.len() >= config.batch_size || batch_deletes.len() >= config.batch_size {
                    flush_batch(&mut batch_upserts, &mut batch_updates, &mut batch_deletes, &config, &stats).await;
                }
            }

            // Periodic flush based on time interval
            _ = flush_interval.tick() => {
                if !batch_upserts.is_empty() || !batch_updates.is_empty() || !batch_deletes.is_empty() {
                    flush_batch(&mut batch_upserts, &mut batch_updates, &mut batch_deletes, &config, &stats).await;
                }
            }
        }
    }

    info!(
        target: "rustfs::storage::database::sync_service",
        "Metadata sync worker shut down"
    );
}

/// Flush accumulated batches to database with retry mechanism
async fn flush_batch(
    upserts: &mut Vec<CreateS3Object>,
    updates: &mut Vec<(String, String, UpdateS3Object)>,
    deletes: &mut Vec<(String, String)>,
    config: &MetadataSyncConfig,
    stats: &Arc<SyncServiceStats>,
) {
    if upserts.is_empty() && updates.is_empty() && deletes.is_empty() {
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
            updates.clear();
            deletes.clear();
            return;
        }
    };

    // Process upserts with retry
    if !upserts.is_empty() {
        let upsert_count = upserts.len();
        let mut success_count = 0;
        let mut failure_count = 0;

        for obj in upserts.drain(..) {
            match retry_database_operation(|| S3ObjectRepository::upsert(pool, &obj), config.max_retries, config.retry_delay_ms)
                .await
            {
                Ok(_) => {
                    success_count += 1;
                    stats.upsert_success.fetch_add(1, Ordering::Relaxed);
                }
                Err(e) => {
                    failure_count += 1;
                    stats.upsert_failed.fetch_add(1, Ordering::Relaxed);
                    error!(
                        target: "rustfs::storage::database::sync_service",
                        bucket = %obj.bucket,
                        object_key = %obj.object_key,
                        error = %e,
                        retries = config.max_retries,
                        "Failed to upsert S3 object metadata after retries"
                    );
                }
            }
        }

        debug!(
            target: "rustfs::storage::database::sync_service",
            total = upsert_count,
            success = success_count,
            failed = failure_count,
            "Flushed upsert batch"
        );
    }

    // Process updates with retry
    if !updates.is_empty() {
        let update_count = updates.len();
        let mut success_count = 0;
        let mut failure_count = 0;

        for (bucket, object_key, update_obj) in updates.drain(..) {
            match retry_database_operation(
                || S3ObjectRepository::update(pool, &bucket, &object_key, &update_obj),
                config.max_retries,
                config.retry_delay_ms,
            )
            .await
            {
                Ok(_) => {
                    success_count += 1;
                    stats.upsert_success.fetch_add(1, Ordering::Relaxed); // Reuse upsert stats for updates
                }
                Err(e) => {
                    failure_count += 1;
                    stats.upsert_failed.fetch_add(1, Ordering::Relaxed);
                    error!(
                        target: "rustfs::storage::database::sync_service",
                        bucket = %bucket,
                        object_key = %object_key,
                        error = %e,
                        retries = config.max_retries,
                        "Failed to update S3 object metadata after retries"
                    );
                }
            }
        }

        debug!(
            target: "rustfs::storage::database::sync_service",
            total = update_count,
            success = success_count,
            failed = failure_count,
            "Flushed update batch"
        );
    }

    // Process deletes with retry
    if !deletes.is_empty() {
        let delete_count = deletes.len();
        let mut success_count = 0;
        let mut failure_count = 0;

        for (bucket, object_key) in deletes.drain(..) {
            match retry_database_operation(
                || S3ObjectRepository::delete(pool, &bucket, &object_key),
                config.max_retries,
                config.retry_delay_ms,
            )
            .await
            {
                Ok(_) => {
                    success_count += 1;
                    stats.delete_success.fetch_add(1, Ordering::Relaxed);
                }
                Err(e) => {
                    failure_count += 1;
                    stats.delete_failed.fetch_add(1, Ordering::Relaxed);
                    error!(
                        target: "rustfs::storage::database::sync_service",
                        bucket = %bucket,
                        object_key = %object_key,
                        error = %e,
                        retries = config.max_retries,
                        "Failed to delete S3 object metadata after retries"
                    );
                }
            }
        }

        debug!(
            target: "rustfs::storage::database::sync_service",
            total = delete_count,
            success = success_count,
            failed = failure_count,
            "Flushed delete batch"
        );
    }
}

/// Retry a database operation with exponential backoff
///
/// # Arguments
///
/// * `operation` - The async database operation to retry
/// * `max_retries` - Maximum number of retry attempts
/// * `base_delay_ms` - Base delay in milliseconds (doubled for each retry)
///
/// # Returns
///
/// Returns the operation result, or the last error if all retries failed
async fn retry_database_operation<F, Fut, T>(mut operation: F, max_retries: usize, base_delay_ms: u64) -> Result<T, sqlx::Error>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, sqlx::Error>>,
{
    let mut last_error = None;
    let mut attempt = 0;

    while attempt <= max_retries {
        match operation().await {
            Ok(result) => {
                if attempt > 0 {
                    debug!(
                        target: "rustfs::storage::database::sync_service",
                        attempt = attempt,
                        "Database operation succeeded after retry"
                    );
                }
                return Ok(result);
            }
            Err(e) => {
                last_error = Some(e);

                if attempt < max_retries {
                    // Exponential backoff: 100ms, 200ms, 400ms, etc.
                    let delay = base_delay_ms * (1 << attempt);

                    warn!(
                        target: "rustfs::storage::database::sync_service",
                        attempt = attempt + 1,
                        max_retries = max_retries,
                        delay_ms = delay,
                        error = %last_error.as_ref().unwrap(),
                        "Database operation failed, retrying..."
                    );

                    tokio::time::sleep(tokio::time::Duration::from_millis(delay)).await;
                }

                attempt += 1;
            }
        }
    }

    Err(last_error.unwrap())
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
