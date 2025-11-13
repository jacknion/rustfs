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

//! Database module for PostgreSQL integration
//!
//! This module provides connection pool management and data access for S3 object metadata.

// Allow unused code during development - will be used in later integration steps
#![allow(dead_code)]
#![allow(unused_imports)]

mod models;
pub mod repositories;
mod sync_service;

use once_cell::sync::OnceCell;
use sqlx::{PgPool, Pool, Postgres};
use std::sync::Arc;
use std::time::Duration;
use tracing::{error, info, warn};

// Re-export models
pub use models::{CreateS3Object, S3Object, S3ObjectMetadata, S3ObjectQuery, UpdateS3Object};

// Re-export repositories
pub use repositories::S3ObjectRepository;

// Re-export sync service
pub use sync_service::{
    MetadataSyncConfig, MetadataSyncEvent, SyncServiceSnapshot, get_sync_stats, init_metadata_sync_service, send_sync_event,
    shutdown_metadata_sync_service,
};

/// Global database connection pool
static DB_POOL: OnceCell<Arc<PgPool>> = OnceCell::new();

/// Database configuration
#[derive(Debug, Clone)]
pub struct DatabaseConfig {
    /// PostgreSQL connection URL
    pub url: String,
    /// Maximum number of connections in the pool
    pub max_connections: u32,
    /// Connection timeout in seconds
    pub connect_timeout: Duration,
    /// Idle timeout in seconds
    pub idle_timeout: Duration,
}

impl Default for DatabaseConfig {
    fn default() -> Self {
        Self {
            url: String::new(),
            max_connections: 10,
            connect_timeout: Duration::from_secs(30),
            idle_timeout: Duration::from_secs(600),
        }
    }
}

/// Initialize the global database connection pool
///
/// # Arguments
///
/// * `config` - Database configuration
///
/// # Returns
///
/// Returns `Ok(())` if successful, otherwise returns an error
pub async fn init_database_pool(config: DatabaseConfig) -> Result<(), sqlx::Error> {
    info!(
        target: "rustfs::storage::database",
        url = %mask_database_url(&config.url),
        max_connections = config.max_connections,
        "Initializing database connection pool"
    );

    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(config.max_connections)
        .acquire_timeout(config.connect_timeout)
        .idle_timeout(config.idle_timeout)
        .connect(&config.url)
        .await
        .inspect_err(|err| {
            error!(
                target: "rustfs::storage::database",
                error = %err,
                "Failed to connect to database"
            );
        })?;

    // Test the connection
    sqlx::query("SELECT 1").execute(&pool).await.inspect_err(|err| {
        error!(
            target: "rustfs::storage::database",
            error = %err,
            "Database connection test failed"
        );
    })?;

    info!(
        target: "rustfs::storage::database",
        "Database connection pool initialized successfully"
    );

    // Store the pool in global state
    DB_POOL
        .set(Arc::new(pool))
        .map_err(|_| sqlx::Error::Configuration("Database pool already initialized".into()))?;

    Ok(())
}

/// Get the global database connection pool
///
/// # Returns
///
/// Returns `Some(&Pool<Postgres>)` if the pool is initialized, otherwise returns `None`
pub fn get_database_pool() -> Option<&'static Pool<Postgres>> {
    DB_POOL.get().map(|arc| arc.as_ref())
}

/// Shutdown the database connection pool
pub async fn shutdown_database_pool() {
    if let Some(pool) = DB_POOL.get() {
        info!(
            target: "rustfs::storage::database",
            "Shutting down database connection pool"
        );
        pool.close().await;
    } else {
        warn!(
            target: "rustfs::storage::database",
            "Database pool not initialized, skipping shutdown"
        );
    }
}

/// Mask sensitive information in database URL for logging
fn mask_database_url(url: &str) -> String {
    if let Some(pos) = url.find("://") {
        if let Some(at_pos) = url[pos + 3..].find('@') {
            let scheme = &url[..pos + 3];
            let after_at = &url[pos + 3 + at_pos..];
            return format!("{scheme}***{after_at}");
        }
    }
    "***".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mask_database_url() {
        let url = "postgres://user:password@localhost:5432/rustfs";
        let masked = mask_database_url(url);
        assert_eq!(masked, "postgres://***@localhost:5432/rustfs");

        let url_no_auth = "postgres://localhost:5432/rustfs";
        let masked_no_auth = mask_database_url(url_no_auth);
        assert_eq!(masked_no_auth, "***");
    }

    #[test]
    fn test_default_config() {
        let config = DatabaseConfig::default();
        assert_eq!(config.max_connections, 10);
        assert_eq!(config.connect_timeout, Duration::from_secs(30));
        assert_eq!(config.idle_timeout, Duration::from_secs(600));
    }
}
