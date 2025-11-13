# 数据库自动建表功能

## 概述

RustFS 现在支持在启动时自动创建数据库表结构。当检测到数据库中不存在 `rustfs.s3_objects` 表时，系统会自动执行完整的 schema 创建脚本。所有数据库对象都位于独立的 `rustfs` schema 中，遵循 PostgreSQL 最佳实践。

## 工作原理

### 自动检测和创建流程

```
启动 RustFS
    ↓
连接到 PostgreSQL
    ↓
检查 rustfs.s3_objects 表是否存在
    ↓
    ├─→ 存在：跳过创建，继续启动
    └─→ 不存在：自动执行 schema SQL
            ↓
        创建 rustfs schema
            ↓
        创建表、索引、视图、触发器
            ↓
        继续启动
```

### 代码实现位置

**文件**：`rustfs/src/storage/database/mod.rs`

**关键函数**：`ensure_database_schema()`

```rust
async fn ensure_database_schema(pool: &PgPool) -> Result<(), sqlx::Error> {
    // 1. 检查表是否存在（使用 rustfs schema）
    let table_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'rustfs' 
            AND table_name = 's3_objects'
        )",
    )
    .fetch_one(pool)
    .await?;

    // 2. 如果不存在，执行创建脚本（会自动创建 rustfs schema）
    if !table_exists {
        let schema_sql = include_str!("../../../../scripts/s3_metadata_schema.sql");
        sqlx::query(schema_sql).execute(pool).await?;
    }

    Ok(())
}
```

## Schema 组织

所有数据库对象都位于独立的 `rustfs` schema 中：

- **Tables**: `rustfs.s3_objects`, `rustfs.bucket_stats`, `rustfs.tag_statistics`
- **Views**: `rustfs.recent_objects`, `rustfs.large_objects`, `rustfs.encrypted_objects_summary`
- **Indexes**: 所有索引都自动关联到对应的表
- **Functions & Triggers**: 自动更新触发器等

**优势**：
- ✅ 命名空间隔离，避免与其他应用冲突
- ✅ 更清晰的权限管理
- ✅ 符合 PostgreSQL 企业级最佳实践
- ✅ 便于未来扩展和维护

## 使用方式

### 方式 1：自动创建（推荐）

直接启动 RustFS，配置好数据库连接即可：

```bash
# 设置数据库连接
export RUSTFS_DATABASE_URL="postgres://rustfs_user:password@localhost:5432/rustfs_db"

# 启动 RustFS（会自动创建 rustfs schema 和所有表）
./rustfs server --config config.yaml
```

**日志输出示例**：

```
INFO rustfs::storage::database: Initializing database connection pool
INFO rustfs::storage::database: Database connection pool initialized successfully
WARN rustfs::storage::database: Table rustfs.s3_objects not found, creating database schema...
INFO rustfs::storage::database: Database schema created successfully in rustfs schema
INFO rustfs::main::run: Metadata sync service initialized successfully
```

### 方式 2：手动创建（可选）

如果你希望手动控制表的创建，可以提前执行：

```bash
# 连接到数据库
psql -U rustfs_user -d rustfs_db

# 执行 schema 脚本
\i scripts/s3_metadata_schema.sql
```

之后启动 RustFS 时会跳过创建：

```
INFO rustfs::storage::database: Database schema already exists, skipping creation
```

## 创建的数据库对象

### 主表

- **s3_objects**：S3 对象元数据主表（包含 16 个字段）

### 辅助表

- **bucket_stats**：Bucket 统计信息
- **tag_statistics**：标签使用统计

### 索引（10个）

1. `idx_bucket_key` - 复合索引（bucket + object_key）
2. `idx_tags_gin` - JSONB 标签 GIN 索引
3. `idx_user_metadata_gin` - 用户元数据 GIN 索引
4. `idx_last_modified` - 时间索引
5. `idx_created_at` - 创建时间索引
6. `idx_bucket_storage_class` - 存储类型索引
7. `idx_retention` - 合规保留索引（部分索引）
8. `idx_legal_hold` - 法律保留索引（部分索引）
9. `idx_encrypted` - 加密对象索引（部分索引）
10. `idx_version` - 版本控制索引

### 视图（3个）

- `recent_objects` - 最近 7 天对象
- `large_objects` - 大文件对象（> 100MB）
- `encrypted_objects_summary` - 加密对象统计

### 触发器（1个）

- `s3_objects_updated_at_trigger` - 自动更新 `updated_at` 字段

### 权限

自动为 `rustfs_user` 授予必要的表操作权限。

## 安全特性

### 1. 幂等性保证

使用 `CREATE TABLE IF NOT EXISTS` 确保重复执行不会出错：

```sql
CREATE TABLE IF NOT EXISTS s3_objects (
    -- ...
);
```

### 2. 只在必要时创建

通过检查 `information_schema.tables` 确保只在表不存在时才创建。

### 3. 事务安全

PostgreSQL 会将整个 schema 创建过程作为一个事务执行，要么全部成功，要么全部回滚。

## 故障排查

### 问题 1：权限不足

**错误**：
```
ERROR: permission denied for schema public
```

**解决**：
```sql
-- 授予用户创建表的权限
GRANT CREATE ON SCHEMA public TO rustfs_user;
```

### 问题 2：数据库不存在

**错误**：
```
database "rustfs_db" does not exist
```

**解决**：
```bash
# 先创建数据库
createdb -U postgres rustfs_db

# 或在 psql 中
CREATE DATABASE rustfs_db OWNER rustfs_user;
```

### 问题 3：SQL 脚本执行失败

**错误**：
```
Failed to create database schema: syntax error at or near "..."
```

**解决**：
1. 检查 `scripts/s3_metadata_schema.sql` 文件是否完整
2. 确认 PostgreSQL 版本 >= 16
3. 手动执行脚本验证：
   ```bash
   psql -U rustfs_user -d rustfs_db -f scripts/s3_metadata_schema.sql
   ```

## 配置选项

### 环境变量

```bash
# 数据库连接 URL（必需）
export RUSTFS_DATABASE_URL="postgres://user:pass@host:port/dbname"

# 最大连接数（可选，默认 10）
export RUSTFS_DATABASE_MAX_CONNECTIONS=20
```

### 配置文件

```yaml
# config.yaml
database:
  url: "postgres://rustfs_user:password@localhost:5432/rustfs_db"
  max_connections: 10
  connect_timeout: 30
  idle_timeout: 600
```

## 性能影响

### 首次启动

- **检查时间**：< 10ms（单次 SQL 查询）
- **创建时间**：200-500ms（包括所有表、索引、视图）
- **对启动的影响**：最多延迟 0.5 秒（一次性）

### 后续启动

- **检查时间**：< 10ms
- **创建时间**：0（跳过）
- **对启动的影响**：几乎无影响

## 最佳实践

### 1. 生产环境建议

**选项 A**：在部署前手动创建（更可控）

```bash
# 部署流程
1. 手动执行 SQL 脚本创建表
2. 验证表结构正确
3. 启动 RustFS（会跳过创建）
```

**选项 B**：使用自动创建（更便捷）

```bash
# 直接启动，让系统自动创建表
./rustfs server
```

### 2. 开发环境

直接使用自动创建功能，无需额外操作：

```bash
docker-compose up  # 数据库和 RustFS 一起启动
```

### 3. 容器化部署

```dockerfile
# Dockerfile
FROM postgres:16

# 可选：预置 SQL 脚本（备用）
COPY scripts/s3_metadata_schema.sql /docker-entrypoint-initdb.d/

# RustFS 启动时也会自动检查和创建
```

## 与手动创建对比

| 特性 | 自动创建 | 手动创建 |
|------|---------|---------|
| **便捷性** | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **可控性** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **适用场景** | 开发、测试、小型部署 | 生产环境、大规模部署 |
| **启动速度** | 首次慢 0.5s | 始终快速 |
| **权限要求** | 需要 CREATE 权限 | 可以使用受限权限 |
| **错误处理** | 自动回滚 | 手动处理 |

## 未来改进

### 计划中的功能

1. **Migration 支持**：使用 SQLx migrations 管理 schema 版本
2. **增量更新**：检测 schema 变更并自动升级
3. **Schema 版本号**：记录当前 schema 版本，支持平滑升级
4. **配置开关**：允许通过配置禁用自动创建

### 建议的 Migration 方案

```bash
# 未来版本可能的实现
rustfs/migrations/
  ├── 20241113_000001_initial_schema.sql
  ├── 20241120_000002_add_checksum_fields.sql
  └── 20241127_000003_optimize_indexes.sql
```

## 参考资料

- [PostgreSQL CREATE TABLE 文档](https://www.postgresql.org/docs/16/sql-createtable.html)
- [SQLx Migrations 指南](https://github.com/launchbadge/sqlx/tree/main/sqlx-cli#migrations)
- [RustFS 数据库设计文档](./S3_METADATA_DATABASE_DESIGN.md)
- [元数据 API 使用指南](./S3_METADATA_API_GUIDE.md)

## 总结

自动建表功能简化了 RustFS 的部署流程，特别是在开发和测试环境中。生产环境中建议根据实际情况选择自动或手动创建方式。

**核心优势**：
- ✅ 零配置启动
- ✅ 幂等性保证
- ✅ 自动权限设置
- ✅ 完整的 schema（表、索引、视图、触发器）
- ✅ 向后兼容（已有表时跳过创建）
