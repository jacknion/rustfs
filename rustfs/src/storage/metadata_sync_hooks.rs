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

//! S3 metadata database sync hooks
//!
//! This module provides hooks for syncing S3 object metadata to the database
//! after successful object operations.

use crate::storage::database::{MetadataSyncEvent, send_sync_event};
use crate::storage::metadata_extractor::MetadataExtractor;
use rustfs_ecstore::store_api::ObjectInfo;
use tracing::{debug, error, warn};

/// Sync object metadata to database after successful PutObject
///
/// This is a non-blocking operation that queues the metadata for async processing.
///
/// # Arguments
///
/// * `obj_info` - Object information from the put operation
/// * `owner_id` - Optional owner ID for the object
pub fn sync_put_object_metadata(obj_info: &ObjectInfo, owner_id: Option<String>) {
    // Extract encryption information
    let encryption = MetadataExtractor::extract_encryption(obj_info);

    // Extract metadata
    let create_obj = MetadataExtractor::extract(obj_info, encryption, owner_id);

    debug!(
        target: "rustfs::storage::metadata_sync_hooks",
        bucket = %create_obj.bucket,
        object_key = %create_obj.object_key,
        size = create_obj.size_bytes,
        "Syncing put object metadata to database"
    );

    // Send event to sync service (non-blocking)
    if let Err(e) = send_sync_event(MetadataSyncEvent::Upsert(Box::new(create_obj.clone()))) {
        warn!(
            target: "rustfs::storage::metadata_sync_hooks",
            error = %e,
            bucket = %obj_info.bucket,
            object_key = %obj_info.name,
            size = obj_info.size,
            error_type = if e.contains("Channel full") { "channel_full" } else if e.contains("not initialized") { "NOT_INITIALIZED" } else { "channel_closed" },
            "❌ SYNC FAILED: Failed to send metadata sync event for put object"
        );
    }
}

/// Sync object deletion to database after successful DeleteObject
///
/// This is a non-blocking operation that queues the deletion for async processing.
///
/// # Arguments
///
/// * `bucket` - Bucket name
/// * `object_key` - Object key
pub fn sync_delete_object_metadata(bucket: &str, object_key: &str) {
    error!(
        target: "rustfs::storage::metadata_sync_hooks",
        bucket = %bucket,
        object_key = %object_key,
        "Syncing delete object metadata to database"
    );

    // Send event to sync service (non-blocking)
    if let Err(e) = send_sync_event(MetadataSyncEvent::Delete {
        bucket: bucket.to_string(),
        object_key: object_key.to_string(),
    }) {
        warn!(
            target: "rustfs::storage::metadata_sync_hooks",
            error = %e,
            bucket = %bucket,
            object_key = %object_key,
            error_type = if e.contains("Channel full") { "channel_full" } else { "channel_closed" },
            "Failed to send metadata sync event for delete object - stale metadata may remain in query results"
        );
    }
}

/// Sync object tags to database after successful PutObjectTagging
///
/// This is a non-blocking operation that queues the tag update for async processing.
///
/// # Arguments
///
/// * `bucket` - Bucket name
/// * `object_key` - Object key
/// * `tags` - Tag key-value pairs
pub fn sync_object_tags(bucket: &str, object_key: &str, tags: std::collections::HashMap<String, String>) {
    use crate::storage::database::{MetadataSyncEvent, UpdateS3Object, send_sync_event};

    debug!(
        target: "rustfs::storage::metadata_sync_hooks",
        bucket = %bucket,
        object_key = %object_key,
        tags_count = tags.len(),
        "Syncing object tags to database"
    );

    // Create update event with tags
    let update = UpdateS3Object {
        tags: Some(tags),
        ..Default::default()
    };

    // Send update event to sync service (non-blocking)
    if let Err(e) = send_sync_event(MetadataSyncEvent::Update {
        bucket: bucket.to_string(),
        object_key: object_key.to_string(),
        update: Box::new(update),
    }) {
        warn!(
            target: "rustfs::storage::metadata_sync_hooks",
            error = %e,
            bucket = %bucket,
            object_key = %object_key,
            error_type = if e.contains("Channel full") { "channel_full" } else { "channel_closed" },
            "Failed to send tag sync event - database tags may be out of sync"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: These tests require the sync service to be initialized
    // They are primarily for documentation and will be tested in integration tests

    #[test]
    fn test_sync_functions_exist() {
        // Just verify the functions are accessible
        // Actual testing requires full system initialization
        let _ = sync_put_object_metadata;
        let _ = sync_delete_object_metadata;
    }
}
