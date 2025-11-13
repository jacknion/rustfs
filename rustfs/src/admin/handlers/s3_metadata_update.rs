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

//! S3 metadata update API handler

// Allow unused code during development - will be used after route registration
#![allow(dead_code)]

use super::Operation;
use crate::storage::database::{UpdateS3Object, get_database_pool, repositories::S3ObjectRepository};
use http::HeaderMap;
use hyper::StatusCode;
use matchit::Params;
use s3s::{Body, S3Request, S3Response, S3Result, s3_error};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, error, info};

/// Update S3 metadata handler
///
/// PUT /rustfs/admin/v3/s3/metadata/update
///
/// Request body (JSON):
/// {
///   "bucket": "my-bucket",
///   "objectKey": "path/to/object.txt",
///   "updates": {
///     "storageClass": "GLACIER",
///     "tags": {"Environment": "production", "Project": "analytics"},
///     "userMetadata": {"x-amz-meta-custom": "value"}
///   }
/// }
///
/// Response:
/// {
///   "success": true,
///   "message": "Metadata updated successfully",
///   "rowsAffected": 1
/// }
pub struct UpdateS3MetadataHandler;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdateMetadataRequest {
    /// Bucket name
    bucket: String,

    /// Object key
    object_key: String,

    /// Fields to update
    updates: MetadataUpdates,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MetadataUpdates {
    /// Update storage class
    storage_class: Option<String>,

    /// Update encryption
    encryption: Option<String>,

    /// Update content type
    content_type: Option<String>,

    /// Update or replace tags
    tags: Option<HashMap<String, String>>,

    /// Update or replace user metadata
    user_metadata: Option<HashMap<String, String>>,

    /// Update owner ID
    owner_id: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct UpdateMetadataResponse {
    /// Whether the update was successful
    success: bool,

    /// Human-readable message
    message: String,

    /// Number of rows affected (0 = not found, 1 = updated)
    rows_affected: u64,
}

#[async_trait::async_trait]
impl Operation for UpdateS3MetadataHandler {
    async fn call(&self, req: S3Request<Body>, _params: Params<'_, '_>) -> S3Result<S3Response<(StatusCode, Body)>> {
        info!(
            target: "rustfs::admin::handlers::s3_metadata_update",
            "Handling S3 metadata update request"
        );

        // Get database pool
        let pool = get_database_pool().ok_or_else(|| s3_error!(InternalError, "Database not initialized"))?;

        // Read request body
        let mut input = req.input;
        let body_bytes = input
            .store_all_unlimited()
            .await
            .map_err(|e| s3_error!(InvalidRequest, "Failed to read request body: {}", e))?;

        // Parse JSON request
        let request: UpdateMetadataRequest =
            serde_json::from_slice(&body_bytes).map_err(|e| s3_error!(InvalidRequest, "Invalid JSON request body: {}", e))?;

        debug!(
            target: "rustfs::admin::handlers::s3_metadata_update",
            bucket = %request.bucket,
            object_key = %request.object_key,
            "Parsed update metadata request"
        );

        // Validate that at least one field is provided
        if request.updates.storage_class.is_none()
            && request.updates.encryption.is_none()
            && request.updates.content_type.is_none()
            && request.updates.tags.is_none()
            && request.updates.user_metadata.is_none()
            && request.updates.owner_id.is_none()
        {
            return Err(s3_error!(
                InvalidRequest,
                "No update fields provided. Specify at least one field to update."
            ));
        }

        // Convert to UpdateS3Object
        let update = UpdateS3Object {
            storage_class: request.updates.storage_class,
            encryption: request.updates.encryption,
            content_type: request.updates.content_type,
            tags: request.updates.tags,
            user_metadata: request.updates.user_metadata,
            owner_id: request.updates.owner_id,
        };

        // Execute update
        let rows_affected = S3ObjectRepository::update(pool, &request.bucket, &request.object_key, &update)
            .await
            .map_err(|e| {
                error!(
                    target: "rustfs::admin::handlers::s3_metadata_update",
                    error = %e,
                    bucket = %request.bucket,
                    object_key = %request.object_key,
                    "Failed to update S3 metadata"
                );

                // Provide user-friendly error messages
                let error_msg = if e.to_string().contains("connection") {
                    "Database connection failed. Please try again later."
                } else if e.to_string().contains("timeout") {
                    "Database operation timeout. Please try again."
                } else {
                    "Failed to update metadata. Please contact administrator if this persists."
                };

                s3_error!(InternalError, "{} Error: {}", error_msg, e)
            })?;

        let (success, message, status_code) = if rows_affected > 0 {
            (true, "Metadata updated successfully".to_string(), StatusCode::OK)
        } else {
            (
                false,
                format!(
                    "Object not found or already deleted: bucket={}, key={}",
                    request.bucket, request.object_key
                ),
                StatusCode::NOT_FOUND,
            )
        };

        debug!(
            target: "rustfs::admin::handlers::s3_metadata_update",
            bucket = %request.bucket,
            object_key = %request.object_key,
            rows_affected = rows_affected,
            success = success,
            "Update metadata operation completed"
        );

        let response_body = UpdateMetadataResponse {
            success,
            message,
            rows_affected,
        };

        // Serialize response
        let body =
            serde_json::to_string(&response_body).map_err(|e| s3_error!(InternalError, "Failed to serialize response: {}", e))?;

        let mut headers = HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, "application/json".parse().unwrap());

        Ok(S3Response::with_headers((status_code, Body::from(body)), headers))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_metadata_updates_deserialization() {
        let json = r#"{
            "bucket": "test-bucket",
            "objectKey": "path/to/file.txt",
            "updates": {
                "storageClass": "GLACIER",
                "tags": {"Environment": "prod"}
            }
        }"#;

        let request: UpdateMetadataRequest = serde_json::from_str(json).unwrap();
        assert_eq!(request.bucket, "test-bucket");
        assert_eq!(request.object_key, "path/to/file.txt");
        assert_eq!(request.updates.storage_class.as_deref(), Some("GLACIER"));
        assert!(request.updates.tags.is_some());
    }

    #[test]
    fn test_update_response_serialization() {
        let response = UpdateMetadataResponse {
            success: true,
            message: "Updated".to_string(),
            rows_affected: 1,
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("success"));
        assert!(json.contains("true"));
        assert!(json.contains("rowsAffected"));
    }
}
