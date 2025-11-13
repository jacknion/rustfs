# S3 对象元数据数据库集成开发方案

## 📋 项目概述

### 目标
在 RustFS 中集成 PostgreSQL 数据库，实现 S3 对象元数据的持久化存储和高效查询，支持基于标签（Tags）的复杂查询功能。

### 技术方案
- **数据库**：PostgreSQL 16+ (支持 JSONB)
- **ORM**：SQLx (异步、类型安全)
- **设计模式**：单表扁平化（适合中小规模 < 1 亿对象）

---

## 🏗️ 架构设计

### 数据流程图

```
┌─────────────────┐
│  S3 PUT/POST    │
│  (上传对象)      │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  RustFS Storage Layer               │
│  - 写入对象到磁盘                    │
│  - 提取元数据 (meta, tags, etc.)    │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Database Sync Service (NEW)        │
│  - 异步插入/更新 s3_objects 表      │
│  - 转换 tags 为 JSONB 格式          │
└─────────────────────────────────────┘

┌─────────────────┐
│  新增 Query API  │
│  (标签查询)      │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  PostgreSQL Query                   │
│  - JSONB 标签匹配                   │
│  - 复杂条件过滤                      │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  返回对象列表                        │
│  (bucket, key, metadata)            │
└─────────────────────────────────────┘
```

---

## 📊 数据库设计

### 核心表结构

```sql
-- S3 对象元数据表
CREATE TABLE s3_objects (
    -- 主键
    id BIGSERIAL PRIMARY KEY,
    
    -- S3 基本信息
    bucket TEXT NOT NULL,
    object_key TEXT NOT NULL,  -- 避免与SQL保留字冲突
    size_bytes BIGINT NOT NULL,
    last_modified TIMESTAMPTZ NOT NULL,
    etag TEXT NOT NULL,
    content_type TEXT,
    
    -- 存储相关
    storage_class VARCHAR(20) DEFAULT 'STANDARD',
    version_id TEXT,  -- 版本控制支持
    is_delete_marker BOOLEAN DEFAULT false,
    
    -- 核心：标签存储（JSONB格式）
    tags JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- 用户自定义元数据（x-amz-meta-*）
    user_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- 安全与合规
    is_encrypted BOOLEAN DEFAULT false,
    encryption_algorithm VARCHAR(50),
    retention_until TIMESTAMPTZ,
    legal_hold BOOLEAN DEFAULT false,
    
    -- 性能优化字段
    access_count BIGINT DEFAULT 0,
    last_accessed TIMESTAMPTZ,
    
    -- 时间戳
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 唯一约束：同一个 bucket 和 key 只能有一条记录（不考虑版本）
    CONSTRAINT unique_bucket_key UNIQUE (bucket, object_key)
);

-- 性能索引
CREATE INDEX idx_bucket_key ON s3_objects (bucket, object_key);
CREATE INDEX idx_tags_gin ON s3_objects USING GIN (tags);
CREATE INDEX idx_user_metadata_gin ON s3_objects USING GIN (user_metadata);
CREATE INDEX idx_last_modified ON s3_objects (last_modified DESC);
CREATE INDEX idx_bucket_storage_class ON s3_objects (bucket, storage_class);
CREATE INDEX idx_retention ON s3_objects (retention_until) WHERE retention_until IS NOT NULL;

-- 自动更新 updated_at 触发器
CREATE OR REPLACE FUNCTION update_s3_objects_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER s3_objects_updated_at
    BEFORE UPDATE ON s3_objects
    FOR EACH ROW
    EXECUTE FUNCTION update_s3_objects_updated_at();

-- 分区支持（可选，适用于大规模数据）
-- CREATE TABLE s3_objects_partitioned (
--     LIKE s3_objects INCLUDING ALL
-- ) PARTITION BY HASH (bucket);
```

### 辅助表（可选）

```sql
-- Bucket 统计信息（缓存表）
CREATE TABLE bucket_stats (
    bucket TEXT PRIMARY KEY,
    object_count BIGINT DEFAULT 0,
    total_size_bytes BIGINT DEFAULT 0,
    last_updated TIMESTAMPTZ DEFAULT NOW()
);

-- 热门标签统计
CREATE TABLE tag_statistics (
    tag_key TEXT PRIMARY KEY,
    usage_count BIGINT DEFAULT 0,
    last_seen TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 🔧 代码实现计划

### 第一阶段：数据库模块扩展（1-2天）

#### 1.1 数据模型定义

**文件：`rustfs/src/storage/database/models.rs`（新增）**

```rust
use serde::{Deserialize, Serialize};
use sqlx::types::Json;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct S3Object {
    pub id: i64,
    pub bucket: String,
    pub object_key: String,
    pub size_bytes: i64,
    pub last_modified: chrono::DateTime<chrono::Utc>,
    pub etag: String,
    pub content_type: Option<String>,
    pub storage_class: String,
    pub version_id: Option<String>,
    pub is_delete_marker: bool,
    
    // JSONB 字段
    pub tags: Json<HashMap<String, String>>,
    pub user_metadata: Json<HashMap<String, String>>,
    
    pub is_encrypted: bool,
    pub encryption_algorithm: Option<String>,
    pub retention_until: Option<chrono::DateTime<chrono::Utc>>,
    pub legal_hold: bool,
    
    pub access_count: i64,
    pub last_accessed: Option<chrono::DateTime<chrono::Utc>>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateS3Object {
    pub bucket: String,
    pub object_key: String,
    pub size_bytes: i64,
    pub last_modified: chrono::DateTime<chrono::Utc>,
    pub etag: String,
    pub content_type: Option<String>,
    pub storage_class: String,
    pub version_id: Option<String>,
    pub tags: HashMap<String, String>,
    pub user_metadata: HashMap<String, String>,
    pub is_encrypted: bool,
    pub encryption_algorithm: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct S3ObjectQuery {
    pub bucket: Option<String>,
    pub prefix: Option<String>,
    pub tags: Option<HashMap<String, String>>,  // 精确匹配
    pub tag_contains: Option<HashMap<String, String>>,  // 模糊匹配
    pub storage_class: Option<String>,
    pub modified_after: Option<chrono::DateTime<chrono::Utc>>,
    pub modified_before: Option<chrono::DateTime<chrono::Utc>>,
    pub min_size: Option<i64>,
    pub max_size: Option<i64>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}
```

#### 1.2 数据库操作层

**文件：`rustfs/src/storage/database/s3_objects.rs`（新增）**

```rust
use super::get_database_pool;
use crate::storage::database::models::{CreateS3Object, S3Object, S3ObjectQuery};
use sqlx::{PgPool, Result as SqlxResult};
use std::collections::HashMap;

pub struct S3ObjectRepository;

impl S3ObjectRepository {
    /// 插入或更新对象元数据
    pub async fn upsert(data: CreateS3Object) -> SqlxResult<S3Object> {
        let pool = get_database_pool()
            .ok_or_else(|| sqlx::Error::Configuration("Database not initialized".into()))?;

        let tags_json = serde_json::to_value(&data.tags).unwrap();
        let metadata_json = serde_json::to_value(&data.user_metadata).unwrap();

        sqlx::query_as!(
            S3Object,
            r#"
            INSERT INTO s3_objects (
                bucket, object_key, size_bytes, last_modified, etag, 
                content_type, storage_class, version_id, tags, user_metadata,
                is_encrypted, encryption_algorithm
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            ON CONFLICT (bucket, object_key) 
            DO UPDATE SET
                size_bytes = EXCLUDED.size_bytes,
                last_modified = EXCLUDED.last_modified,
                etag = EXCLUDED.etag,
                content_type = EXCLUDED.content_type,
                storage_class = EXCLUDED.storage_class,
                version_id = EXCLUDED.version_id,
                tags = EXCLUDED.tags,
                user_metadata = EXCLUDED.user_metadata,
                is_encrypted = EXCLUDED.is_encrypted,
                encryption_algorithm = EXCLUDED.encryption_algorithm
            RETURNING *
            "#,
            data.bucket,
            data.object_key,
            data.size_bytes,
            data.last_modified,
            data.etag,
            data.content_type,
            data.storage_class,
            data.version_id,
            tags_json,
            metadata_json,
            data.is_encrypted,
            data.encryption_algorithm
        )
        .fetch_one(pool)
        .await
    }

    /// 查询对象（支持复杂条件）
    pub async fn query(params: S3ObjectQuery) -> SqlxResult<Vec<S3Object>> {
        let pool = get_database_pool()
            .ok_or_else(|| sqlx::Error::Configuration("Database not initialized".into()))?;

        // 动态构建查询
        let mut query = String::from("SELECT * FROM s3_objects WHERE 1=1");
        let mut bind_params: Vec<Box<dyn sqlx::Encode<'_, sqlx::Postgres> + Send>> = Vec::new();
        
        // TODO: 使用 query builder 或 sqlx::query_builder
        // 这里简化为示例，实际需要使用参数化查询
        
        if let Some(bucket) = &params.bucket {
            query.push_str(&format!(" AND bucket = '{}'", bucket));
        }
        
        if let Some(prefix) = &params.prefix {
            query.push_str(&format!(" AND object_key LIKE '{}%'", prefix));
        }
        
        // JSONB 标签查询（精确匹配）
        if let Some(tags) = &params.tags {
            let tags_json = serde_json::to_string(tags).unwrap();
            query.push_str(&format!(" AND tags @> '{}'::jsonb", tags_json));
        }

        query.push_str(&format!(" LIMIT {}", params.limit.unwrap_or(100)));
        query.push_str(&format!(" OFFSET {}", params.offset.unwrap_or(0)));

        sqlx::query_as(&query).fetch_all(pool).await
    }

    /// 删除对象元数据
    pub async fn delete(bucket: &str, object_key: &str) -> SqlxResult<bool> {
        let pool = get_database_pool()
            .ok_or_else(|| sqlx::Error::Configuration("Database not initialized".into()))?;

        let result = sqlx::query!(
            "DELETE FROM s3_objects WHERE bucket = $1 AND object_key = $2",
            bucket,
            object_key
        )
        .execute(pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// 按标签查询（高级）
    pub async fn find_by_tags(
        bucket: Option<&str>,
        tags: HashMap<String, String>
    ) -> SqlxResult<Vec<S3Object>> {
        let pool = get_database_pool()
            .ok_or_else(|| sqlx::Error::Configuration("Database not initialized".into()))?;

        let tags_json = serde_json::to_value(&tags).unwrap();

        if let Some(bucket_name) = bucket {
            sqlx::query_as!(
                S3Object,
                r#"
                SELECT * FROM s3_objects 
                WHERE bucket = $1 AND tags @> $2::jsonb
                ORDER BY last_modified DESC
                LIMIT 1000
                "#,
                bucket_name,
                tags_json
            )
            .fetch_all(pool)
            .await
        } else {
            sqlx::query_as!(
                S3Object,
                r#"
                SELECT * FROM s3_objects 
                WHERE tags @> $1::jsonb
                ORDER BY last_modified DESC
                LIMIT 1000
                "#,
                tags_json
            )
            .fetch_all(pool)
            .await
        }
    }
}
```

### 第二阶段：S3 操作拦截器（2-3天）

#### 2.1 元数据提取器

**文件：`rustfs/src/storage/metadata_extractor.rs`（新增）**

```rust
use crate::storage::database::models::CreateS3Object;
use rustfs_ecstore::store_api::ObjectInfo;
use std::collections::HashMap;

pub struct MetadataExtractor;

impl MetadataExtractor {
    /// 从 S3 ObjectInfo 提取数据库需要的字段
    pub fn extract(
        bucket: &str,
        object_key: &str,
        object_info: &ObjectInfo,
    ) -> CreateS3Object {
        // 提取标签（从 S3 metadata 中解析）
        let tags = Self::parse_tags(object_info);
        
        // 提取用户自定义元数据（x-amz-meta-*）
        let user_metadata = Self::parse_user_metadata(object_info);

        CreateS3Object {
            bucket: bucket.to_string(),
            object_key: object_key.to_string(),
            size_bytes: object_info.size as i64,
            last_modified: object_info.last_modified,
            etag: object_info.etag.clone(),
            content_type: object_info.content_type.clone(),
            storage_class: object_info.storage_class.clone().unwrap_or_else(|| "STANDARD".to_string()),
            version_id: object_info.version_id.clone(),
            tags,
            user_metadata,
            is_encrypted: object_info.is_encrypted.unwrap_or(false),
            encryption_algorithm: object_info.encryption_algorithm.clone(),
        }
    }

    fn parse_tags(object_info: &ObjectInfo) -> HashMap<String, String> {
        // 从 ObjectInfo.user_defined 或 tags 字段提取
        // 实际实现需要根据 RustFS 的数据结构调整
        object_info.user_defined
            .as_ref()
            .and_then(|meta| meta.get("tags"))
            .and_then(|tags_str| serde_json::from_str(tags_str).ok())
            .unwrap_or_default()
    }

    fn parse_user_metadata(object_info: &ObjectInfo) -> HashMap<String, String> {
        object_info.user_defined
            .as_ref()
            .cloned()
            .unwrap_or_default()
    }
}
```

#### 2.2 异步同步服务

**文件：`rustfs/src/storage/database/sync_service.rs`（新增）**

```rust
use crate::storage::database::models::CreateS3Object;
use crate::storage::database::s3_objects::S3ObjectRepository;
use tokio::sync::mpsc;
use tracing::{error, info, warn};

pub enum SyncEvent {
    ObjectCreated(CreateS3Object),
    ObjectDeleted { bucket: String, object_key: String },
}

pub struct MetadataSyncService {
    tx: mpsc::UnboundedSender<SyncEvent>,
}

impl MetadataSyncService {
    pub fn new() -> Self {
        let (tx, mut rx) = mpsc::unbounded_channel::<SyncEvent>();

        // 后台任务处理同步
        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                match event {
                    SyncEvent::ObjectCreated(data) => {
                        if let Err(e) = S3ObjectRepository::upsert(data.clone()).await {
                            error!(
                                bucket = %data.bucket,
                                key = %data.object_key,
                                error = %e,
                                "Failed to sync object metadata to database"
                            );
                        } else {
                            info!(
                                bucket = %data.bucket,
                                key = %data.object_key,
                                "Object metadata synced to database"
                            );
                        }
                    }
                    SyncEvent::ObjectDeleted { bucket, object_key } => {
                        if let Err(e) = S3ObjectRepository::delete(&bucket, &object_key).await {
                            error!(
                                bucket = %bucket,
                                key = %object_key,
                                error = %e,
                                "Failed to delete object metadata from database"
                            );
                        }
                    }
                }
            }
        });

        Self { tx }
    }

    pub fn sync_object_created(&self, data: CreateS3Object) {
        if let Err(e) = self.tx.send(SyncEvent::ObjectCreated(data)) {
            warn!("Failed to send sync event: {}", e);
        }
    }

    pub fn sync_object_deleted(&self, bucket: String, object_key: String) {
        if let Err(e) = self.tx.send(SyncEvent::ObjectDeleted { bucket, object_key }) {
            warn!("Failed to send delete event: {}", e);
        }
    }
}

// 全局同步服务实例
use once_cell::sync::OnceCell;
static SYNC_SERVICE: OnceCell<MetadataSyncService> = OnceCell::new();

pub fn init_sync_service() {
    SYNC_SERVICE.get_or_init(MetadataSyncService::new);
}

pub fn get_sync_service() -> Option<&'static MetadataSyncService> {
    SYNC_SERVICE.get()
}
```

### 第三阶段：API 端点开发（2-3天）

#### 3.1 查询 API Handler

**文件：`rustfs/src/admin/handlers/s3_metadata.rs`（新增）**

```rust
use super::Operation;
use crate::storage::database::models::S3ObjectQuery;
use crate::storage::database::s3_objects::S3ObjectRepository;
use http::HeaderMap;
use hyper::StatusCode;
use matchit::Params;
use s3s::{Body, S3Request, S3Response, S3Result, s3_error};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{error, info};

/// 查询对象元数据 Handler
pub struct QueryS3MetadataHandler {}

#[derive(Debug, Deserialize)]
struct QueryParams {
    bucket: Option<String>,
    prefix: Option<String>,
    tags: Option<String>,  // JSON 字符串: {"key": "value"}
    storage_class: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
}

#[derive(Debug, Serialize)]
struct QueryResponse {
    objects: Vec<ObjectMetadata>,
    total: usize,
    limit: i64,
    offset: i64,
}

#[derive(Debug, Serialize)]
struct ObjectMetadata {
    bucket: String,
    key: String,
    size: i64,
    last_modified: String,
    etag: String,
    tags: HashMap<String, String>,
    storage_class: String,
}

#[async_trait::async_trait]
impl Operation for QueryS3MetadataHandler {
    async fn call(
        &self,
        req: S3Request<Body>,
        _params: Params<'_, '_>,
    ) -> S3Result<S3Response<(StatusCode, Body)>> {
        info!("Handling S3 metadata query request");

        // 解析查询参数
        let query_string = req.uri.query().unwrap_or("");
        let params: QueryParams = serde_urlencoded::from_str(query_string)
            .map_err(|e| s3_error!(InvalidRequest, "Invalid query parameters: {}", e))?;

        // 解析标签过滤器
        let tags = params.tags
            .as_ref()
            .and_then(|t| serde_json::from_str::<HashMap<String, String>>(t).ok());

        let query = S3ObjectQuery {
            bucket: params.bucket,
            prefix: params.prefix,
            tags,
            tag_contains: None,
            storage_class: params.storage_class,
            modified_after: None,
            modified_before: None,
            min_size: None,
            max_size: None,
            limit: Some(params.limit.unwrap_or(100)),
            offset: Some(params.offset.unwrap_or(0)),
        };

        // 查询数据库
        let objects = S3ObjectRepository::query(query.clone())
            .await
            .map_err(|e| {
                error!(error = %e, "Database query failed");
                s3_error!(InternalError, "Database query failed: {}", e)
            })?;

        // 转换为响应格式
        let response_objects: Vec<ObjectMetadata> = objects
            .into_iter()
            .map(|obj| ObjectMetadata {
                bucket: obj.bucket,
                key: obj.object_key,
                size: obj.size_bytes,
                last_modified: obj.last_modified.to_rfc3339(),
                etag: obj.etag,
                tags: obj.tags.0,
                storage_class: obj.storage_class,
            })
            .collect();

        let response = QueryResponse {
            total: response_objects.len(),
            objects: response_objects,
            limit: query.limit.unwrap_or(100),
            offset: query.offset.unwrap_or(0),
        };

        let body = serde_json::to_string(&response)
            .map_err(|e| s3_error!(InternalError, "Serialization failed: {}", e))?;

        let mut headers = HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, "application/json".parse().unwrap());

        Ok(S3Response::with_headers((StatusCode::OK, Body::from(body)), headers))
    }
}

/// 按标签查询 Handler
pub struct QueryByTagsHandler {}

#[async_trait::async_trait]
impl Operation for QueryByTagsHandler {
    async fn call(
        &self,
        mut req: S3Request<Body>,
        _params: Params<'_, '_>,
    ) -> S3Result<S3Response<(StatusCode, Body)>> {
        info!("Handling query by tags request");

        // 读取请求体（POST 方式）
        let body_bytes = hyper::body::to_bytes(req.body_mut())
            .await
            .map_err(|e| s3_error!(InvalidRequest, "Failed to read body: {}", e))?;

        let tags: HashMap<String, String> = serde_json::from_slice(&body_bytes)
            .map_err(|e| s3_error!(InvalidRequest, "Invalid JSON: {}", e))?;

        // 查询数据库
        let objects = S3ObjectRepository::find_by_tags(None, tags)
            .await
            .map_err(|e| s3_error!(InternalError, "Database query failed: {}", e))?;

        let response_objects: Vec<ObjectMetadata> = objects
            .into_iter()
            .map(|obj| ObjectMetadata {
                bucket: obj.bucket,
                key: obj.object_key,
                size: obj.size_bytes,
                last_modified: obj.last_modified.to_rfc3339(),
                etag: obj.etag,
                tags: obj.tags.0,
                storage_class: obj.storage_class,
            })
            .collect();

        let response = QueryResponse {
            total: response_objects.len(),
            objects: response_objects,
            limit: 1000,
            offset: 0,
        };

        let body = serde_json::to_string(&response)
            .map_err(|e| s3_error!(InternalError, "Serialization failed: {}", e))?;

        let mut headers = HeaderMap::new();
        headers.insert(http::header::CONTENT_TYPE, "application/json".parse().unwrap());

        Ok(S3Response::with_headers((StatusCode::OK, Body::from(body)), headers))
    }
}
```

#### 3.2 注册路由

**文件：`rustfs/src/admin/mod.rs`（修改）**

```rust
// 添加导入
use handlers::s3_metadata::{QueryS3MetadataHandler, QueryByTagsHandler};

// 在 make_admin_route 函数中添加路由
r.insert(
    Method::GET,
    format!("{}{}", ADMIN_PREFIX, "/v3/s3/metadata/query").as_str(),
    AdminOperation(&QueryS3MetadataHandler {}),
)?;

r.insert(
    Method::POST,
    format!("{}{}", ADMIN_PREFIX, "/v3/s3/metadata/query-by-tags").as_str(),
    AdminOperation(&QueryByTagsHandler {}),
)?;
```

### 第四阶段：集成到 S3 操作（3-4天）

#### 4.1 Hook 到 PutObject

**文件：`rustfs/src/storage/ecfs/mod.rs`（修改）**

```rust
use crate::storage::database::sync_service::get_sync_service;
use crate::storage::metadata_extractor::MetadataExtractor;

// 在 put_object 成功后添加
async fn put_object(...) -> Result<...> {
    // ... 原有逻辑 ...
    
    // 同步元数据到数据库（异步、非阻塞）
    if let Some(sync_service) = get_sync_service() {
        let metadata = MetadataExtractor::extract(bucket, key, &object_info);
        sync_service.sync_object_created(metadata);
    }
    
    Ok(...)
}
```

#### 4.2 Hook 到 DeleteObject

```rust
async fn delete_object(...) -> Result<...> {
    // ... 原有逻辑 ...
    
    // 从数据库删除元数据
    if let Some(sync_service) = get_sync_service() {
        sync_service.sync_object_deleted(bucket.to_string(), key.to_string());
    }
    
    Ok(())
}
```

---

## 🧪 测试计划

### 单元测试

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_upsert_object() {
        let data = CreateS3Object {
            bucket: "test-bucket".to_string(),
            object_key: "test.txt".to_string(),
            size_bytes: 1024,
            // ... 其他字段
        };

        let result = S3ObjectRepository::upsert(data).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_query_by_tags() {
        let mut tags = HashMap::new();
        tags.insert("env".to_string(), "prod".to_string());

        let result = S3ObjectRepository::find_by_tags(None, tags).await;
        assert!(result.is_ok());
    }
}
```

### 集成测试

```bash
# 1. 上传带标签的对象
aws s3api put-object \
  --bucket test-bucket \
  --key test-file.txt \
  --body ./test.txt \
  --tagging "Project=analytics&Environment=prod"

# 2. 查询标签
curl "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?tags={\"Project\":\"analytics\"}"

# 3. 验证响应
{
  "objects": [
    {
      "bucket": "test-bucket",
      "key": "test-file.txt",
      "size": 1024,
      "tags": {"Project": "analytics", "Environment": "prod"}
    }
  ]
}
```

---

## 📅 开发时间表

| 阶段 | 任务 | 预计时间 | 依赖 |
|------|------|----------|------|
| **第1周** | 数据库设计 + 模型定义 | 2天 | - |
| | 数据库操作层实现 | 2天 | 数据模型 |
| | 单元测试编写 | 1天 | 操作层 |
| **第2周** | 元数据提取器 | 1天 | - |
| | 异步同步服务 | 2天 | 提取器 |
| | Hook 到 S3 操作 | 2天 | 同步服务 |
| **第3周** | Query API 实现 | 2天 | 数据库层 |
| | 路由注册 + 中间件 | 1天 | API Handler |
| | 集成测试 | 2天 | 全部 |
| **第4周** | 性能优化 | 2天 | - |
| | 文档编写 | 1天 | - |
| | Code Review + 修复 | 2天 | - |

**总计：约 20 个工作日（4周）**

---

## ⚡ 性能优化策略

### 1. 批量写入
```rust
// 批量 upsert（每 N 秒或 M 条记录触发）
pub async fn batch_upsert(objects: Vec<CreateS3Object>) -> SqlxResult<()> {
    // 使用 PostgreSQL COPY 或批量 INSERT
}
```

### 2. 读写分离
```rust
// 使用 PostgreSQL 主从复制
// 查询走从库，写入走主库
```

### 3. 缓存层
```rust
// Redis 缓存热点查询
// TTL: 60秒
```

### 4. 分区表
```sql
-- 按 bucket 哈希分区
CREATE TABLE s3_objects_part1 PARTITION OF s3_objects
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
```

---

## 🔒 安全考虑

1. **权限控制**：所有查询 API 需要验证 IAM 权限
2. **SQL 注入防护**：使用参数化查询（sqlx 自动处理）
3. **敏感数据**：用户元数据可能包含敏感信息，需加密存储
4. **审计日志**：所有数据库操作记录到 audit_logs 表

---

## 📊 监控指标

```rust
// Prometheus metrics
- rustfs_db_sync_lag_seconds  // 同步延迟
- rustfs_db_query_duration_seconds  // 查询耗时
- rustfs_db_connection_pool_size  // 连接池大小
- rustfs_db_sync_failures_total  // 同步失败次数
```

---

## 🚀 部署清单

### 数据库迁移脚本
```bash
# scripts/migrate-db.sh
sqlx migrate run --source ./migrations
```

### 配置示例
```bash
export RUSTFS_DATABASE_URL="postgres://rustfs:pass@localhost:5432/rustfs"
export RUSTFS_DATABASE_MAX_CONNECTIONS=20
export RUSTFS_METADATA_SYNC_ENABLED=true  # 新增开关
```

### Docker Compose 更新
```yaml
services:
  rustfs:
    environment:
      RUSTFS_METADATA_SYNC_ENABLED: "true"
```

---

## ✅ 验收标准

- [ ] 数据库表创建成功，索引生效
- [ ] PutObject 后元数据自动同步到数据库
- [ ] DeleteObject 后数据库记录被删除
- [ ] Query API 支持标签精确匹配和模糊查询
- [ ] 查询响应时间 < 100ms (1000 条记录以内)
- [ ] 同步延迟 < 1秒
- [ ] 通过所有单元测试和集成测试
- [ ] 文档完整（API 文档 + 部署指南）

---

## 📚 参考资料

- [PostgreSQL JSONB 文档](https://www.postgresql.org/docs/current/datatype-json.html)
- [SQLx 官方文档](https://github.com/launchbadge/sqlx)
- [S3 Tagging API](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-tagging.html)
