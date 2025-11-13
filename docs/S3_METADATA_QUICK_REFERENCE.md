# S3 元数据数据库集成 - 快速参考

## 🚀 快速开始（5 分钟）

```bash
# 1. 初始化数据库
psql -U rustfs_user -d rustfs_db -f scripts/s3_metadata_schema.sql

# 2. 配置 RustFS
export RUSTFS_DATABASE_URL="postgres://rustfs_user:password@localhost:5432/rustfs_db"
export RUSTFS_DATABASE_MAX_CONNECTIONS=20

# 3. 启动 RustFS
cargo run --bin rustfs -- --volumes /data
```

## 📊 核心表结构

```sql
s3_objects (
    id                  BIGSERIAL PRIMARY KEY,
    bucket              TEXT NOT NULL,
    object_key          TEXT NOT NULL,
    size_bytes          BIGINT,
    last_modified       TIMESTAMPTZ,
    etag                TEXT,
    tags                JSONB,  -- 核心：标签存储
    user_metadata       JSONB,  -- x-amz-meta-*
    storage_class       VARCHAR(20),
    is_encrypted        BOOLEAN,
    UNIQUE(bucket, object_key)
)
```

## 🔍 常用查询

### 1. 按标签精确匹配

```sql
-- 查找 Project=analytics AND Environment=prod
SELECT bucket, object_key, tags 
FROM s3_objects
WHERE tags @> '{"Project": "analytics", "Environment": "prod"}'::jsonb;
```

### 2. 按标签键查询

```sql
-- 查找所有包含 "Project" 标签的对象
SELECT bucket, object_key, tags->>'Project' AS project
FROM s3_objects
WHERE tags ? 'Project';
```

### 3. 标签值模糊匹配

```sql
-- 查找 Owner 包含 "alice" 的对象
SELECT bucket, object_key, tags
FROM s3_objects
WHERE tags->>'Owner' LIKE '%alice%';
```

### 4. 复合查询

```sql
-- 查找特定 bucket + 标签 + 大小范围
SELECT bucket, object_key, size_bytes, tags
FROM s3_objects
WHERE bucket = 'my-bucket'
  AND tags @> '{"Environment": "prod"}'::jsonb
  AND size_bytes > 1048576  -- > 1MB
  AND last_modified > NOW() - INTERVAL '7 days';
```

### 5. 前缀查询

```sql
-- 查找前缀为 "documents/" 的对象
SELECT bucket, object_key
FROM s3_objects
WHERE bucket = 'my-bucket'
  AND object_key LIKE 'documents/%';
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
SELECT * FROM s3_objects 
WHERE tags @> '{"Project": "analytics"}'::jsonb;

-- 应该看到 "Index Scan using idx_tags_gin"
```

### 2. 统计信息更新

```sql
-- 定期更新（每天）
ANALYZE s3_objects;
```

### 3. 索引重建

```sql
-- 如果性能下降
REINDEX INDEX CONCURRENTLY idx_tags_gin;
```

## 🐛 故障排查

### 问题 1：元数据未同步

```bash
# 检查数据库连接
curl http://localhost:9000/rustfs/admin/v3/database/health

# 检查日志
tail -f logs/rustfs.log | grep "sync\|database"

# 手动查询数据库
psql -U rustfs_user -d rustfs_db -c "SELECT COUNT(*) FROM s3_objects;"
```

### 问题 2：查询慢

```sql
-- 检查索引使用
SELECT 
    indexname,
    idx_scan,
    idx_tup_read
FROM pg_stat_user_indexes
WHERE tablename = 's3_objects'
ORDER BY idx_scan DESC;

-- 更新统计信息
ANALYZE s3_objects;
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

## 📊 监控指标

```sql
-- 表大小
SELECT pg_size_pretty(pg_total_relation_size('s3_objects'));

-- 对象总数
SELECT COUNT(*) FROM s3_objects;

-- 按 bucket 统计
SELECT bucket, COUNT(*), SUM(size_bytes) 
FROM s3_objects 
GROUP BY bucket;

-- 最热门的标签
SELECT 
    jsonb_object_keys(tags) AS tag_key,
    COUNT(*) 
FROM s3_objects 
GROUP BY tag_key 
ORDER BY count DESC 
LIMIT 10;
```

## 🔐 安全

```sql
-- 创建只读用户
CREATE USER analyst WITH PASSWORD 'readonly_pass';
GRANT CONNECT ON DATABASE rustfs_db TO analyst;
GRANT SELECT ON s3_objects TO analyst;

-- 撤销写权限
REVOKE INSERT, UPDATE, DELETE ON s3_objects FROM analyst;
```

## 📝 常用维护命令

```sql
-- 清空表（谨慎！）
TRUNCATE s3_objects;

-- 删除特定 bucket 的数据
DELETE FROM s3_objects WHERE bucket = 'old-bucket';

-- 更新对象标签
UPDATE s3_objects 
SET tags = tags || '{"NewTag": "value"}'::jsonb
WHERE bucket = 'my-bucket' AND object_key = 'file.txt';

-- 删除标签
UPDATE s3_objects 
SET tags = tags - 'OldTag'
WHERE bucket = 'my-bucket';
```

## 🎯 开发进度跟踪

- [ ] 数据库表结构创建
- [ ] 数据模型定义 (`models.rs`)
- [ ] Repository 实现 (`s3_objects.rs`)
- [ ] 元数据提取器 (`metadata_extractor.rs`)
- [ ] 异步同步服务 (`sync_service.rs`)
- [ ] Hook 到 PutObject
- [ ] Hook 到 DeleteObject
- [ ] Query API Handler
- [ ] 路由注册
- [ ] 单元测试
- [ ] 集成测试
- [ ] 性能测试
- [ ] 文档更新

## 📚 相关文档

- 设计文档：`docs/S3_METADATA_DATABASE_DESIGN.md`
- 实施指南：`docs/S3_METADATA_IMPLEMENTATION_GUIDE.md`
- 数据库文档：`docs/DATABASE.md`
- SQL 脚本：`scripts/s3_metadata_schema.sql`

## 🆘 获取帮助

- 检查错误日志：`tail -f logs/rustfs.log`
- 数据库状态：`SELECT * FROM pg_stat_activity;`
- GitHub Issues：提交问题报告
