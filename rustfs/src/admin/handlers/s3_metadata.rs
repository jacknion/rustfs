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

//! S3 metadata query API handlers

// Allow unused code during development - will be used after route registration
#![allow(dead_code)]

use super::Operation;
use crate::storage::database::{S3ObjectQuery, get_database_pool, repositories::S3ObjectRepository};
use chrono::DateTime;
use http::HeaderMap;
use hyper::StatusCode;
use matchit::Params;
use s3s::{Body, S3Request, S3Response, S3Result, s3_error};
use serde::Deserialize;
use std::collections::HashMap;
use tracing::{debug, error, info};

/// Query S3 metadata handler
///
/// GET /rustfs/admin/v3/s3/metadata/query
///
/// Query parameters:
/// - bucket: Filter by bucket name
/// - prefix: Filter by object key prefix
/// - storage_class: Filter by storage class
/// - encryption: Filter by encryption type
/// - owner_id: Filter by owner ID
/// - min_size: Minimum object size (bytes)
/// - max_size: Maximum object size (bytes)
/// - modified_after: Filter objects modified after (RFC3339)
/// - modified_before: Filter objects modified before (RFC3339)
/// - include_deleted: Include deleted objects (true/false)
/// - limit: Maximum number of results
/// - offset: Offset for pagination
pub struct QueryS3MetadataHandler;

#[async_trait::async_trait]
impl Operation for QueryS3MetadataHandler {
    async fn call(&self, req: S3Request<Body>, _params: Params<'_, '_>) -> S3Result<S3Response<(StatusCode, Body)>> {
        info!(
            target: "rustfs::admin::handlers::s3_metadata",
            "Handling S3 metadata query request"
        );

        // Get database pool
        let pool = get_database_pool().ok_or_else(|| s3_error!(InternalError, "Database not initialized"))?;

        // Parse query parameters from URI
        let query_str = req.uri.query().unwrap_or("");

        debug!(
            target: "rustfs::admin::handlers::s3_metadata",
            query_string = %query_str,
            "Parsing query parameters"
        );

        // Parse query parameters manually
        let mut query =
            parse_query_params(query_str).map_err(|e| s3_error!(InvalidRequest, "Invalid query parameters: {}", e))?;

        // Apply default and maximum limits to prevent unbounded queries
        const DEFAULT_LIMIT: i64 = 100;
        const MAX_LIMIT: i64 = 1000;

        if query.limit.is_none() {
            query.limit = Some(DEFAULT_LIMIT);
        } else {
            query.limit = Some(query.limit.unwrap().clamp(1, MAX_LIMIT));
        }

        // Execute query
        let response = S3ObjectRepository::query(pool, &query).await.map_err(|e| {
            error!(
                target: "rustfs::admin::handlers::s3_metadata",
                error = %e,
                "Failed to query S3 metadata"
            );
            s3_error!(InternalError, "Database query failed: {}", e)
        })?;

        debug!(
            target: "rustfs::admin::handlers::s3_metadata",
            total_count = response.metadata.total_count,
            returned_count = response.metadata.returned_count,
            query_time_ms = response.metadata.query_time_ms,
            "Query executed successfully"
        );

        // Serialize response
        let body =
            serde_json::to_string(&response).map_err(|e| s3_error!(InternalError, "Failed to serialize response: {}", e))?;

        let mut headers = HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, "application/json".parse().unwrap());

        Ok(S3Response::with_headers((StatusCode::OK, Body::from(body)), headers))
    }
}

/// Query S3 metadata by tags handler
///
/// POST /rustfs/admin/v3/s3/metadata/query-by-tags
///
/// Request body (JSON):
/// {
///   "tags": {"key1": "value1", "key2": "value2"},
///   "limit": 100,
///   "bucket": "optional-bucket-filter"
/// }
pub struct QueryS3MetadataByTagsHandler;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct QueryByTagsRequest {
    tags: HashMap<String, String>,
    limit: Option<i64>,
    bucket: Option<String>,
    prefix: Option<String>,
    include_deleted: Option<bool>,
}

#[async_trait::async_trait]
impl Operation for QueryS3MetadataByTagsHandler {
    async fn call(&self, req: S3Request<Body>, _params: Params<'_, '_>) -> S3Result<S3Response<(StatusCode, Body)>> {
        info!(
            target: "rustfs::admin::handlers::s3_metadata",
            "Handling S3 metadata query by tags request"
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
        let request: QueryByTagsRequest =
            serde_json::from_slice(&body_bytes).map_err(|e| s3_error!(InvalidRequest, "Invalid JSON request body: {}", e))?;

        debug!(
            target: "rustfs::admin::handlers::s3_metadata",
            tags = ?request.tags,
            limit = ?request.limit,
            bucket = ?request.bucket,
            "Parsed query by tags request"
        );

        // Build query with limits
        const DEFAULT_LIMIT: i64 = 100;
        const MAX_LIMIT: i64 = 1000;

        let limit = match request.limit {
            Some(l) => Some(l.clamp(1, MAX_LIMIT)),
            None => Some(DEFAULT_LIMIT),
        };

        let query = S3ObjectQuery {
            bucket: request.bucket,
            prefix: request.prefix,
            tags: Some(request.tags),
            limit,
            include_deleted: request.include_deleted.unwrap_or(false),
            ..Default::default()
        };

        // Execute query
        let response = S3ObjectRepository::query(pool, &query).await.map_err(|e| {
            error!(
                target: "rustfs::admin::handlers::s3_metadata",
                error = %e,
                "Failed to query S3 metadata by tags"
            );
            s3_error!(InternalError, "Database query failed: {}", e)
        })?;

        debug!(
            target: "rustfs::admin::handlers::s3_metadata",
            total_count = response.metadata.total_count,
            returned_count = response.metadata.returned_count,
            query_time_ms = response.metadata.query_time_ms,
            "Query by tags executed successfully"
        );

        // Serialize response
        let body =
            serde_json::to_string(&response).map_err(|e| s3_error!(InternalError, "Failed to serialize response: {}", e))?;

        let mut headers = HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, "application/json".parse().unwrap());

        Ok(S3Response::with_headers((StatusCode::OK, Body::from(body)), headers))
    }
}

/// Parse query parameters from query string
fn parse_query_params(query_str: &str) -> Result<S3ObjectQuery, String> {
    let mut query = S3ObjectQuery::default();

    for pair in query_str.split('&') {
        if pair.is_empty() {
            continue;
        }

        let (key, value) = pair.split_once('=').ok_or_else(|| format!("Invalid parameter: {}", pair))?;

        let key = urlencoding::decode(key).map_err(|e| format!("Failed to decode key: {}", e))?;
        let value = urlencoding::decode(value).map_err(|e| format!("Failed to decode value: {}", e))?;

        match key.as_ref() {
            "bucket" => query.bucket = Some(value.to_string()),
            "prefix" => query.prefix = Some(value.to_string()),
            "storage_class" => query.storage_class = Some(value.to_string()),
            "encryption" => query.encryption = Some(value.to_string()),
            "owner_id" => query.owner_id = Some(value.to_string()),
            "min_size" => {
                query.min_size = Some(value.parse::<i64>().map_err(|e| format!("Invalid min_size: {}", e))?);
            }
            "max_size" => {
                query.max_size = Some(value.parse::<i64>().map_err(|e| format!("Invalid max_size: {}", e))?);
            }
            "modified_after" => {
                query.modified_after = Some(
                    DateTime::parse_from_rfc3339(&value)
                        .map_err(|e| format!("Invalid modified_after: {}", e))?
                        .into(),
                );
            }
            "modified_before" => {
                query.modified_before = Some(
                    DateTime::parse_from_rfc3339(&value)
                        .map_err(|e| format!("Invalid modified_before: {}", e))?
                        .into(),
                );
            }
            "include_deleted" => {
                query.include_deleted = value.parse::<bool>().map_err(|e| format!("Invalid include_deleted: {}", e))?;
            }
            "limit" => {
                let limit_val = value.parse::<i64>().map_err(|e| format!("Invalid limit: {}", e))?;
                // Enforce maximum limit of 1000 to prevent excessive queries
                query.limit = Some(limit_val.clamp(1, 1000));
            }
            "offset" => {
                query.offset = Some(value.parse::<i64>().map_err(|e| format!("Invalid offset: {}", e))?);
            }
            "tags" => {
                // Parse tags as JSON: tags={"key1":"value1","key2":"value2"}
                let tags: HashMap<String, String> =
                    serde_json::from_str(&value).map_err(|e| format!("Invalid tags JSON: {}", e))?;
                query.tags = Some(tags);
            }
            _ => {
                // Ignore unknown parameters
                debug!(
                    target: "rustfs::admin::handlers::s3_metadata",
                    key = %key,
                    "Ignoring unknown query parameter"
                );
            }
        }
    }

    Ok(query)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_query_params_basic() {
        let query_str = "bucket=test-bucket&prefix=logs/&limit=100&offset=0";
        let query = parse_query_params(query_str).unwrap();

        assert_eq!(query.bucket.as_deref(), Some("test-bucket"));
        assert_eq!(query.prefix.as_deref(), Some("logs/"));
        assert_eq!(query.limit, Some(100));
        assert_eq!(query.offset, Some(0));
    }

    #[test]
    fn test_parse_query_params_with_sizes() {
        let query_str = "min_size=1000&max_size=10000";
        let query = parse_query_params(query_str).unwrap();

        assert_eq!(query.min_size, Some(1000));
        assert_eq!(query.max_size, Some(10000));
    }

    #[test]
    fn test_parse_query_params_with_tags() {
        let query_str = r#"tags={"Project":"analytics","Environment":"prod"}"#;
        let query = parse_query_params(query_str).unwrap();

        let tags = query.tags.unwrap();
        assert_eq!(tags.len(), 2);
        assert_eq!(tags.get("Project"), Some(&"analytics".to_string()));
        assert_eq!(tags.get("Environment"), Some(&"prod".to_string()));
    }

    #[test]
    fn test_parse_query_params_url_encoded() {
        let query_str = "prefix=path%2Fto%2Fobject&bucket=my%20bucket";
        let query = parse_query_params(query_str).unwrap();

        assert_eq!(query.prefix.as_deref(), Some("path/to/object"));
        assert_eq!(query.bucket.as_deref(), Some("my bucket"));
    }

    #[test]
    fn test_parse_query_params_invalid() {
        let query_str = "min_size=invalid";
        let result = parse_query_params(query_str);
        assert!(result.is_err());
    }
}
