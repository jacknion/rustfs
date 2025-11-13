# S3 元数据数据库集成 - 实施步骤详解

## 🎯 快速开始指南

### 前置条件
- ✅ PostgreSQL 16+ 已安装并运行
- ✅ RustFS 已配置数据库连接（`RUSTFS_DATABASE_URL`）
- ✅ Rust 1.85+ 工具链

---

## 📋 实施步骤

### 步骤 1：初始化数据库表结构

```bash
# 1. 连接到 PostgreSQL
psql -U rustfs_user -d rustfs_db

# 2. 执行表结构创建脚本
\i scripts/s3_metadata_schema.sql
```

**验证**：
```sql
-- 检查表是否创建成功
\dt s3_objects

-- 检查索引
\di s3_objects*

-- 验证 JSONB 功能
SELECT '{"Project": "test"}'::jsonb @> '{"Project": "test"}'::jsonb;
```

---

### 步骤 2：创建数据模型和 Repository

#### 2.1 创建目录结构

```bash
mkdir -p rustfs/src/storage/database/models
mkdir -p rustfs/src/storage/database/repositories
```

#### 2.2 实现数据模型

**文件：`rustfs/src/storage/database/models.rs`**

关键点：
- 使用 `#[derive(sqlx::FromRow)]` 自动映射数据库行
- JSONB 字段使用 `sqlx::types::Json<HashMap<String, String>>`
- 时间字段使用 `chrono::DateTime<chrono::Utc>`

#### 2.3 实现 Repository

**文件：`rustfs/src/storage/database/repositories/s3_objects.rs`**

关键 SQL 语句：

```sql
-- Upsert（插入或更新）
INSERT INTO s3_objects (...) 
VALUES (...)
ON CONFLICT (bucket, object_key) 
DO UPDATE SET ...

-- 标签查询（JSONB containment）
SELECT * FROM s3_objects 
WHERE tags @> '{"Project": "analytics"}'::jsonb

-- 前缀查询
SELECT * FROM s3_objects 
WHERE bucket = $1 AND object_key LIKE $2
```

---

### 步骤 3：实现元数据提取器

#### 3.1 分析 RustFS 现有数据结构

首先需要找到 RustFS 中对象元数据的数据结构：

```bash
# 查找 ObjectInfo 定义
grep -r "struct ObjectInfo" rustfs/

# 查找标签相关字段
grep -r "tags\|user_defined\|metadata" crates/ecstore/src/
```

#### 3.2 实现提取逻辑

**文件：`rustfs/src/storage/metadata_extractor.rs`**

```rust
impl MetadataExtractor {
    pub fn extract(
        bucket: &str,
        object_key: &str,
        object_info: &ObjectInfo,
    ) -> CreateS3Object {
        // 关键：从 ObjectInfo 中提取所有字段
        // 需要根据 RustFS 实际结构调整
        
        CreateS3Object {
            bucket: bucket.to_string(),
            object_key: object_key.to_string(),
            size_bytes: object_info.size as i64,
            last_modified: object_info.last_modified,
            etag: object_info.etag.clone(),
            // ... 其他字段
        }
    }
}
```

**调试技巧**：
```rust
// 在 put_object 中添加日志查看实际数据
tracing::debug!("ObjectInfo: {:?}", object_info);
```

---

### 步骤 4：实现异步同步服务

#### 4.1 创建同步服务

**文件：`rustfs/src/storage/database/sync_service.rs`**

架构设计：
```
┌─────────────┐
│ S3 操作     │
└──────┬──────┘
       │ send(event)
       ▼
┌─────────────────────┐
│ Unbounded Channel   │
└──────┬──────────────┘
       │ recv()
       ▼
┌─────────────────────┐
│ Background Worker   │ ← tokio::spawn
│ - batch write       │
│ - error retry       │
└─────────────────────┘
```

**关键代码**：

```rust
pub fn new() -> Self {
    let (tx, mut rx) = mpsc::unbounded_channel::<SyncEvent>();

    tokio::spawn(async move {
        let mut batch = Vec::new();
        let mut interval = tokio::time::interval(Duration::from_secs(1));

        loop {
            tokio::select! {
                Some(event) = rx.recv() => {
                    batch.push(event);
                    
                    // 批量写入（每 100 条或每秒）
                    if batch.len() >= 100 {
                        Self::flush_batch(&mut batch).await;
                    }
                }
                _ = interval.tick() => {
                    if !batch.is_empty() {
                        Self::flush_batch(&mut batch).await;
                    }
                }
            }
        }
    });

    Self { tx }
}
```

#### 4.2 初始化同步服务

**文件：`rustfs/src/main.rs`**

```rust
use crate::storage::database::sync_service::init_sync_service;

// 在数据库初始化后添加
if opt.database_url.is_some() {
    init_database_pool(db_config).await?;
    init_sync_service();  // 新增
    info!("Metadata sync service initialized");
}
```

---

### 步骤 5：Hook 到 S3 操作

#### 5.1 查找 PutObject 实现

```bash
# 查找 put_object 函数
grep -r "fn put_object" crates/ecstore/src/

# 可能的位置：
# crates/ecstore/src/store/mod.rs
# crates/ecstore/src/store_api.rs
```

#### 5.2 添加同步 Hook

**示例位置：`crates/ecstore/src/store/mod.rs`**

```rust
impl ECStore {
    pub async fn put_object(
        &self,
        bucket: &str,
        key: &str,
        data: &[u8],
        // ... 其他参数
    ) -> Result<ObjectInfo> {
        // 原有逻辑：写入磁盘
        let object_info = self.write_to_disk(bucket, key, data).await?;
        
        // 新增：同步到数据库（非阻塞）
        #[cfg(feature = "database-sync")]
        {
            use crate::storage::database::sync_service::get_sync_service;
            use crate::storage::metadata_extractor::MetadataExtractor;
            
            if let Some(sync) = get_sync_service() {
                let metadata = MetadataExtractor::extract(bucket, key, &object_info);
                sync.sync_object_created(metadata);
            }
        }
        
        Ok(object_info)
    }
}
```

#### 5.3 添加 Feature Flag（可选）

**文件：`Cargo.toml`**

```toml
[features]
default = []
database-sync = ["sqlx"]
```

这样可以在编译时选择是否启用数据库同步功能。

---

### 步骤 6：实现查询 API

#### 6.1 创建 Handler

**文件：`rustfs/src/admin/handlers/s3_metadata.rs`**

API 设计：

```
GET /rustfs/admin/v3/s3/metadata/query
Query Parameters:
  - bucket: string (optional)
  - prefix: string (optional)
  - tags: JSON string (optional) e.g., {"Project":"analytics"}
  - storage_class: string (optional)
  - limit: int (default: 100)
  - offset: int (default: 0)

Response:
{
  "objects": [
    {
      "bucket": "my-bucket",
      "key": "path/to/file.txt",
      "size": 1024,
      "last_modified": "2025-11-13T10:00:00Z",
      "etag": "abc123",
      "tags": {"Project": "analytics"},
      "storage_class": "STANDARD"
    }
  ],
  "total": 1,
  "limit": 100,
  "offset": 0
}
```

#### 6.2 注册路由

**文件：`rustfs/src/admin/mod.rs`**

```rust
// 添加导入
use handlers::s3_metadata::{
    QueryS3MetadataHandler, 
    QueryByTagsHandler,
    GetObjectTagsHandler,
};

// 在 make_admin_route 中注册
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

r.insert(
    Method::GET,
    format!("{}{}", ADMIN_PREFIX, "/v3/s3/metadata/tags/{bucket}/{key}").as_str(),
    AdminOperation(&GetObjectTagsHandler {}),
)?;
```

---

### 步骤 7：测试和验证

#### 7.1 单元测试

```bash
# 运行数据库相关测试
cargo test --package rustfs --lib database

# 运行集成测试
cargo test --package rustfs --test s3_metadata_integration
```

#### 7.2 手动测试

```bash
# 1. 启动 RustFS
export RUSTFS_DATABASE_URL="postgres://rustfs_user:rustfs_password@localhost:5432/rustfs_db"
cargo run --bin rustfs -- --volumes /tmp/data

# 2. 上传带标签的对象
aws s3api put-object \
  --endpoint-url http://localhost:9000 \
  --bucket test-bucket \
  --key test-file.txt \
  --body /tmp/test.txt \
  --tagging "Project=analytics&Environment=prod&Owner=alice"

# 3. 检查数据库
psql -U rustfs_user -d rustfs_db -c \
  "SELECT bucket, object_key, tags FROM s3_objects WHERE bucket = 'test-bucket';"

# 4. 查询 API 测试
curl "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?bucket=test-bucket" | jq

# 5. 标签查询
curl "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?tags={\"Project\":\"analytics\"}" | jq

# 6. 验证删除同步
aws s3api delete-object \
  --endpoint-url http://localhost:9000 \
  --bucket test-bucket \
  --key test-file.txt

psql -U rustfs_user -d rustfs_db -c \
  "SELECT COUNT(*) FROM s3_objects WHERE bucket = 'test-bucket' AND object_key = 'test-file.txt';"
# 应该返回 0
```

---

### 步骤 8：性能测试

#### 8.1 基准测试

```bash
# 生成测试数据
./scripts/generate_test_objects.sh 10000

# 运行性能测试
cargo bench --bench s3_metadata_query
```

#### 8.2 监控指标

```bash
# 查询性能
SELECT 
    COUNT(*) as total_objects,
    AVG(size_bytes) as avg_size,
    MAX(last_modified) as latest_object
FROM s3_objects;

# 索引使用情况
EXPLAIN ANALYZE 
SELECT * FROM s3_objects 
WHERE tags @> '{"Project": "analytics"}'::jsonb;

# 连接池状态
SELECT * FROM pg_stat_activity WHERE datname = 'rustfs_db';
```

---

## 🐛 常见问题排查

### 问题 1：元数据未同步到数据库

**检查清单**：
```bash
# 1. 数据库连接是否正常
curl http://localhost:9000/rustfs/admin/v3/database/health

# 2. 同步服务是否初始化
# 在 main.rs 添加日志确认

# 3. 检查错误日志
tail -f logs/rustfs.log | grep "Failed to sync"

# 4. 手动测试 Repository
cargo test test_upsert_object -- --nocapture
```

### 问题 2：查询性能慢

**优化步骤**：
```sql
-- 1. 检查索引是否生效
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM s3_objects WHERE tags @> '{"Project": "test"}'::jsonb;

-- 2. 重建索引
REINDEX INDEX idx_tags_gin;

-- 3. 更新统计信息
ANALYZE s3_objects;

-- 4. 考虑分区（大数据量）
CREATE TABLE s3_objects_partitioned (
    LIKE s3_objects INCLUDING ALL
) PARTITION BY HASH (bucket);
```

### 问题 3：JSONB 查询不正确

**常见错误**：
```sql
-- ❌ 错误：使用字符串比较
WHERE tags::text LIKE '%Project%'

-- ✅ 正确：使用 JSONB containment
WHERE tags @> '{"Project": "analytics"}'::jsonb

-- ✅ 正确：检查键存在
WHERE tags ? 'Project'

-- ✅ 正确：值模糊匹配
WHERE tags->>'Project' LIKE '%anal%'
```

---

## 📊 监控和告警

### Prometheus Metrics

```rust
// metrics.rs
use prometheus::{Histogram, IntCounter, IntGauge};

lazy_static! {
    static ref DB_SYNC_DURATION: Histogram = register_histogram!(
        "rustfs_db_sync_duration_seconds",
        "Database sync operation duration"
    ).unwrap();
    
    static ref DB_SYNC_FAILURES: IntCounter = register_int_counter!(
        "rustfs_db_sync_failures_total",
        "Total number of database sync failures"
    ).unwrap();
    
    static ref DB_QUERY_DURATION: Histogram = register_histogram!(
        "rustfs_db_query_duration_seconds",
        "Database query duration"
    ).unwrap();
}
```

### Grafana Dashboard

```json
{
  "panels": [
    {
      "title": "Database Sync Latency",
      "targets": [
        {
          "expr": "rate(rustfs_db_sync_duration_seconds_sum[5m]) / rate(rustfs_db_sync_duration_seconds_count[5m])"
        }
      ]
    },
    {
      "title": "Sync Failures",
      "targets": [
        {
          "expr": "rate(rustfs_db_sync_failures_total[5m])"
        }
      ]
    }
  ]
}
```

---

## 🚀 部署检查清单

- [ ] PostgreSQL 16+ 已安装
- [ ] 数据库表结构已创建
- [ ] 索引已创建并生效
- [ ] 环境变量已配置（`RUSTFS_DATABASE_URL`）
- [ ] 同步服务已初始化
- [ ] API 路由已注册
- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] 性能测试满足要求（<100ms 查询）
- [ ] 监控指标已配置
- [ ] 文档已更新

---

## 📚 下一步优化

1. **批量同步优化**：实现批量 upsert，减少数据库往返
2. **读写分离**：查询走 PostgreSQL 从库
3. **缓存层**：使用 Redis 缓存热点查询
4. **全文搜索**：集成 Elasticsearch 支持更复杂的查询
5. **数据归档**：定期归档老数据到对象存储

---

## 🆘 获取帮助

- 查看详细设计文档：`docs/S3_METADATA_DATABASE_DESIGN.md`
- 查看 API 文档：`docs/DATABASE.md`
- GitHub Issues：提交 bug 报告或功能请求
