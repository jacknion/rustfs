# 数据库错误处理改进

## 概述

本次改进为 S3 元数据同步服务添加了全面的错误处理机制，确保用户在数据库操作失败时能收到明确的错误提示。

## 改进内容

### 1. HTTP 查询 API 错误处理

#### 元数据查询 API (`GET /rustfs/admin/v3/s3/metadata/query`)

**改进前：**
```rust
.map_err(|e| s3_error!(InternalError, "Database query failed: {}", e))
```

**改进后：**
```rust
.map_err(|e| {
    // 根据错误类型提供友好提示
    let error_msg = if e.to_string().contains("connection") {
        "Database connection failed. Please try again later."
    } else if e.to_string().contains("timeout") {
        "Database query timeout. Please refine your search criteria."
    } else if e.to_string().contains("syntax") {
        "Invalid query parameters. Please check your request."
    } else {
        "Database query failed. Please contact administrator if this persists."
    };
    
    s3_error!(InternalError, "{} Error: {}", error_msg, e)
})
```

#### 按标签查询 API (`POST /rustfs/admin/v3/s3/metadata/query-by-tags`)

提供针对标签查询的专门错误信息：
- 连接失败：`"Database connection failed. Please try again later."`
- 查询超时：`"Database query timeout. Please refine your search criteria."`
- 标签格式错误：`"Invalid tag query. Please check your tag format."`
- 其他错误：`"Database query failed. Please contact administrator if this persists."`

### 2. 元数据同步钩子错误处理

#### PUT 操作同步钩子

**改进前：**
```rust
warn!("Failed to send metadata sync event for put object");
```

**改进后：**
```rust
warn!(
    bucket = %obj_info.bucket,
    object_key = %obj_info.name,
    size = obj_info.size,
    error_type = if e.contains("Channel full") { "channel_full" } else { "channel_closed" },
    "Failed to send metadata sync event for put object - metadata will not be searchable via query API"
);
```

**用户影响说明：**
- 对象成功上传到存储层
- 元数据未同步到数据库（不影响对象本身）
- 该对象暂时无法通过查询 API 检索
- 日志中包含详细的错误类型和对象信息

#### DELETE 操作同步钩子

**改进后：**
```rust
warn!(
    bucket = %bucket,
    object_key = %object_key,
    error_type = if e.contains("Channel full") { "channel_full" } else { "channel_closed" },
    "Failed to send metadata sync event for delete object - stale metadata may remain in query results"
);
```

**用户影响说明：**
- 对象成功从存储层删除
- 数据库中的元数据未及时清理
- 查询 API 可能返回已删除对象的过期记录
- 日志中记录详细信息以便追踪

### 3. 同步服务统计和监控

#### 新增全局统计结构

```rust
pub struct SyncServiceStats {
    /// 成功的 upsert 操作数
    pub upsert_success: AtomicU64,
    
    /// 失败的 upsert 操作数
    pub upsert_failed: AtomicU64,
    
    /// 成功的 delete 操作数
    pub delete_success: AtomicU64,
    
    /// 失败的 delete 操作数
    pub delete_failed: AtomicU64,
    
    /// 因通道满而丢弃的事件数
    pub events_dropped: AtomicU64,
}
```

#### 统计快照 API

```rust
pub struct SyncServiceSnapshot {
    pub upsert_success: u64,
    pub upsert_failed: u64,
    pub delete_success: u64,
    pub delete_failed: u64,
    pub events_dropped: u64,
}

impl SyncServiceSnapshot {
    /// 计算总处理数
    pub fn total_processed(&self) -> u64;
    
    /// 计算总失败数
    pub fn total_failed(&self) -> u64;
    
    /// 计算成功率 (0.0 到 1.0)
    pub fn success_rate(&self) -> f64;
    
    /// 检查服务是否健康 (成功率 > 95% 且丢弃事件 < 1000)
    pub fn is_healthy(&self) -> bool;
}
```

### 4. 健康检查 API

#### 端点：`GET /rustfs/admin/v3/sync/health`

**响应格式：**

```json
{
  "status": "healthy|degraded|unhealthy|unavailable",
  "syncStats": {
    "upsertSuccess": 1000,
    "upsertFailed": 5,
    "deleteSuccess": 200,
    "deleteFailed": 1,
    "eventsDropped": 0,
    "totalProcessed": 1200,
    "totalFailed": 6,
    "successRate": 0.995
  },
  "message": "Metadata sync service is operating normally"
}
```

**状态判断：**

| 状态 | 条件 | HTTP 状态码 |
|------|------|------------|
| `healthy` | 成功率 > 95% 且丢弃 < 1000 | 200 OK |
| `degraded` | 成功率 80-95% 或 丢弃 >= 1000 | 200 OK |
| `unhealthy` | 成功率 < 80% | 503 Service Unavailable |
| `unavailable` | 服务未初始化 | 503 Service Unavailable |

## 错误场景示例

### 场景 1：数据库连接失败

**用户操作：**
```bash
curl "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?bucket=test"
```

**响应：**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>InternalError</Code>
  <Message>Database connection failed. Please try again later. Error: connection refused</Message>
  <RequestId>...</RequestId>
</Error>
```

### 场景 2：查询超时

**用户操作：**
```bash
curl "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?bucket=*&limit=10000"
```

**响应：**
```xml
<Error>
  <Code>InternalError</Code>
  <Message>Database query timeout. Please refine your search criteria. Error: query timeout after 30s</Message>
  <RequestId>...</RequestId>
</Error>
```

### 场景 3：同步通道满（高负载）

**S3 PUT 操作：**
```bash
s3cmd put large-file.dat s3://bucket/key
```

**对象上传成功，但元数据同步失败：**

**日志输出：**
```
WARN rustfs::storage::metadata_sync_hooks bucket="bucket" object_key="key" size=1048576 error_type="channel_full" \
  Failed to send metadata sync event for put object - metadata will not be searchable via query API
```

**用户影响：**
- PUT 操作成功返回 200 OK
- 对象已存储，可正常下载
- 暂时无法通过查询 API 检索该对象
- 管理员可通过健康检查 API 发现问题

### 场景 4：健康检查（降级状态）

**请求：**
```bash
curl "http://localhost:9000/rustfs/admin/v3/sync/health"
```

**响应（降级）：**
```json
{
  "status": "degraded",
  "syncStats": {
    "upsertSuccess": 900,
    "upsertFailed": 100,
    "deleteSuccess": 200,
    "deleteFailed": 10,
    "eventsDropped": 1500,
    "totalProcessed": 1100,
    "totalFailed": 110,
    "successRate": 0.909
  },
  "message": "Metadata sync service is degraded (success rate: 90.9%, dropped: 1500)"
}
```

## 监控建议

### 1. 日志监控

监控以下关键日志：

```bash
# 元数据同步失败
grep "Failed to send metadata sync event" /var/log/rustfs/*.log

# 数据库操作重试失败
grep "Failed to upsert S3 object metadata after retries" /var/log/rustfs/*.log
grep "Failed to delete S3 object metadata after retries" /var/log/rustfs/*.log

# 通道满警告
grep "Metadata sync queue is full" /var/log/rustfs/*.log
```

### 2. 指标监控（Prometheus 示例）

```yaml
# 健康检查探针
- job_name: 'rustfs-sync-health'
  scrape_interval: 30s
  metrics_path: '/rustfs/admin/v3/sync/health'
  static_configs:
    - targets: ['localhost:9000']
```

### 3. 告警规则

```yaml
# 同步服务健康告警
- alert: RustFSMetadataSyncDegraded
  expr: rustfs_sync_success_rate < 0.95
  for: 5m
  annotations:
    summary: "RustFS 元数据同步服务降级"
    description: "成功率降至 {{ $value }}，低于 95% 阈值"

- alert: RustFSMetadataSyncEventsDropped
  expr: rustfs_sync_events_dropped > 1000
  for: 5m
  annotations:
    summary: "RustFS 元数据同步丢失事件过多"
    description: "已丢失 {{ $value }} 个同步事件"
```

## 故障排查

### 问题 1：元数据查询返回 "Database connection failed"

**原因：**
- PostgreSQL 未启动
- 网络不通
- 连接池耗尽

**排查：**
```bash
# 检查数据库连接
psql -h localhost -U rustfs -d rustfs_metadata -c "SELECT 1;"

# 检查连接池状态（添加到日志）
grep "Database pool" /var/log/rustfs/*.log
```

**解决：**
- 启动 PostgreSQL
- 检查防火墙规则
- 增加 `max_connections` 配置

### 问题 2：查询返回 "Database query timeout"

**原因：**
- 查询条件过于宽泛
- 缺少索引
- 数据库负载高

**排查：**
```bash
# 检查慢查询
psql -U rustfs -d rustfs_metadata -c "
SELECT query, calls, mean_exec_time 
FROM pg_stat_statements 
ORDER BY mean_exec_time DESC 
LIMIT 10;
"

# 验证索引
./scripts/check_db_indexes.sh
```

**解决：**
- 使用更精确的查询条件
- 创建缺失的索引（参考 `DATABASE_INDEX_GUIDE.md`）
- 优化数据库配置

### 问题 3：同步通道频繁满载

**原因：**
- 写入速率超过处理能力
- `batch_size` 过大导致处理慢
- 数据库性能瓶颈

**排查：**
```bash
# 查看健康检查
curl http://localhost:9000/rustfs/admin/v3/sync/health | jq

# 检查丢弃事件数
grep "events_dropped" /var/log/rustfs/*.log
```

**解决：**
```rust
// 调整同步服务配置
MetadataSyncConfig {
    batch_size: 50,              // 减小批次（默认 100）
    flush_interval_secs: 1,       // 保持不变
    max_queue_size: 20000,        // 增加队列（默认 10000）
    max_retries: 3,               // 保持不变
    retry_delay_ms: 100,          // 保持不变
}
```

## 相关文档

- [数据库索引指南](./DATABASE_INDEX_GUIDE.md)
- [N+1 查询优化](./N1_QUERY_OPTIMIZATION.md)
- [环境变量配置](./ENVIRONMENT_VARIABLES.md)

## 测试验证

### 单元测试

```bash
# 测试健康检查响应序列化
cargo test --package rustfs test_health_check_response_serialization

# 测试统计快照功能
cargo test --package rustfs test_sync_service_snapshot
```

### 集成测试

```bash
# 模拟数据库连接失败
# 停止 PostgreSQL 后测试查询 API
systemctl stop postgresql
curl http://localhost:9000/rustfs/admin/v3/s3/metadata/query?bucket=test

# 预期：返回 "Database connection failed" 错误
```

### 压力测试

```bash
# 模拟高并发写入
parallel -j 100 'aws s3 cp /dev/zero s3://test/obj-{} --endpoint-url http://localhost:9000' ::: {1..10000}

# 检查健康状态
watch -n 1 'curl -s http://localhost:9000/rustfs/admin/v3/sync/health | jq .syncStats'
```

## 总结

本次改进实现了：

1. ✅ **友好的错误提示** - 用户能清楚了解错误原因和解决方向
2. ✅ **详细的日志记录** - 运维人员可快速定位问题
3. ✅ **实时监控指标** - 通过健康检查 API 掌握服务状态
4. ✅ **非阻塞设计** - 元数据同步失败不影响 S3 核心功能
5. ✅ **优雅降级** - 在高负载下丢弃元数据同步，保证存储可用性

错误处理遵循"快速失败、明确提示、详细日志"原则，在保证系统可靠性的同时提供良好的用户体验。
