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

//! Metadata sync service health check API

// Allow unused code during development - will be used after route registration
#![allow(dead_code)]

use super::Operation;
use crate::storage::database::get_sync_stats;
use http::HeaderMap;
use hyper::StatusCode;
use matchit::Params;
use s3s::{Body, S3Request, S3Response, S3Result};
use serde::Serialize;
use tracing::info;

/// Health check response
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct HealthCheckResponse {
    /// Service status: healthy, degraded, or unhealthy
    status: String,

    /// Metadata sync statistics
    sync_stats: Option<SyncStats>,

    /// Human-readable message
    message: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SyncStats {
    /// Total successful upserts
    upsert_success: u64,

    /// Total failed upserts
    upsert_failed: u64,

    /// Total successful deletes
    delete_success: u64,

    /// Total failed deletes
    delete_failed: u64,

    /// Total events dropped (channel full)
    events_dropped: u64,

    /// Total events processed
    total_processed: u64,

    /// Total failures
    total_failed: u64,

    /// Success rate (0.0 to 1.0)
    success_rate: f64,
}

/// Metadata sync service health check handler
///
/// GET /rustfs/admin/v3/sync/health
///
/// Returns:
/// - 200 OK: Service is healthy (success rate > 95%, dropped events < 1000)
/// - 503 Service Unavailable: Service is unhealthy or not initialized
pub struct SyncHealthCheckHandler;

#[async_trait::async_trait]
impl Operation for SyncHealthCheckHandler {
    async fn call(&self, _req: S3Request<Body>, _params: Params<'_, '_>) -> S3Result<S3Response<(StatusCode, Body)>> {
        info!(
            target: "rustfs::admin::handlers::sync_health",
            "Handling sync service health check request"
        );

        let response = match get_sync_stats() {
            Some(snapshot) => {
                let sync_stats = SyncStats {
                    upsert_success: snapshot.upsert_success,
                    upsert_failed: snapshot.upsert_failed,
                    delete_success: snapshot.delete_success,
                    delete_failed: snapshot.delete_failed,
                    events_dropped: snapshot.events_dropped,
                    total_processed: snapshot.total_processed(),
                    total_failed: snapshot.total_failed(),
                    success_rate: snapshot.success_rate(),
                };

                let (status, message, http_status) = if snapshot.is_healthy() {
                    ("healthy", "Metadata sync service is operating normally".to_string(), StatusCode::OK)
                } else if snapshot.success_rate() > 0.80 {
                    (
                        "degraded",
                        format!(
                            "Metadata sync service is degraded (success rate: {:.1}%, dropped: {})",
                            snapshot.success_rate() * 100.0,
                            snapshot.events_dropped
                        ),
                        StatusCode::OK,
                    )
                } else {
                    (
                        "unhealthy",
                        format!(
                            "Metadata sync service is unhealthy (success rate: {:.1}%, dropped: {})",
                            snapshot.success_rate() * 100.0,
                            snapshot.events_dropped
                        ),
                        StatusCode::SERVICE_UNAVAILABLE,
                    )
                };

                let response_body = HealthCheckResponse {
                    status: status.to_string(),
                    sync_stats: Some(sync_stats),
                    message,
                };

                (http_status, response_body)
            }
            None => {
                let response_body = HealthCheckResponse {
                    status: "unavailable".to_string(),
                    sync_stats: None,
                    message: "Metadata sync service is not initialized".to_string(),
                };

                (StatusCode::SERVICE_UNAVAILABLE, response_body)
            }
        };

        let (status_code, response_body) = response;
        let body = serde_json::to_string(&response_body)
            .unwrap_or_else(|_| r#"{"status":"error","message":"Failed to serialize response"}"#.to_string());

        let mut headers = HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, "application/json".parse().unwrap());

        Ok(S3Response::with_headers((status_code, Body::from(body)), headers))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_health_check_response_serialization() {
        let response = HealthCheckResponse {
            status: "healthy".to_string(),
            sync_stats: Some(SyncStats {
                upsert_success: 100,
                upsert_failed: 5,
                delete_success: 20,
                delete_failed: 1,
                events_dropped: 0,
                total_processed: 120,
                total_failed: 6,
                success_rate: 0.952,
            }),
            message: "Service is healthy".to_string(),
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("healthy"));
        assert!(json.contains("syncStats"));
    }
}
