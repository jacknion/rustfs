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

//! Metadata extractor for converting ObjectInfo to database models

// Allow unused code during development - will be used in later integration steps
#![allow(dead_code)]
#![allow(unused_imports)]

use crate::storage::database::CreateS3Object;
use chrono::{DateTime, Utc};
use rustfs_ecstore::store_api::ObjectInfo;
use std::collections::HashMap;
use tracing::{debug, warn};

/// Extract S3 object metadata from ObjectInfo
pub struct MetadataExtractor;

impl MetadataExtractor {
    /// Extract metadata from ObjectInfo and convert to CreateS3Object
    ///
    /// # Arguments
    ///
    /// * `obj_info` - Object information from ecstore
    /// * `encryption` - Encryption algorithm (optional)
    /// * `owner_id` - Owner identifier (optional)
    ///
    /// # Returns
    ///
    /// Returns CreateS3Object for database insertion
    pub fn extract(obj_info: &ObjectInfo, encryption: Option<String>, owner_id: Option<String>) -> CreateS3Object {
        // Extract tags from user_tags string (format: "key1=value1&key2=value2")
        let tags = Self::parse_tags(&obj_info.user_tags);

        // Extract user-defined metadata (x-amz-meta-* headers)
        let user_metadata = Self::extract_user_metadata(&obj_info.user_defined);

        // Convert mod_time to DateTime<Utc>
        let last_modified = obj_info
            .mod_time
            .map(|t| DateTime::from_timestamp(t.unix_timestamp(), t.nanosecond()).unwrap_or_else(Utc::now))
            .unwrap_or_else(Utc::now);

        // Convert version_id to string
        let version_id = obj_info.version_id.map(|v| v.to_string());

        CreateS3Object {
            bucket: obj_info.bucket.clone(),
            object_key: obj_info.name.clone(),
            version_id,
            size_bytes: obj_info.size,
            content_type: obj_info.content_type.clone(),
            etag: obj_info.etag.clone(),
            storage_class: obj_info.storage_class.clone(),
            encryption,
            tags,
            user_metadata,
            owner_id,
            last_modified,
        }
    }

    /// Parse tags from S3 tagging string format
    ///
    /// S3 tags are typically in format: "key1=value1&key2=value2"
    ///
    /// # Arguments
    ///
    /// * `tags_str` - Tags string from S3 request
    ///
    /// # Returns
    ///
    /// Returns HashMap of tag key-value pairs, or None if empty
    fn parse_tags(tags_str: &str) -> Option<HashMap<String, String>> {
        if tags_str.is_empty() {
            return None;
        }

        let mut tags = HashMap::new();

        for pair in tags_str.split('&') {
            if let Some((key, value)) = pair.split_once('=') {
                // URL decode if necessary
                let decoded_key = urlencoding::decode(key).unwrap_or_else(|_| key.into());
                let decoded_value = urlencoding::decode(value).unwrap_or_else(|_| value.into());

                tags.insert(decoded_key.to_string(), decoded_value.to_string());
            } else {
                warn!(
                    target: "rustfs::storage::metadata_extractor",
                    pair = %pair,
                    "Invalid tag pair format, expected 'key=value'"
                );
            }
        }

        if tags.is_empty() { None } else { Some(tags) }
    }

    /// Extract user-defined metadata from user_defined map
    ///
    /// Filters out system metadata and extracts only x-amz-meta-* headers
    ///
    /// # Arguments
    ///
    /// * `user_defined` - User-defined metadata map from ObjectInfo
    ///
    /// # Returns
    ///
    /// Returns HashMap of user metadata, or None if empty
    fn extract_user_metadata(user_defined: &HashMap<String, String>) -> Option<HashMap<String, String>> {
        const AMZ_META_PREFIX: &str = "x-amz-meta-";
        const AMZ_META_PREFIX_LOWER: &str = "x-amz-meta-";

        let mut metadata = HashMap::new();

        for (key, value) in user_defined.iter() {
            let key_lower = key.to_lowercase();

            // Only include x-amz-meta-* headers
            if key_lower.starts_with(AMZ_META_PREFIX_LOWER) {
                // Remove the prefix
                let metadata_key = key_lower
                    .strip_prefix(AMZ_META_PREFIX_LOWER)
                    .unwrap_or(&key_lower)
                    .to_string();

                metadata.insert(metadata_key, value.clone());
            }
        }

        if metadata.is_empty() { None } else { Some(metadata) }
    }

    /// Extract encryption information from ObjectInfo
    ///
    /// This is a helper method that can be used to determine the encryption type
    /// from the object metadata.
    ///
    /// # Arguments
    ///
    /// * `obj_info` - Object information
    ///
    /// # Returns
    ///
    /// Returns encryption algorithm name if found
    pub fn extract_encryption(obj_info: &ObjectInfo) -> Option<String> {
        // Check for server-side encryption headers
        const SSE_ALGORITHM_KEY: &str = "x-amz-server-side-encryption";
        const SSE_CUSTOMER_ALGORITHM_KEY: &str = "x-amz-server-side-encryption-customer-algorithm";

        // Check user_defined for encryption headers
        if let Some(algo) = obj_info.user_defined.get(SSE_ALGORITHM_KEY) {
            return Some(algo.clone());
        }

        if let Some(algo) = obj_info.user_defined.get(SSE_CUSTOMER_ALGORITHM_KEY) {
            return Some(algo.clone());
        }

        // Check lowercase versions
        if let Some(algo) = obj_info.user_defined.get(&SSE_ALGORITHM_KEY.to_lowercase()) {
            return Some(algo.clone());
        }

        if let Some(algo) = obj_info.user_defined.get(&SSE_CUSTOMER_ALGORITHM_KEY.to_lowercase()) {
            return Some(algo.clone());
        }

        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_tags_valid() {
        let tags_str = "Project=analytics&Environment=production&Team=data";
        let tags = MetadataExtractor::parse_tags(tags_str).unwrap();

        assert_eq!(tags.len(), 3);
        assert_eq!(tags.get("Project"), Some(&"analytics".to_string()));
        assert_eq!(tags.get("Environment"), Some(&"production".to_string()));
        assert_eq!(tags.get("Team"), Some(&"data".to_string()));
    }

    #[test]
    fn test_parse_tags_url_encoded() {
        let tags_str = "Name=Test%20File&Type=Log%2FData";
        let tags = MetadataExtractor::parse_tags(tags_str).unwrap();

        assert_eq!(tags.len(), 2);
        assert_eq!(tags.get("Name"), Some(&"Test File".to_string()));
        assert_eq!(tags.get("Type"), Some(&"Log/Data".to_string()));
    }

    #[test]
    fn test_parse_tags_empty() {
        let tags_str = "";
        let tags = MetadataExtractor::parse_tags(tags_str);
        assert!(tags.is_none());
    }

    #[test]
    fn test_parse_tags_invalid() {
        let tags_str = "invalid&Project=test";
        let tags = MetadataExtractor::parse_tags(tags_str).unwrap();

        // Should skip invalid pair and parse valid one
        assert_eq!(tags.len(), 1);
        assert_eq!(tags.get("Project"), Some(&"test".to_string()));
    }

    #[test]
    fn test_extract_user_metadata() {
        let mut user_defined = HashMap::new();
        user_defined.insert("x-amz-meta-author".to_string(), "John Doe".to_string());
        user_defined.insert("x-amz-meta-description".to_string(), "Test file".to_string());
        user_defined.insert("x-amz-server-side-encryption".to_string(), "AES256".to_string());
        user_defined.insert("Content-Type".to_string(), "text/plain".to_string());

        let metadata = MetadataExtractor::extract_user_metadata(&user_defined).unwrap();

        assert_eq!(metadata.len(), 2);
        assert_eq!(metadata.get("author"), Some(&"John Doe".to_string()));
        assert_eq!(metadata.get("description"), Some(&"Test file".to_string()));

        // Should not include non-meta headers
        assert!(!metadata.contains_key("x-amz-server-side-encryption"));
        assert!(!metadata.contains_key("Content-Type"));
    }

    #[test]
    fn test_extract_user_metadata_empty() {
        let user_defined = HashMap::new();
        let metadata = MetadataExtractor::extract_user_metadata(&user_defined);
        assert!(metadata.is_none());
    }

    #[test]
    fn test_extract_encryption() {
        let mut user_defined = HashMap::new();
        user_defined.insert("x-amz-server-side-encryption".to_string(), "AES256".to_string());

        let obj_info = ObjectInfo {
            bucket: "test".to_string(),
            name: "file.txt".to_string(),
            storage_class: None,
            mod_time: None,
            size: 1024,
            actual_size: 1024,
            is_dir: false,
            user_defined,
            parity_blocks: 0,
            data_blocks: 1,
            version_id: None,
            delete_marker: false,
            transitioned_object: Default::default(),
            restore_ongoing: false,
            restore_expires: None,
            user_tags: String::new(),
            parts: vec![],
            is_latest: true,
            content_type: None,
            content_encoding: None,
            expires: None,
            num_versions: 1,
            successor_mod_time: None,
            put_object_reader: None,
            etag: None,
            inlined: false,
            metadata_only: false,
            version_only: false,
            replication_status_internal: None,
            replication_status: Default::default(),
            version_purge_status_internal: None,
            version_purge_status: Default::default(),
            replication_decision: String::new(),
            checksum: None,
        };

        let encryption = MetadataExtractor::extract_encryption(&obj_info);
        assert_eq!(encryption, Some("AES256".to_string()));
    }
}
