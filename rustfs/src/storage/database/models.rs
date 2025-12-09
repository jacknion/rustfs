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

//! Data models for S3 object metadata storage

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::types::Json;
use std::collections::HashMap;

/// S3 object metadata record from database
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct S3Object {
    /// Auto-incrementing ID
    pub id: i64,

    /// Bucket name
    pub bucket: String,

    /// Object key (path)
    pub object_key: String,

    /// Version ID (optional for non-versioned buckets)
    pub version_id: Option<String>,

    /// Object size in bytes
    pub size_bytes: i64,

    /// Content type (MIME type)
    pub content_type: Option<String>,

    /// ETag (entity tag)
    pub etag: Option<String>,

    /// Storage class (STANDARD, REDUCED_REDUNDANCY, etc.)
    pub storage_class: Option<String>,

    /// Encryption algorithm (AES256, aws:kms, etc.)
    pub encryption: Option<String>,

    /// Object tags as JSONB
    pub tags: Option<Json<HashMap<String, String>>>,

    /// User-defined metadata (x-amz-meta-*) as JSONB
    pub user_metadata: Option<Json<HashMap<String, String>>>,

    /// Owner ID
    pub owner_id: Option<String>,

    /// Whether object is deleted (for soft delete)
    pub is_deleted: bool,

    /// Last modified timestamp
    pub last_modified: DateTime<Utc>,

    /// Record creation timestamp
    pub created_at: DateTime<Utc>,

    /// Record update timestamp
    pub updated_at: DateTime<Utc>,
}

/// DTO for creating a new S3 object record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateS3Object {
    /// Bucket name
    pub bucket: String,

    /// Object key (path)
    pub object_key: String,

    /// Version ID (optional)
    pub version_id: Option<String>,

    /// Object size in bytes
    pub size_bytes: i64,

    /// Content type (MIME type)
    pub content_type: Option<String>,

    /// ETag (entity tag)
    pub etag: Option<String>,

    /// Storage class
    pub storage_class: Option<String>,

    /// Encryption algorithm
    pub encryption: Option<String>,

    /// Object tags
    pub tags: Option<HashMap<String, String>>,

    /// User-defined metadata
    pub user_metadata: Option<HashMap<String, String>>,

    /// Owner ID
    pub owner_id: Option<String>,

    /// Last modified timestamp
    pub last_modified: DateTime<Utc>,
}

/// DTO for updating S3 object metadata
///
/// All fields are optional - only provided fields will be updated
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UpdateS3Object {
    /// Update storage class
    pub storage_class: Option<String>,

    /// Update encryption algorithm
    pub encryption: Option<String>,

    /// Update or replace object tags
    pub tags: Option<HashMap<String, String>>,

    /// Update or replace user-defined metadata
    pub user_metadata: Option<HashMap<String, String>>,

    /// Update owner ID
    pub owner_id: Option<String>,

    /// Update content type
    pub content_type: Option<String>,
}

/// Query parameters for searching S3 objects
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct S3ObjectQuery {
    /// Filter by bucket name
    pub bucket: Option<String>,

    /// Filter by object key prefix
    pub prefix: Option<String>,

    /// Filter by storage class
    pub storage_class: Option<String>,

    /// Filter by encryption type
    pub encryption: Option<String>,

    /// Filter by owner ID
    pub owner_id: Option<String>,

    /// Filter by tags (exact match)
    pub tags: Option<HashMap<String, String>>,

    /// Filter by tags using fuzzy search (partial match, case-insensitive)
    /// Key-value pairs where values support wildcards (%, _)
    pub tags_fuzzy: Option<HashMap<String, String>>,

    /// Minimum object size (bytes)
    pub min_size: Option<i64>,

    /// Maximum object size (bytes)
    pub max_size: Option<i64>,

    /// Filter objects modified after this timestamp
    pub modified_after: Option<DateTime<Utc>>,

    /// Filter objects modified before this timestamp
    pub modified_before: Option<DateTime<Utc>>,

    /// Include deleted objects
    pub include_deleted: bool,

    /// Maximum number of results to return
    pub limit: Option<i64>,

    /// Offset for pagination
    pub offset: Option<i64>,
}

/// Metadata for S3 object query response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct S3ObjectMetadata {
    /// Total number of matching records
    pub total_count: i64,

    /// Number of records returned
    pub returned_count: usize,

    /// Current offset
    pub offset: i64,

    /// Query execution time in milliseconds
    pub query_time_ms: u64,
}

/// Response wrapper for S3 object queries
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct S3ObjectQueryResponse {
    /// Metadata about the query
    pub metadata: S3ObjectMetadata,

    /// List of S3 objects
    pub objects: Vec<S3Object>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_s3_object_serialization() {
        let mut tags = HashMap::new();
        tags.insert("Project".to_string(), "test".to_string());
        tags.insert("Environment".to_string(), "dev".to_string());

        let obj = CreateS3Object {
            bucket: "test-bucket".to_string(),
            object_key: "path/to/file.txt".to_string(),
            version_id: Some("v1".to_string()),
            size_bytes: 1024,
            content_type: Some("text/plain".to_string()),
            etag: Some("abc123".to_string()),
            storage_class: Some("STANDARD".to_string()),
            encryption: Some("AES256".to_string()),
            tags: Some(tags),
            user_metadata: None,
            owner_id: Some("user-123".to_string()),
            last_modified: Utc::now(),
        };

        let json = serde_json::to_string(&obj).unwrap();
        assert!(json.contains("test-bucket"));
        assert!(json.contains("path/to/file.txt"));
    }

    #[test]
    fn test_s3_object_query_default() {
        let query = S3ObjectQuery::default();
        assert!(query.bucket.is_none());
        assert!(query.prefix.is_none());
        assert!(!query.include_deleted);
    }

    #[test]
    fn test_s3_object_query_with_filters() {
        let mut tags = HashMap::new();
        tags.insert("Type".to_string(), "log".to_string());

        let query = S3ObjectQuery {
            bucket: Some("my-bucket".to_string()),
            prefix: Some("logs/".to_string()),
            storage_class: Some("STANDARD".to_string()),
            encryption: None,
            owner_id: Some("user-456".to_string()),
            tags: Some(tags),
            min_size: Some(1000),
            max_size: Some(10000),
            modified_after: None,
            modified_before: None,
            include_deleted: false,
            limit: Some(100),
            offset: Some(0),
        };

        assert_eq!(query.bucket.as_deref(), Some("my-bucket"));
        assert_eq!(query.limit, Some(100));
        assert_eq!(query.min_size, Some(1000));
    }
}
