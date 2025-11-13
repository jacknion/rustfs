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

use super::Operation;
use crate::storage::database::get_database_pool;
use http::HeaderMap;
use hyper::StatusCode;
use matchit::Params;
use s3s::{Body, S3Request, S3Response, S3Result, s3_error};
use serde::Serialize;
use tracing::{error, info, warn};

/// Database health check handler
///
/// Checks if the database connection pool is initialized and healthy
pub struct DatabaseHealthHandler {}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DatabaseHealthResponse {
    status: String,
    connected: bool,
    message: String,
    timestamp: String,
}

#[async_trait::async_trait]
impl Operation for DatabaseHealthHandler {
    async fn call(&self, _req: S3Request<Body>, _params: Params<'_, '_>) -> S3Result<S3Response<(StatusCode, Body)>> {
        info!(
            target: "rustfs::admin::handlers::database",
            "Handling database health check request"
        );

        let (connected, message) = match get_database_pool() {
            Some(pool) => {
                // Test the connection
                match sqlx::query("SELECT 1").execute(pool).await {
                    Ok(_) => (true, "Database connection is healthy".to_string()),
                    Err(e) => {
                        error!(
                            target: "rustfs::admin::handlers::database",
                            error = %e,
                            "Database connection test failed"
                        );
                        (false, format!("Database connection test failed: {e}"))
                    }
                }
            }
            None => {
                warn!(
                    target: "rustfs::admin::handlers::database",
                    "Database pool not initialized"
                );
                (false, "Database not configured or initialized".to_string())
            }
        };

        let response = DatabaseHealthResponse {
            status: if connected { "ok" } else { "error" }.to_string(),
            connected,
            message,
            timestamp: chrono::Utc::now().to_rfc3339(),
        };

        let body =
            serde_json::to_string(&response).map_err(|e| s3_error!(InternalError, "Failed to serialize response: {}", e))?;

        let mut headers = HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, "application/json".parse().unwrap());

        Ok(S3Response::with_headers((StatusCode::OK, Body::from(body)), headers))
    }
}

/// Example database query handler
///
/// Demonstrates how to use the database connection pool in handlers
pub struct DatabaseExampleQueryHandler {}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DatabaseExampleResponse {
    status: String,
    current_time: String,
    database_version: String,
    message: String,
}

#[async_trait::async_trait]
impl Operation for DatabaseExampleQueryHandler {
    async fn call(&self, _req: S3Request<Body>, _params: Params<'_, '_>) -> S3Result<S3Response<(StatusCode, Body)>> {
        info!(
            target: "rustfs::admin::handlers::database",
            "Handling database example query request"
        );

        let pool = get_database_pool().ok_or_else(|| s3_error!(InternalError, "Database not initialized"))?;

        // Example query: Get current timestamp and database version
        let row: (String, String) = sqlx::query_as("SELECT NOW()::TEXT as current_time, VERSION() as db_version")
            .fetch_one(pool)
            .await
            .map_err(|e| {
                error!(
                    target: "rustfs::admin::handlers::database",
                    error = %e,
                    "Database query failed"
                );
                s3_error!(InternalError, "Database query failed: {}", e)
            })?;

        let response = DatabaseExampleResponse {
            status: "success".to_string(),
            current_time: row.0,
            database_version: row.1,
            message: "Database query executed successfully".to_string(),
        };

        let body =
            serde_json::to_string(&response).map_err(|e| s3_error!(InternalError, "Failed to serialize response: {}", e))?;

        let mut headers = HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, "application/json".parse().unwrap());

        Ok(S3Response::with_headers((StatusCode::OK, Body::from(body)), headers))
    }
}
