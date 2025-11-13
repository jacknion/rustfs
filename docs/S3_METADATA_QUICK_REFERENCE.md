# S3 元数据数据库集成 - 快速参考

## 📋 最近更新

**最后更新**：2025-11-13

**重要变更**：
- ✅ **Schema 迁移**：所有表迁移到独立的 `rustfs` schema，避免命名冲突
- ✅ **自动建表**：首次启动自动检测并创建数据库表，无需手动执行 SQL 脚本
- ✅ **删除同步**：支持单个和批量删除操作的自动元数据同步
- ✅ **软删除策略**：删除操作使用软删除（`is_deleted=true`），保留审计记录
- ✅ **统计视图**：新增 `bucket_stats` 和 `tag_statistics` 视图

**升级提示**：
- 如果从旧版本升级，需要手动迁移数据到 `rustfs` schema
- 所有 SQL 查询需要使用 `rustfs.s3_objects` 而非 `public.s3_objects`
- 查询时建议添加 `is_deleted = false` 过滤软删除的对象

---

## 🚀 快速开始（3 分钟）

```bash
# 1. 配置数据库连接（支持自动建表）
export RUSTFS_DATABASE_URL="postgres://rustfs_user:password@localhost:5432/rustfs_db"
export RUSTFS_DATABASE_MAX_CONNECTIONS=20

# 2. 启动 RustFS（首次启动会自动创建 rustfs schema 和所有表）
./rustfs server --config config.yaml

# 或者使用 cargo 运行
cargo run --bin rustfs -- --volumes /data
```

**注意**：
- ✅ 无需手动执行 SQL 脚本，RustFS 会自动检测并创建数据库表
- ✅ 所有表都在独立的 `rustfs` schema 中，避免命名冲突
- ✅ 首次启动会看到日志：`Database schema created successfully in rustfs schema`

### 手动初始化（可选）

如果需要手动控制，可以提前执行：

```bash
psql -U rustfs_user -d rustfs_db -f scripts/s3_metadata_schema.sql
```

## ⚠️ 重要提示

### Schema 命名空间

所有数据库对象都位于 `rustfs` schema 中，查询时**必须**使用 schema 前缀：

```sql
-- ✅ 正确
SELECT * FROM rustfs.s3_objects;

-- ❌ 错误（除非设置了 search_path）
SELECT * FROM s3_objects;
```

### 软删除过滤

查询活跃对象时，记得过滤软删除的记录：

```sql
-- ✅ 推荐（只查询未删除的对象）
SELECT * FROM rustfs.s3_objects WHERE is_deleted = false;

-- ⚠️ 不推荐（包含软删除的对象）
SELECT * FROM rustfs.s3_objects;
```

### 自动建表验证

首次启动后，验证表是否正确创建：

```bash
psql -U rustfs_user -d rustfs_db -c "\dt rustfs.*"
```

预期输出：
```
              List of relations
 Schema  |      Name       | Type  |    Owner    
---------+-----------------+-------+-------------
 rustfs  | bucket_stats    | table | rustfs_user
 rustfs  | s3_objects      | table | rustfs_user
 rustfs  | tag_statistics  | table | rustfs_user
```

## 📊 核心表结构

**Schema**: `rustfs` (所有表都在独立 schema 中)

```sql
rustfs.s3_objects (
    id                  BIGSERIAL PRIMARY KEY,
    bucket              TEXT NOT NULL,
    object_key          TEXT NOT NULL,
    size_bytes          BIGINT NOT NULL,
    last_modified       TIMESTAMPTZ NOT NULL,
    etag                TEXT NOT NULL,
    tags                JSONB NOT NULL DEFAULT '{}'::jsonb,  -- 核心：标签存储
    user_metadata       JSONB NOT NULL DEFAULT '{}'::jsonb,  -- x-amz-meta-*
    storage_class       VARCHAR(20) DEFAULT 'STANDARD',
    is_encrypted        BOOLEAN DEFAULT false,
    is_deleted          BOOLEAN DEFAULT false,  -- 软删除标记
    created_at          TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(bucket, object_key)
)
```

**重要索引**：
- `idx_bucket` - 按 bucket 查询
- `idx_tags_gin` - 标签查询（GIN 索引）
- `idx_bucket_prefix` - 前缀查询
- `idx_last_modified` - 按时间范围查询

**统计视图**：
- `rustfs.bucket_stats` - 每个 bucket 的统计信息
- `rustfs.tag_statistics` - 标签使用统计

## 🔍 常用查询

**注意**：所有查询都使用 `rustfs.s3_objects` 表（带 schema 前缀）

### 1. 按标签精确匹配

```sql
-- 查找 Project=analytics AND Environment=prod
SELECT bucket, object_key, tags 
FROM rustfs.s3_objects
WHERE tags @> '{"Project": "analytics", "Environment": "prod"}'::jsonb
  AND is_deleted = false;  -- 排除软删除的对象
```

### 2. 按标签键查询

```sql
-- 查找所有包含 "Project" 标签的对象
SELECT bucket, object_key, tags->>'Project' AS project
FROM rustfs.s3_objects
WHERE tags ? 'Project'
  AND is_deleted = false;
```

### 3. 标签值模糊匹配

```sql
-- 查找 Owner 包含 "alice" 的对象
SELECT bucket, object_key, tags
FROM rustfs.s3_objects
WHERE tags->>'Owner' LIKE '%alice%'
  AND is_deleted = false;
```

### 4. 复合查询

```sql
-- 查找特定 bucket + 标签 + 大小范围
SELECT bucket, object_key, size_bytes, tags
FROM rustfs.s3_objects
WHERE bucket = 'my-bucket'
  AND tags @> '{"Environment": "prod"}'::jsonb
  AND size_bytes > 1048576  -- > 1MB
  AND last_modified > NOW() - INTERVAL '7 days'
  AND is_deleted = false;
```

### 5. 前缀查询

```sql
-- 查找前缀为 "documents/" 的对象
SELECT bucket, object_key
FROM rustfs.s3_objects
WHERE bucket = 'my-bucket'
  AND object_key LIKE 'documents/%'
  AND is_deleted = false;
```

### 6. 查看软删除的对象

```sql
-- 查询最近删除的对象
SELECT bucket, object_key, updated_at AS deleted_at
FROM rustfs.s3_objects
WHERE is_deleted = true
ORDER BY updated_at DESC
LIMIT 100;
```

## 🌐 API 端点

### 1. 查询元数据

```bash
GET /rustfs/admin/v3/s3/metadata/query

Query Parameters:
  bucket: string (optional)
  prefix: string (optional)
  tags: JSON string (optional)
  storage_class: string (optional)
  limit: int (default: 100)
  offset: int (default: 0)

Example:
curl "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?bucket=my-bucket&tags={\"Project\":\"analytics\"}"
```

**响应示例**：
```json
{
  "objects": [
    {
      "bucket": "my-bucket",
      "key": "data/file.txt",
      "size": 1024,
      "last_modified": "2025-11-13T10:00:00Z",
      "etag": "abc123",
      "tags": {"Project": "analytics", "Environment": "prod"},
      "storage_class": "STANDARD"
    }
  ],
  "total": 1,
  "limit": 100,
  "offset": 0
}
```

### 2. 按标签查询（POST）

```bash
POST /rustfs/admin/v3/s3/metadata/query-by-tags
Content-Type: application/json

Body:
{
  "Project": "analytics",
  "Environment": "prod"
}

Example:
curl -X POST http://localhost:9000/rustfs/admin/v3/s3/metadata/query-by-tags \
  -H "Content-Type: application/json" \
  -d '{"Project":"analytics","Environment":"prod"}'
```

## 🔧 Rust 代码示例

### 插入/更新对象元数据

```rust
use crate::storage::database::models::CreateS3Object;
use crate::storage::database::s3_objects::S3ObjectRepository;

let data = CreateS3Object {
    bucket: "my-bucket".to_string(),
    object_key: "path/to/file.txt".to_string(),
    size_bytes: 1024,
    last_modified: chrono::Utc::now(),
    etag: "abc123".to_string(),
    content_type: Some("text/plain".to_string()),
    storage_class: "STANDARD".to_string(),
    version_id: None,
    tags: [
        ("Project".to_string(), "analytics".to_string()),
        ("Environment".to_string(), "prod".to_string()),
    ].into_iter().collect(),
    user_metadata: HashMap::new(),
    is_encrypted: false,
    encryption_algorithm: None,
};

let result = S3ObjectRepository::upsert(data).await?;
```

### 查询对象

```rust
use crate::storage::database::models::S3ObjectQuery;

let query = S3ObjectQuery {
    bucket: Some("my-bucket".to_string()),
    prefix: Some("documents/".to_string()),
    tags: Some([
        ("Project".to_string(), "analytics".to_string()),
    ].into_iter().collect()),
    limit: Some(100),
    offset: Some(0),
    ..Default::default()
};

let objects = S3ObjectRepository::query(query).await?;
```

### 按标签查询

```rust
let tags = [
    ("Environment".to_string(), "prod".to_string()),
    ("Owner".to_string(), "alice".to_string()),
].into_iter().collect();

let objects = S3ObjectRepository::find_by_tags(
    Some("my-bucket"),
    tags
).await?;
```

## 📈 性能优化

### 1. 索引检查

```sql
-- 检查 GIN 索引是否生效
EXPLAIN ANALYZE 
SELECT * FROM rustfs.s3_objects 
WHERE tags @> '{"Project": "analytics"}'::jsonb
  AND is_deleted = false;

-- 应该看到 "Index Scan using idx_tags_gin"
```

### 2. 统计信息更新

```sql
-- 定期更新（每天）
ANALYZE rustfs.s3_objects;
```

### 3. 索引重建

```sql
-- 如果性能下降
REINDEX INDEX CONCURRENTLY rustfs.idx_tags_gin;
```

### 4. 清理软删除的记录

```sql
-- 删除 90 天前软删除的记录（定期清理）
DELETE FROM rustfs.s3_objects 
WHERE is_deleted = true 
  AND updated_at < CURRENT_TIMESTAMP - INTERVAL '90 days';
```

## 🐛 故障排查

### 问题 1：元数据未同步

```bash
# 检查数据库连接
curl http://localhost:9000/rustfs/admin/v3/database/health

# 检查日志（查看同步状态）
tail -f logs/rustfs.log | grep -E "sync|database|metadata"

# 手动查询数据库
psql -U rustfs_user -d rustfs_db -c "SELECT COUNT(*) FROM rustfs.s3_objects WHERE is_deleted = false;"
```

### 问题 2：查询慢

```sql
-- 检查索引使用
SELECT 
    schemaname,
    indexname,
    idx_scan,
    idx_tup_read
FROM pg_stat_user_indexes
WHERE schemaname = 'rustfs' AND tablename = 's3_objects'
ORDER BY idx_scan DESC;

-- 更新统计信息
ANALYZE rustfs.s3_objects;
```

### 问题 3：JSONB 查询不工作

```sql
-- ❌ 错误
WHERE tags::text LIKE '%Project%'

-- ✅ 正确
WHERE tags @> '{"Project": "analytics"}'::jsonb
-- 或
WHERE tags ? 'Project'
-- 或
WHERE tags->>'Project' = 'analytics'
```

### 问题 4：删除对象后数据库仍有记录

这是正常的！RustFS 使用**软删除**策略：

```sql
-- 检查软删除的对象
SELECT bucket, object_key, updated_at AS deleted_at
FROM rustfs.s3_objects
WHERE is_deleted = true
ORDER BY updated_at DESC;

-- 手动清理软删除记录（谨慎！）
DELETE FROM rustfs.s3_objects 
WHERE is_deleted = true 
  AND updated_at < CURRENT_TIMESTAMP - INTERVAL '30 days';
```

## 📊 监控指标

```sql
-- 表大小
SELECT pg_size_pretty(pg_total_relation_size('rustfs.s3_objects'));

-- 活跃对象总数（排除软删除）
SELECT COUNT(*) FROM rustfs.s3_objects WHERE is_deleted = false;

-- 软删除对象总数
SELECT COUNT(*) FROM rustfs.s3_objects WHERE is_deleted = true;

-- 按 bucket 统计
SELECT 
    bucket, 
    COUNT(*) AS object_count,
    SUM(size_bytes) AS total_size,
    pg_size_pretty(SUM(size_bytes)) AS size_human
FROM rustfs.s3_objects 
WHERE is_deleted = false
GROUP BY bucket
ORDER BY total_size DESC;

-- 最热门的标签
SELECT 
    jsonb_object_keys(tags) AS tag_key,
    COUNT(*) AS usage_count
FROM rustfs.s3_objects 
WHERE is_deleted = false
GROUP BY tag_key 
ORDER BY usage_count DESC 
LIMIT 10;

-- 删除操作统计（最近 7 天）
SELECT 
    DATE(updated_at) AS delete_date,
    COUNT(*) AS deleted_count
FROM rustfs.s3_objects
WHERE is_deleted = true
  AND updated_at > CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY DATE(updated_at)
ORDER BY delete_date DESC;
```

## 🔐 安全

```sql
-- 创建只读用户
CREATE USER analyst WITH PASSWORD 'readonly_pass';
GRANT CONNECT ON DATABASE rustfs_db TO analyst;
GRANT USAGE ON SCHEMA rustfs TO analyst;
GRANT SELECT ON rustfs.s3_objects TO analyst;
GRANT SELECT ON rustfs.bucket_stats TO analyst;
GRANT SELECT ON rustfs.tag_statistics TO analyst;

-- 撤销写权限
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA rustfs FROM analyst;
```

## 📝 常用维护命令

```sql
-- 清空表（谨慎！）
TRUNCATE rustfs.s3_objects CASCADE;

-- 删除特定 bucket 的数据（硬删除）
DELETE FROM rustfs.s3_objects WHERE bucket = 'old-bucket';

-- 软删除特定 bucket 的对象
UPDATE rustfs.s3_objects 
SET is_deleted = true, updated_at = CURRENT_TIMESTAMP
WHERE bucket = 'archive-bucket' AND is_deleted = false;

-- 恢复软删除的对象
UPDATE rustfs.s3_objects 
SET is_deleted = false, updated_at = CURRENT_TIMESTAMP
WHERE bucket = 'my-bucket' AND object_key = 'file.txt';

-- 更新对象标签
UPDATE rustfs.s3_objects 
SET tags = tags || '{"NewTag": "value"}'::jsonb,
    updated_at = CURRENT_TIMESTAMP
WHERE bucket = 'my-bucket' AND object_key = 'file.txt';

-- 删除标签
UPDATE rustfs.s3_objects 
SET tags = tags - 'OldTag',
    updated_at = CURRENT_TIMESTAMP
WHERE bucket = 'my-bucket';

-- 清理旧的软删除记录（自动化脚本）
DELETE FROM rustfs.s3_objects 
WHERE is_deleted = true 
  AND updated_at < CURRENT_TIMESTAMP - INTERVAL '90 days';
```

## 🔄 删除同步功能

### 自动同步机制

当 S3 对象被删除时，RustFS 会**自动同步**删除数据库中的元数据：

| 操作 | 同步方式 | 代码位置 |
|------|---------|---------|
| **DeleteObject** | 软删除 | `rustfs/src/storage/ecfs.rs:1170` |
| **DeleteObjects**（批量） | 软删除 | `rustfs/src/storage/ecfs.rs:1423` |

### 软删除策略

```sql
-- 删除操作实际执行的是软删除
UPDATE rustfs.s3_objects
SET is_deleted = true, 
    updated_at = CURRENT_TIMESTAMP
WHERE bucket = $1 AND object_key = $2 AND is_deleted = false
```

**优势**：
- ✅ 保留审计记录
- ✅ 支持误删恢复
- ✅ 避免级联问题
- ✅ 便于调试分析

### 定期清理

设置 cron 任务清理旧的软删除记录：

```bash
# 每天凌晨 2 点清理 90 天前的软删除记录
0 2 * * * psql -U rustfs_user -d rustfs_db -c "DELETE FROM rustfs.s3_objects WHERE is_deleted = true AND updated_at < CURRENT_TIMESTAMP - INTERVAL '90 days';"
```

### 监控删除操作

```sql
-- 查看最近删除的对象
SELECT bucket, object_key, updated_at AS deleted_at
FROM rustfs.s3_objects
WHERE is_deleted = true
ORDER BY updated_at DESC
LIMIT 50;

-- 统计每日删除量
SELECT 
    DATE(updated_at) AS date,
    COUNT(*) AS deleted_count
FROM rustfs.s3_objects
WHERE is_deleted = true
  AND updated_at > CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY DATE(updated_at)
ORDER BY date DESC;
```

## 🎯 开发进度跟踪

- [x] 数据库表结构创建（使用独立 rustfs schema）
- [x] **自动建表功能**（首次启动自动创建）
- [x] 数据模型定义 (`models.rs`)
- [x] Repository 实现 (`s3_objects.rs`)
- [x] 元数据提取器 (`metadata_extractor.rs`)
- [x] 异步同步服务 (`sync_service.rs`)
- [x] Hook 到 PutObject（创建/更新同步）
- [x] **Hook 到 DeleteObject（单个删除同步）**
- [x] **Hook 到 DeleteObjects（批量删除同步）**
- [x] **软删除策略实现**
- [x] Query API Handler
- [x] 路由注册
- [ ] 单元测试
- [ ] 集成测试
- [ ] 性能测试（大规模数据）
- [x] 文档更新
- [x] **删除同步文档** (`METADATA_DELETE_SYNC.md`)
- [x] **自动建表文档** (`AUTO_SCHEMA_CREATION.md`)

## 📚 相关文档

- **设计文档**：`docs/S3_METADATA_DATABASE_DESIGN.md` - 架构设计和技术选型
- **实施指南**：`docs/S3_METADATA_IMPLEMENTATION_GUIDE.md` - 完整实施步骤
- **自动建表**：`docs/AUTO_SCHEMA_CREATION.md` - 自动创建 schema 功能说明
- **删除同步**：`docs/METADATA_DELETE_SYNC.md` - 删除操作同步机制详解
- **数据库文档**：`docs/DATABASE.md` - 通用数据库配置
- **SQL 脚本**：`scripts/s3_metadata_schema.sql` - 完整 schema 定义

## 🆘 获取帮助

```bash
# 检查错误日志
tail -f logs/rustfs.log | grep -E "error|ERROR|metadata"

# 数据库连接状态
psql -U rustfs_user -d rustfs_db -c "SELECT * FROM pg_stat_activity WHERE datname = 'rustfs_db';"

# 检查 schema 是否存在
psql -U rustfs_user -d rustfs_db -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'rustfs';"

# 检查表是否存在
psql -U rustfs_user -d rustfs_db -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'rustfs';"
```

**常见问题**：
- 启动时未自动建表 → 检查数据库连接和权限
- 查询返回空结果 → 检查 `is_deleted = false` 条件
- 性能下降 → 运行 `ANALYZE` 更新统计信息
- Schema 找不到 → 确认使用 `rustfs.` 前缀

**获取支持**：
- GitHub Issues：提交 bug 报告或功能请求
- 查看日志：`tail -f logs/rustfs.log`
- 检查数据库：`psql -U rustfs_user -d rustfs_db`
