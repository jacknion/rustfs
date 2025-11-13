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

//! Repository for S3 object metadata operations

use crate::storage::database::models::{CreateS3Object, S3Object, S3ObjectQuery, S3ObjectQueryResponse, S3ObjectMetadata};
use sqlx::{PgPool, Postgres, QueryBuilder};
use std::collections::HashMap;
use std::time::Instant;
use tracing::{debug, error, warn};

/// Repository for S3 object metadata database operations
pub struct S3ObjectRepository;

impl S3ObjectRepository {
    /// Insert or update an S3 object record (upsert)
    ///
    /// Uses PostgreSQL's ON CONFLICT clause to handle object overwrites atomically.
    ///
    /// # Arguments
    ///
    /// * `pool` - Database connection pool
    /// * `obj` - S3 object data to insert/update
    ///
    /// # Returns
    ///
    /// Returns the ID of the inserted/updated record
    pub async fn upsert(pool: &PgPool, obj: &CreateS3Object) -> Result<i64, sqlx::Error> {
        let tags_json = obj.tags.as_ref().map(|t| serde_json::to_value(t).ok()).flatten();
        let user_metadata_json = obj.user_metadata.as_ref().map(|m| serde_json::to_value(m).ok()).flatten();

        let result = sqlx::query_scalar::<_, i64>(
            r#"
            INSERT INTO s3_objects (
                bucket, object_key, version_id, size_bytes, content_type, etag,
                storage_class, encryption, tags, user_metadata, owner_id, last_modified
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            ON CONFLICT (bucket, object_key)
            DO UPDATE SET
                version_id = EXCLUDED.version_id,
                size_bytes = EXCLUDED.size_bytes,
                content_type = EXCLUDED.content_type,
                etag = EXCLUDED.etag,
                storage_class = EXCLUDED.storage_class,
                encryption = EXCLUDED.encryption,
                tags = EXCLUDED.tags,
                user_metadata = EXCLUDED.user_metadata,
                owner_id = EXCLUDED.owner_id,
                last_modified = EXCLUDED.last_modified,
                is_deleted = false,
                updated_at = CURRENT_TIMESTAMP
            RETURNING id
            "#,
        )
        .bind(&obj.bucket)
        .bind(&obj.object_key)
        .bind(&obj.version_id)
        .bind(obj.size_bytes)
        .bind(&obj.content_type)
        .bind(&obj.etag)
        .bind(&obj.storage_class)
        .bind(&obj.encryption)
        .bind(tags_json)
        .bind(user_metadata_json)
        .bind(&obj.owner_id)
        .bind(obj.last_modified)
        .fetch_one(pool)
        .await
        .inspect_err(|err| {
            error!(
                target: "rustfs::storage::database::repositories",
                bucket = %obj.bucket,
                object_key = %obj.object_key,
                error = %err,
                "Failed to upsert S3 object"
            );
        })?;

        debug!(
            target: "rustfs::storage::database::repositories",
            bucket = %obj.bucket,
            object_key = %obj.object_key,
            id = result,
            "Successfully upserted S3 object"
        );

        Ok(result)
    }

    /// Query S3 objects with flexible filters
    ///
    /// # Arguments
    ///
    /// * `pool` - Database connection pool
    /// * `query` - Query parameters for filtering
    ///
    /// # Returns
    ///
    /// Returns a response containing matched objects and metadata
    pub async fn query(pool: &PgPool, query: &S3ObjectQuery) -> Result<S3ObjectQueryResponse, sqlx::Error> {
        let start = Instant::now();

        // Build dynamic query
        let mut qb: QueryBuilder<Postgres> = QueryBuilder::new("SELECT * FROM s3_objects WHERE 1=1");

        // Apply filters
        if let Some(ref bucket) = query.bucket {
            qb.push(" AND bucket = ");
            qb.push_bind(bucket);
        }

        if let Some(ref prefix) = query.prefix {
            qb.push(" AND object_key LIKE ");
            qb.push_bind(format!("{}%", prefix));
        }

        if let Some(ref storage_class) = query.storage_class {
            qb.push(" AND storage_class = ");
            qb.push_bind(storage_class);
        }

        if let Some(ref encryption) = query.encryption {
            qb.push(" AND encryption = ");
            qb.push_bind(encryption);
        }

        if let Some(ref owner_id) = query.owner_id {
            qb.push(" AND owner_id = ");
            qb.push_bind(owner_id);
        }

        if let Some(min_size) = query.min_size {
            qb.push(" AND size_bytes >= ");
            qb.push_bind(min_size);
        }

        if let Some(max_size) = query.max_size {
            qb.push(" AND size_bytes <= ");
            qb.push_bind(max_size);
        }

        if let Some(ref modified_after) = query.modified_after {
            qb.push(" AND last_modified >= ");
            qb.push_bind(modified_after);
        }

        if let Some(ref modified_before) = query.modified_before {
            qb.push(" AND last_modified <= ");
            qb.push_bind(modified_before);
        }

        if !query.include_deleted {
            qb.push(" AND is_deleted = false");
        }

        // Apply tag filters if specified
        if let Some(ref tags) = query.tags {
            if !tags.is_empty() {
                let tags_json = serde_json::to_value(tags).unwrap_or_default();
                qb.push(" AND tags @> ");
                qb.push_bind(tags_json);
            }
        }

        // Order by last_modified descending
        qb.push(" ORDER BY last_modified DESC");

        // Apply pagination
        if let Some(limit) = query.limit {
            qb.push(" LIMIT ");
            qb.push_bind(limit);
        }

        if let Some(offset) = query.offset {
            qb.push(" OFFSET ");
            qb.push_bind(offset);
        }

        // Execute query
        let objects: Vec<S3Object> = qb.build_query_as().fetch_all(pool).await.inspect_err(|err| {
            error!(
                target: "rustfs::storage::database::repositories",
                error = %err,
                "Failed to query S3 objects"
            );
        })?;

        // Get total count (for pagination metadata)
        let total_count = Self::count_query(pool, query).await?;

        let query_time_ms = start.elapsed().as_millis() as u64;

        debug!(
            target: "rustfs::storage::database::repositories",
            returned = objects.len(),
            total = total_count,
            query_time_ms = query_time_ms,
            "Successfully queried S3 objects"
        );

        Ok(S3ObjectQueryResponse {
            metadata: S3ObjectMetadata {
                total_count,
                returned_count: objects.len(),
                offset: query.offset.unwrap_or(0),
                query_time_ms,
            },
            objects,
        })
    }

    /// Count total matching records for a query (used for pagination metadata)
    async fn count_query(pool: &PgPool, query: &S3ObjectQuery) -> Result<i64, sqlx::Error> {
        let mut qb: QueryBuilder<Postgres> = QueryBuilder::new("SELECT COUNT(*) FROM s3_objects WHERE 1=1");

        // Apply the same filters as the main query
        if let Some(ref bucket) = query.bucket {
            qb.push(" AND bucket = ");
            qb.push_bind(bucket);
        }

        if let Some(ref prefix) = query.prefix {
            qb.push(" AND object_key LIKE ");
            qb.push_bind(format!("{}%", prefix));
        }

        if let Some(ref storage_class) = query.storage_class {
            qb.push(" AND storage_class = ");
            qb.push_bind(storage_class);
        }

        if let Some(ref encryption) = query.encryption {
            qb.push(" AND encryption = ");
            qb.push_bind(encryption);
        }

        if let Some(ref owner_id) = query.owner_id {
            qb.push(" AND owner_id = ");
            qb.push_bind(owner_id);
        }

        if let Some(min_size) = query.min_size {
            qb.push(" AND size_bytes >= ");
            qb.push_bind(min_size);
        }

        if let Some(max_size) = query.max_size {
            qb.push(" AND size_bytes <= ");
            qb.push_bind(max_size);
        }

        if let Some(ref modified_after) = query.modified_after {
            qb.push(" AND last_modified >= ");
            qb.push_bind(modified_after);
        }

        if let Some(ref modified_before) = query.modified_before {
            qb.push(" AND last_modified <= ");
            qb.push_bind(modified_before);
        }

        if !query.include_deleted {
            qb.push(" AND is_deleted = false");
        }

        if let Some(ref tags) = query.tags {
            if !tags.is_empty() {
                let tags_json = serde_json::to_value(tags).unwrap_or_default();
                qb.push(" AND tags @> ");
                qb.push_bind(tags_json);
            }
        }

        let count: i64 = qb.build_query_scalar().fetch_one(pool).await?;
        Ok(count)
    }

    /// Find S3 objects by tags (shortcut method for tag-based queries)
    ///
    /// # Arguments
    ///
    /// * `pool` - Database connection pool
    /// * `tags` - Tags to search for (all tags must match)
    /// * `limit` - Maximum number of results
    ///
    /// # Returns
    ///
    /// Returns a list of matching S3 objects
    pub async fn find_by_tags(
        pool: &PgPool,
        tags: &HashMap<String, String>,
        limit: Option<i64>,
    ) -> Result<Vec<S3Object>, sqlx::Error> {
        let query = S3ObjectQuery {
            tags: Some(tags.clone()),
            limit,
            include_deleted: false,
            ..Default::default()
        };

        let response = Self::query(pool, &query).await?;
        Ok(response.objects)
    }

    /// Mark an S3 object as deleted (soft delete)
    ///
    /// # Arguments
    ///
    /// * `pool` - Database connection pool
    /// * `bucket` - Bucket name
    /// * `object_key` - Object key
    ///
    /// # Returns
    ///
    /// Returns the number of affected rows
    pub async fn delete(pool: &PgPool, bucket: &str, object_key: &str) -> Result<u64, sqlx::Error> {
        let result = sqlx::query(
            r#"
            UPDATE s3_objects
            SET is_deleted = true, updated_at = CURRENT_TIMESTAMP
            WHERE bucket = $1 AND object_key = $2 AND is_deleted = false
            "#,
        )
        .bind(bucket)
        .bind(object_key)
        .execute(pool)
        .await
        .inspect_err(|err| {
            error!(
                target: "rustfs::storage::database::repositories",
                bucket = %bucket,
                object_key = %object_key,
                error = %err,
                "Failed to delete S3 object"
            );
        })?;

        let rows_affected = result.rows_affected();

        if rows_affected > 0 {
            debug!(
                target: "rustfs::storage::database::repositories",
                bucket = %bucket,
                object_key = %object_key,
                rows_affected = rows_affected,
                "Successfully deleted S3 object"
            );
        } else {
            warn!(
                target: "rustfs::storage::database::repositories",
                bucket = %bucket,
                object_key = %object_key,
                "No S3 object found to delete"
            );
        }

        Ok(rows_affected)
    }

    /// Permanently remove deleted objects (hard delete)
    ///
    /// This should be called periodically by a cleanup job.
    ///
    /// # Arguments
    ///
    /// * `pool` - Database connection pool
    /// * `days_old` - Delete objects that were soft-deleted this many days ago
    ///
    /// # Returns
    ///
    /// Returns the number of permanently deleted rows
    pub async fn purge_deleted(pool: &PgPool, days_old: i32) -> Result<u64, sqlx::Error> {
        let result = sqlx::query(
            r#"
            DELETE FROM s3_objects
            WHERE is_deleted = true
            AND updated_at < CURRENT_TIMESTAMP - INTERVAL '1 day' * $1
            "#,
        )
        .bind(days_old)
        .execute(pool)
        .await
        .inspect_err(|err| {
            error!(
                target: "rustfs::storage::database::repositories",
                days_old = days_old,
                error = %err,
                "Failed to purge deleted S3 objects"
            );
        })?;

        let rows_affected = result.rows_affected();

        debug!(
            target: "rustfs::storage::database::repositories",
            days_old = days_old,
            rows_affected = rows_affected,
            "Successfully purged deleted S3 objects"
        );

        Ok(rows_affected)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn test_query_builder_construction() {
        let query = S3ObjectQuery {
            bucket: Some("test-bucket".to_string()),
            prefix: Some("logs/".to_string()),
            min_size: Some(1000),
            max_size: Some(10000),
            limit: Some(100),
            offset: Some(0),
            ..Default::default()
        };

        assert_eq!(query.bucket.as_deref(), Some("test-bucket"));
        assert_eq!(query.limit, Some(100));
    }

    #[test]
    fn test_create_s3_object_construction() {
        let obj = CreateS3Object {
            bucket: "my-bucket".to_string(),
            object_key: "path/file.txt".to_string(),
            version_id: None,
            size_bytes: 2048,
            content_type: Some("text/plain".to_string()),
            etag: Some("etag123".to_string()),
            storage_class: Some("STANDARD".to_string()),
            encryption: None,
            tags: None,
            user_metadata: None,
            owner_id: Some("user-789".to_string()),
            last_modified: Utc::now(),
        };

        assert_eq!(obj.bucket, "my-bucket");
        assert_eq!(obj.size_bytes, 2048);
    }
}
