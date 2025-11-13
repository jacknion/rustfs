# RustFS S3 元数据数据库索引指南

## 📋 概述

本文档说明 `s3_objects` 表所需的全部索引，以及如何验证和创建它们。

## 🎯 索引优先级分类

### 🔴 高优先级（必需）

这些索引对系统性能至关重要，**必须在生产环境中创建**：

| 索引名称 | 类型 | 列 | 用途 | 预期查询性能 |
|---------|------|-----|------|-------------|
| `idx_bucket_key` | B-Tree | `(bucket, object_key)` | 快速定位对象 | < 1ms |
| `idx_tags_gin` | GIN | `tags` | 标签查询（核心功能） | < 50ms |
| `idx_last_modified` | B-Tree | `last_modified DESC` | 时间范围查询 | < 10ms |

**创建命令：**
```sql
CREATE INDEX IF NOT EXISTS idx_bucket_key 
    ON s3_objects (bucket, object_key);

CREATE INDEX IF NOT EXISTS idx_tags_gin 
    ON s3_objects USING GIN (tags);

CREATE INDEX IF NOT EXISTS idx_last_modified 
    ON s3_objects (last_modified DESC);
```

### 🟡 中优先级（推荐）

这些索引提升常见查询性能，**强烈推荐创建**：

| 索引名称 | 类型 | 列 | 用途 |
|---------|------|-----|------|
| `idx_user_metadata_gin` | GIN | `user_metadata` | 用户元数据查询 |
| `idx_created_at` | B-Tree | `created_at DESC` | 创建时间查询 |
| `idx_bucket_storage_class` | B-Tree | `(bucket, storage_class)` | 存储类型过滤 |
| `idx_etag` | B-Tree | `etag` | 去重查询 |

**创建命令：**
```sql
CREATE INDEX IF NOT EXISTS idx_user_metadata_gin 
    ON s3_objects USING GIN (user_metadata);

CREATE INDEX IF NOT EXISTS idx_created_at 
    ON s3_objects (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_bucket_storage_class 
    ON s3_objects (bucket, storage_class);

CREATE INDEX IF NOT EXISTS idx_etag 
    ON s3_objects (etag);
```

### 🟢 低优先级（可选）

条件索引，仅在需要时创建，可节省磁盘空间：

| 索引名称 | 类型 | 条件 | 用途 |
|---------|------|------|------|
| `idx_retention` | B-Tree | `WHERE retention_until IS NOT NULL` | 合规查询 |
| `idx_legal_hold` | B-Tree | `WHERE legal_hold = true` | 法定保留查询 |
| `idx_encrypted` | B-Tree | `WHERE is_encrypted = true` | 加密对象查询 |
| `idx_version` | B-Tree | `WHERE version_id IS NOT NULL` | 版本控制查询 |
| `idx_size_bytes` | B-Tree | `WHERE size_bytes > 1073741824` | 大文件查询 |

**创建命令：**
```sql
CREATE INDEX IF NOT EXISTS idx_retention 
    ON s3_objects (retention_until) 
    WHERE retention_until IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_legal_hold 
    ON s3_objects (bucket, object_key) 
    WHERE legal_hold = true;

CREATE INDEX IF NOT EXISTS idx_encrypted 
    ON s3_objects (bucket) 
    WHERE is_encrypted = true;

CREATE INDEX IF NOT EXISTS idx_version 
    ON s3_objects (bucket, object_key, version_id) 
    WHERE version_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_size_bytes 
    ON s3_objects (size_bytes) 
    WHERE size_bytes > 1073741824;
```

## ✅ 索引验证

### 方法1：使用验证脚本（推荐）

```bash
# 运行自动验证脚本
psql -U rustfs_user -d rustfs_db -f scripts/verify_indexes.sql

# 或者使用环境变量
export DATABASE_URL="postgres://rustfs_user:password@localhost:5432/rustfs_db"
psql $DATABASE_URL -f scripts/verify_indexes.sql
```

**输出示例：**
```
=========================================
RustFS S3 Metadata Database Index Verification
=========================================

1. Checking if s3_objects table exists...
 ✓ Table s3_objects exists

2. Checking required indexes...

Index Status Report:
-------------------
 index_name            | priority | status    | index_size
-----------------------+----------+-----------+------------
 idx_bucket_key        | HIGH     | ✓ EXISTS  | 2048 kB
 idx_tags_gin          | HIGH     | ✓ EXISTS  | 4096 kB
 idx_last_modified     | HIGH     | ✓ EXISTS  | 1024 kB
 idx_user_metadata_gin | MEDIUM   | ✗ MISSING | N/A
 ...

Status: ⚠ WARNING - Some optional indexes missing
```

### 方法2：手动检查

```sql
-- 列出所有索引
SELECT 
    indexname,
    indexdef,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_indexes
WHERE tablename = 's3_objects'
ORDER BY indexname;

-- 检查特定索引
SELECT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE tablename = 's3_objects' AND indexname = 'idx_tags_gin'
) AS tags_index_exists;
```

### 方法3：查看索引使用情况

```sql
-- 查看索引使用统计
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE tablename = 's3_objects'
ORDER BY idx_scan DESC;
```

## 🛠️ 常见问题排查

### 问题1：索引未创建

**症状：** 查询速度慢，EXPLAIN 显示 "Seq Scan"

**解决方案：**
```sql
-- 创建缺失的索引
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tags_gin 
    ON s3_objects USING GIN (tags);

-- 使用 CONCURRENTLY 避免锁表
```

### 问题2：索引膨胀

**症状：** 索引大小异常增长

**解决方案：**
```sql
-- 查看索引膨胀
SELECT 
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_indexes
WHERE tablename = 's3_objects';

-- 重建索引
REINDEX INDEX CONCURRENTLY idx_tags_gin;
```

### 问题3：统计信息过期

**症状：** 查询计划不优

**解决方案：**
```sql
-- 更新统计信息
ANALYZE s3_objects;

-- 查看上次分析时间
SELECT 
    schemaname,
    tablename,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE tablename = 's3_objects';
```

## 📊 性能基准

### 预期查询性能（1000万条记录）

| 查询类型 | 无索引 | 有索引 | 改善 |
|---------|-------|--------|------|
| 按 bucket+key 查找 | 5000ms | < 1ms | 5000x |
| 标签精确匹配 | 8000ms | < 50ms | 160x |
| 时间范围查询 | 3000ms | < 10ms | 300x |
| 大小范围查询 | 4000ms | < 20ms | 200x |

### 索引空间占用（估算）

| 索引 | 100万对象 | 1000万对象 | 1亿对象 |
|-----|----------|-----------|---------|
| idx_bucket_key | ~50 MB | ~500 MB | ~5 GB |
| idx_tags_gin | ~200 MB | ~2 GB | ~20 GB |
| idx_last_modified | ~30 MB | ~300 MB | ~3 GB |
| **总计** | **~300 MB** | **~3 GB** | **~30 GB** |

## 🔧 维护建议

### 日常维护

```bash
# 每天运行（cron job）
psql $DATABASE_URL -c "ANALYZE s3_objects;"

# 每周检查索引健康
psql $DATABASE_URL -f scripts/verify_indexes.sql
```

### 定期优化

```sql
-- 每月重建膨胀的索引（非高峰期）
REINDEX INDEX CONCURRENTLY idx_tags_gin;
REINDEX INDEX CONCURRENTLY idx_user_metadata_gin;

-- 清理过期数据（如果启用软删除）
DELETE FROM s3_objects 
WHERE is_deleted = true 
  AND updated_at < NOW() - INTERVAL '90 days';

VACUUM ANALYZE s3_objects;
```

## 📝 部署清单

### 新环境部署

- [ ] 1. 创建数据库和表：`psql -f scripts/s3_metadata_schema.sql`
- [ ] 2. 验证索引：`psql -f scripts/verify_indexes.sql`
- [ ] 3. 创建缺失的高优先级索引
- [ ] 4. 授予应用用户权限：`GRANT SELECT, INSERT, UPDATE, DELETE ON s3_objects TO rustfs_user;`
- [ ] 5. 测试查询性能：运行示例查询
- [ ] 6. 配置监控：设置 Prometheus 指标采集

### 生产环境升级

- [ ] 1. 备份数据库：`pg_dump rustfs_db > backup.sql`
- [ ] 2. 在非高峰期创建索引（使用 CONCURRENTLY）
- [ ] 3. 验证索引创建成功
- [ ] 4. 运行性能测试
- [ ] 5. 监控系统负载
- [ ] 6. 更新运维文档

## 🔍 监控指标

```sql
-- 索引命中率（应该 > 95%）
SELECT 
    schemaname,
    tablename,
    ROUND(
        (SUM(idx_scan) / NULLIF(SUM(idx_scan) + SUM(seq_scan), 0)) * 100, 2
    ) AS index_hit_rate_pct
FROM pg_stat_user_tables
WHERE tablename = 's3_objects'
GROUP BY schemaname, tablename;

-- 索引膨胀率
SELECT 
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS current_size,
    pg_size_pretty(pg_relation_size(indexrelid) * 0.2) AS bloat_estimate
FROM pg_stat_user_indexes
WHERE tablename = 's3_objects';
```

## 📚 相关文档

- [PostgreSQL 索引类型](https://www.postgresql.org/docs/current/indexes-types.html)
- [GIN 索引详解](https://www.postgresql.org/docs/current/gin.html)
- [索引维护最佳实践](https://www.postgresql.org/docs/current/routine-vacuuming.html)

## 🆘 故障排查

### 查询仍然很慢

1. 检查索引是否被使用：
```sql
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM s3_objects 
WHERE tags @> '{"Project": "analytics"}'::jsonb;
```

2. 查看查询计划，确认使用了 "Index Scan using idx_tags_gin"

3. 如果未使用索引，检查：
   - 统计信息是否最新（运行 ANALYZE）
   - 查询条件是否匹配索引
   - 数据分布是否合理

### 索引创建失败

```sql
-- 检查磁盘空间
SELECT pg_size_pretty(pg_database_size(current_database()));

-- 检查权限
\du rustfs_user

-- 使用较小的 maintenance_work_mem
SET maintenance_work_mem = '1GB';
CREATE INDEX CONCURRENTLY idx_tags_gin ON s3_objects USING GIN (tags);
```

---

**最后更新：** 2025-11-13  
**维护者：** RustFS Team
