# S3 对象删除时的数据库元数据同步

## 概述

当 S3 对象被删除时，RustFS 会自动同步删除数据库中存储的元数据信息，确保对象存储和元数据数据库的一致性。

## 删除同步机制

### 支持的删除操作

| API 操作 | 数据库同步 | 实现位置 |
|---------|----------|---------|
| **DeleteObject** | ✅ 已支持 | `rustfs/src/storage/ecfs.rs:1170` |
| **DeleteObjects**（批量删除） | ✅ 已支持 | `rustfs/src/storage/ecfs.rs:1423` |

### 工作流程

```
S3 删除请求
    ↓
权限验证
    ↓
删除对象存储中的对象
    ↓
sync_delete_object_metadata() ← 触发数据库同步
    ↓
发送 MetadataSyncEvent::Delete 到异步队列
    ↓
后台同步服务处理
    ↓
软删除数据库记录 (is_deleted=true)
```

### 代码示例

#### 单个对象删除

```rust
// 文件：rustfs/src/storage/ecfs.rs (delete_object)

// 删除对象存储中的对象
let obj_info = store.delete_object(&bucket, &key, opts).await?;

// 同步删除数据库元数据（非阻塞）
sync_delete_object_metadata(&bucket, &key);
```

#### 批量对象删除

```rust
// 文件：rustfs/src/storage/ecfs.rs (delete_objects)

for dobjs in delete_results.iter() {
    if let Some(dobj) = &dobjs.delete_object {
        // 同步删除数据库元数据（非阻塞）
        sync_delete_object_metadata(&bucket, &dobj.object_name);
        
        // ... 其他处理逻辑（复制等）
    }
}
```

## 数据库删除策略

### 软删除 vs 硬删除

RustFS 采用**软删除**策略：

```sql
UPDATE rustfs.s3_objects
SET is_deleted = true, updated_at = CURRENT_TIMESTAMP
WHERE bucket = $1 AND object_key = $2 AND is_deleted = false
```

**优势**：
- ✅ 保留审计记录
- ✅ 支持数据恢复
- ✅ 避免级联删除问题
- ✅ 更好的调试能力

### 硬删除（定期清理）

通过定期任务清理软删除的记录：

```sql
DELETE FROM rustfs.s3_objects 
WHERE is_deleted = true 
  AND updated_at < CURRENT_TIMESTAMP - INTERVAL '90 days'
```

可以通过 `S3ObjectRepository::purge_deleted()` 手动触发：

```rust
// 删除 90 天前软删除的记录
let deleted_count = S3ObjectRepository::purge_deleted(pool, 90).await?;
```

## 异步同步服务

### 配置参数

```yaml
database:
  sync:
    batch_size: 100        # 批量处理大小
    flush_interval_secs: 5 # 刷新间隔（秒）
    channel_size: 10000    # 事件队列大小
    max_retries: 3         # 最大重试次数
    retry_delay_ms: 1000   # 重试延迟（毫秒）
```

### 性能特征

- **非阻塞**：删除操作不等待数据库同步完成
- **批量处理**：多个删除操作批量写入数据库
- **自动重试**：失败时自动重试（默认 3 次）
- **背压管理**：队列满时丢弃事件并记录日志

### 监控指标

通过 `get_sync_stats()` 获取同步统计：

```rust
pub struct SyncServiceSnapshot {
    pub upsert_success: u64,  // 更新成功数
    pub upsert_failed: u64,   // 更新失败数
    pub delete_success: u64,  // 删除成功数
    pub delete_failed: u64,   // 删除失败数
    pub events_dropped: u64,  // 丢弃事件数
}
```

健康检查：

```rust
let stats = get_sync_stats().unwrap();
if stats.is_healthy() {
    // 成功率 > 95% 且丢弃事件 < 1000
    println!("Sync service is healthy");
}
```

## 删除场景处理

### 1. 普通对象删除

```bash
# AWS CLI
aws s3api delete-object --bucket my-bucket --key file.txt

# RustFS 处理流程
1. 验证权限
2. 删除对象存储中的文件
3. 异步软删除数据库记录
4. 返回响应
```

### 2. 批量删除

```bash
# AWS CLI
aws s3api delete-objects --bucket my-bucket --delete '{
  "Objects": [
    {"Key": "file1.txt"},
    {"Key": "file2.txt"},
    {"Key": "file3.txt"}
  ]
}'

# RustFS 处理流程
1. 验证每个对象的权限
2. 批量删除对象存储中的文件
3. 为每个成功删除的对象调用 sync_delete_object_metadata
4. 异步批量软删除数据库记录
5. 返回删除结果
```

### 3. 版本化对象删除

```bash
# 删除特定版本
aws s3api delete-object \
  --bucket my-bucket \
  --key file.txt \
  --version-id "version-id-here"

# RustFS 处理
- 删除特定版本的对象
- 软删除对应版本的元数据记录
- 不影响其他版本
```

### 4. 删除标记（Delete Marker）

```bash
# 在版本化 bucket 中删除对象（不指定版本）
aws s3api delete-object --bucket versioned-bucket --key file.txt

# RustFS 处理
- 创建删除标记（而非真正删除）
- 在数据库中标记为 delete_marker=true
- 对象仍可通过版本 ID 访问
```

## 故障处理

### 删除同步失败

如果数据库同步失败，系统会：

1. **记录错误日志**：
   ```
   WARN Failed to send metadata sync event for delete object
        - stale metadata may remain in query results
   ```

2. **自动重试**（最多 3 次）

3. **最终失败处理**：
   - 对象存储中的文件已删除
   - 数据库中的元数据可能残留
   - 查询 API 可能返回"已删除"的对象

### 手动清理残留元数据

如果检测到元数据不一致：

```rust
use rustfs::storage::database::{get_database_pool, S3ObjectRepository};

// 手动删除特定对象的元数据
let pool = get_database_pool().unwrap();
S3ObjectRepository::delete(pool, "my-bucket", "file.txt").await?;

// 或直接执行 SQL
sqlx::query("UPDATE rustfs.s3_objects SET is_deleted=true WHERE bucket=$1 AND object_key=$2")
    .bind("my-bucket")
    .bind("file.txt")
    .execute(pool)
    .await?;
```

### 队列满时的行为

当同步队列满时（默认 10000 个事件）：

```
WARN Failed to send metadata sync event for delete object
     - error_type: channel_full
     - stale metadata may remain in query results
```

**解决方法**：
1. 增加 `channel_size` 配置
2. 减少 `flush_interval_secs`（更频繁刷新）
3. 增加 `batch_size`（每次处理更多）
4. 检查数据库性能瓶颈

## 查询已删除对象

### 排除已删除对象

默认查询会过滤软删除的对象：

```rust
use rustfs::storage::database::{S3ObjectQuery, S3ObjectRepository};

let query = S3ObjectQuery {
    bucket: Some("my-bucket".to_string()),
    ..Default::default()
};

// 只返回 is_deleted=false 的对象
let result = S3ObjectRepository::query(pool, &query).await?;
```

### 查询包括已删除对象

如果需要查询所有对象（包括已删除）：

```sql
-- 查询所有对象（包括软删除）
SELECT * FROM rustfs.s3_objects WHERE bucket = 'my-bucket';

-- 只查询已删除对象
SELECT * FROM rustfs.s3_objects WHERE bucket = 'my-bucket' AND is_deleted = true;

-- 查询最近删除的对象
SELECT * FROM rustfs.s3_objects 
WHERE is_deleted = true 
  AND updated_at > NOW() - INTERVAL '7 days'
ORDER BY updated_at DESC;
```

## 最佳实践

### 1. 监控删除同步健康度

```rust
use rustfs::storage::database::get_sync_stats;

// 定期检查（如每分钟）
tokio::spawn(async move {
    let mut interval = tokio::time::interval(Duration::from_secs(60));
    loop {
        interval.tick().await;
        
        if let Some(stats) = get_sync_stats() {
            if !stats.is_healthy() {
                eprintln!("WARNING: Metadata sync service unhealthy!");
                eprintln!("  Success rate: {:.2}%", stats.success_rate() * 100.0);
                eprintln!("  Events dropped: {}", stats.events_dropped);
            }
        }
    }
});
```

### 2. 定期清理软删除记录

建议配置 cron 任务：

```bash
#!/bin/bash
# cleanup-deleted-metadata.sh

# 清理 90 天前软删除的记录
psql -U rustfs_user -d rustfs_db <<SQL
DELETE FROM rustfs.s3_objects 
WHERE is_deleted = true 
  AND updated_at < CURRENT_TIMESTAMP - INTERVAL '90 days';
SQL
```

或通过 Rust 代码：

```rust
// 每天运行一次
tokio::spawn(async move {
    let mut interval = tokio::time::interval(Duration::from_secs(86400));
    loop {
        interval.tick().await;
        
        if let Some(pool) = get_database_pool() {
            match S3ObjectRepository::purge_deleted(pool, 90).await {
                Ok(count) => info!("Purged {} deleted objects", count),
                Err(e) => error!("Failed to purge deleted objects: {}", e),
            }
        }
    }
});
```

### 3. 调整同步配置

根据负载调整配置：

**低负载场景**（< 100 删除/秒）：
```yaml
database:
  sync:
    batch_size: 50
    flush_interval_secs: 10
    channel_size: 1000
```

**中等负载**（100-1000 删除/秒）：
```yaml
database:
  sync:
    batch_size: 200
    flush_interval_secs: 3
    channel_size: 10000
```

**高负载**（> 1000 删除/秒）：
```yaml
database:
  sync:
    batch_size: 500
    flush_interval_secs: 1
    channel_size: 50000
    max_retries: 5
```

## 限制和注意事项

### 1. 最终一致性

数据库元数据同步是**异步**的，存在短暂的不一致窗口：

- 对象已从对象存储删除
- 但数据库查询可能短暂返回该对象（< 5 秒）

### 2. 队列容量限制

- 默认队列大小：10000 个事件
- 队列满时会**丢弃**新事件
- 需要根据删除频率调整 `channel_size`

### 3. 软删除占用空间

- 软删除记录仍占用数据库空间
- 需要定期清理（建议 90 天）
- 可通过索引优化查询性能：
  ```sql
  CREATE INDEX idx_deleted_objects 
  ON rustfs.s3_objects(is_deleted, updated_at) 
  WHERE is_deleted = true;
  ```

### 4. 版本化对象的特殊处理

- 版本化 bucket 中删除对象会创建删除标记
- 删除标记本身也是一个"对象"，也会同步到数据库
- 查询时需要区分删除标记和真实对象

## 相关文档

- [数据库自动建表功能](./AUTO_SCHEMA_CREATION.md)
- [S3 元数据数据库设计](./S3_METADATA_DATABASE_DESIGN.md)
- [元数据 API 使用指南](./S3_METADATA_API_GUIDE.md)
- [元数据同步服务](../rustfs/src/storage/database/sync_service.rs)
- [删除钩子实现](../rustfs/src/storage/metadata_sync_hooks.rs)

## 总结

✅ **已实现功能**：
- 单个对象删除时自动同步数据库
- 批量删除时自动同步数据库
- 软删除策略保留审计记录
- 异步批量处理提升性能
- 自动重试机制保证可靠性
- 完善的监控和统计

🔧 **运维建议**：
- 定期监控同步服务健康度
- 定期清理软删除记录（建议 90 天）
- 根据负载调整同步配置
- 关注 `events_dropped` 指标

⚠️ **注意事项**：
- 删除是异步的，存在短暂不一致
- 队列满时会丢弃事件
- 软删除需要定期清理
