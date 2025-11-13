# S3 元数据更新 API

## 概述

提供 RESTful API 用于更新已存储对象的元数据，无需重新上传对象本身。支持部分更新（只更新指定的字段）。

## API 端点

### 更新元数据

**端点:** `PUT /rustfs/admin/v3/s3/metadata/update`

**请求方法:** PUT

**Content-Type:** `application/json`

## 请求格式

```json
{
  "bucket": "string",           // 必填：桶名称
  "objectKey": "string",        // 必填：对象键（路径）
  "updates": {                  // 必填：要更新的字段（至少提供一个）
    "storageClass": "string",   // 可选：存储类别
    "encryption": "string",     // 可选：加密算法
    "contentType": "string",    // 可选：内容类型
    "tags": {                   // 可选：对象标签（完全替换）
      "key1": "value1",
      "key2": "value2"
    },
    "userMetadata": {           // 可选：用户元数据（完全替换）
      "customKey": "customValue"
    },
    "ownerId": "string"         // 可选：所有者ID
  }
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bucket` | string | ✅ | 对象所在的桶名称 |
| `objectKey` | string | ✅ | 对象的完整键（路径） |
| `updates` | object | ✅ | 要更新的字段对象 |
| `updates.storageClass` | string | ❌ | 存储类别（如 STANDARD, GLACIER, DEEP_ARCHIVE） |
| `updates.encryption` | string | ❌ | 加密算法（如 AES256, aws:kms） |
| `updates.contentType` | string | ❌ | MIME 类型（如 application/json, text/plain） |
| `updates.tags` | object | ❌ | 对象标签键值对，会完全替换现有标签 |
| `updates.userMetadata` | object | ❌ | 用户自定义元数据，会完全替换现有元数据 |
| `updates.ownerId` | string | ❌ | 对象所有者标识符 |

**注意：**
- `updates` 对象中至少需要提供一个字段
- 标签和用户元数据是**完全替换**，而不是合并
- 不可修改的字段：bucket、objectKey、size、etag、lastModified

## 响应格式

### 成功响应 (200 OK)

```json
{
  "success": true,
  "message": "Metadata updated successfully",
  "rowsAffected": 1
}
```

### 对象不存在 (404 Not Found)

```json
{
  "success": false,
  "message": "Object not found or already deleted: bucket=my-bucket, key=path/to/file.txt",
  "rowsAffected": 0
}
```

### 错误响应 (4xx/5xx)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>InvalidRequest</Code>
  <Message>No update fields provided. Specify at least one field to update.</Message>
  <RequestId>...</RequestId>
</Error>
```

## 使用示例

### 示例 1: 更新存储类别

将对象归档到 GLACIER 存储类别：

```bash
curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "my-bucket",
    "objectKey": "logs/2024/november/access.log",
    "updates": {
      "storageClass": "GLACIER"
    }
  }'
```

**响应：**
```json
{
  "success": true,
  "message": "Metadata updated successfully",
  "rowsAffected": 1
}
```

### 示例 2: 更新标签

为对象添加项目和环境标签：

```bash
curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "analytics-data",
    "objectKey": "reports/2024/q4/sales.csv",
    "updates": {
      "tags": {
        "Project": "Q4-Analytics",
        "Environment": "production",
        "Department": "Sales"
      }
    }
  }'
```

### 示例 3: 更新多个字段

同时更新存储类别、标签和用户元数据：

```bash
curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "documents",
    "objectKey": "contracts/2024/contract-12345.pdf",
    "updates": {
      "storageClass": "STANDARD_IA",
      "tags": {
        "Status": "archived",
        "Year": "2024",
        "Type": "contract"
      },
      "userMetadata": {
        "x-amz-meta-archived-by": "john.doe@company.com",
        "x-amz-meta-archive-date": "2024-11-13"
      }
    }
  }'
```

### 示例 4: 更新内容类型

修正对象的 MIME 类型：

```bash
curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "images",
    "objectKey": "photos/vacation/beach.jpg",
    "updates": {
      "contentType": "image/jpeg"
    }
  }'
```

### 示例 5: Python 客户端

```python
import requests
import json

def update_s3_metadata(bucket, object_key, updates):
    """更新 S3 对象元数据"""
    url = "http://localhost:9000/rustfs/admin/v3/s3/metadata/update"
    
    payload = {
        "bucket": bucket,
        "objectKey": object_key,
        "updates": updates
    }
    
    response = requests.put(url, json=payload)
    response.raise_for_status()
    
    return response.json()

# 使用示例
result = update_s3_metadata(
    bucket="my-bucket",
    object_key="data/report.csv",
    updates={
        "storageClass": "DEEP_ARCHIVE",
        "tags": {
            "Retention": "7years",
            "Compliance": "SOX"
        }
    }
)

print(f"Success: {result['success']}")
print(f"Message: {result['message']}")
print(f"Rows affected: {result['rowsAffected']}")
```

### 示例 6: 批量更新脚本

```bash
#!/bin/bash
# 批量更新特定前缀下的所有对象标签

BUCKET="logs"
PREFIX="2023/"
ENDPOINT="http://localhost:9000/rustfs/admin/v3"

# 先查询需要更新的对象
objects=$(curl -s "${ENDPOINT}/s3/metadata/query?bucket=${BUCKET}&prefix=${PREFIX}&limit=1000" | \
  jq -r '.objects[].objectKey')

# 批量更新标签
for object_key in $objects; do
  echo "Updating: $object_key"
  
  curl -X PUT "${ENDPOINT}/s3/metadata/update" \
    -H "Content-Type: application/json" \
    -d "{
      \"bucket\": \"${BUCKET}\",
      \"objectKey\": \"${object_key}\",
      \"updates\": {
        \"tags\": {
          \"Year\": \"2023\",
          \"Status\": \"archived\"
        },
        \"storageClass\": \"GLACIER\"
      }
    }"
  
  echo ""
done
```

## 错误处理

### 常见错误

#### 1. 未提供更新字段

**请求：**
```json
{
  "bucket": "my-bucket",
  "objectKey": "file.txt",
  "updates": {}
}
```

**响应：** 400 Bad Request
```xml
<Error>
  <Code>InvalidRequest</Code>
  <Message>No update fields provided. Specify at least one field to update.</Message>
</Error>
```

#### 2. 对象不存在

**响应：** 404 Not Found
```json
{
  "success": false,
  "message": "Object not found or already deleted: bucket=my-bucket, key=missing.txt",
  "rowsAffected": 0
}
```

#### 3. 数据库连接失败

**响应：** 500 Internal Error
```xml
<Error>
  <Code>InternalError</Code>
  <Message>Database connection failed. Please try again later. Error: connection refused</Message>
</Error>
```

#### 4. 无效的 JSON

**请求：**
```
{ invalid json
```

**响应：** 400 Bad Request
```xml
<Error>
  <Code>InvalidRequest</Code>
  <Message>Invalid JSON request body: expected value at line 1 column 3</Message>
</Error>
```

## 最佳实践

### 1. 标签管理

标签更新是**完全替换**操作，如果需要保留现有标签：

```python
# ❌ 错误：会删除所有现有标签
update_s3_metadata(bucket, key, {
    "tags": {"NewTag": "value"}
})

# ✅ 正确：先查询现有标签，再合并
current_obj = query_metadata(bucket, key)
current_tags = current_obj.get("tags", {})
current_tags["NewTag"] = "value"  # 添加新标签

update_s3_metadata(bucket, key, {
    "tags": current_tags  # 包含旧标签和新标签
})
```

### 2. 批量操作建议

```python
import asyncio
import aiohttp

async def update_metadata_batch(updates):
    """异步批量更新元数据"""
    async with aiohttp.ClientSession() as session:
        tasks = []
        for update in updates:
            task = session.put(
                "http://localhost:9000/rustfs/admin/v3/s3/metadata/update",
                json=update
            )
            tasks.append(task)
        
        # 限制并发数
        semaphore = asyncio.Semaphore(10)
        async def bounded_task(task):
            async with semaphore:
                return await task
        
        results = await asyncio.gather(*[bounded_task(t) for t in tasks])
        return results

# 使用
updates = [
    {"bucket": "data", "objectKey": f"file{i}.txt", "updates": {"storageClass": "GLACIER"}}
    for i in range(100)
]

asyncio.run(update_metadata_batch(updates))
```

### 3. 存储类别转换策略

```python
# 根据对象年龄自动归档
from datetime import datetime, timedelta

def archive_old_objects(bucket, days_old=90):
    """归档超过指定天数的对象"""
    cutoff_date = datetime.utcnow() - timedelta(days=days_old)
    
    # 查询旧对象
    query_url = f"http://localhost:9000/rustfs/admin/v3/s3/metadata/query"
    params = {
        "bucket": bucket,
        "modifiedBefore": cutoff_date.isoformat() + "Z",
        "limit": 1000
    }
    
    response = requests.get(query_url, params=params)
    old_objects = response.json()["objects"]
    
    # 批量更新为 GLACIER
    for obj in old_objects:
        if obj.get("storageClass") == "STANDARD":
            update_s3_metadata(
                bucket=obj["bucket"],
                object_key=obj["objectKey"],
                updates={"storageClass": "GLACIER"}
            )
            print(f"Archived: {obj['objectKey']}")
```

## 限制和注意事项

### 不可变字段

以下字段**不能**通过此 API 修改：
- `bucket` - 桶名称
- `objectKey` - 对象键
- `versionId` - 版本ID
- `sizeBytes` - 对象大小
- `etag` - ETag 值
- `lastModified` - 最后修改时间（自动更新为当前时间）

如需修改这些字段，必须重新上传对象。

### 标签和元数据替换

⚠️ **重要：** `tags` 和 `userMetadata` 是**完全替换**操作：

```bash
# 当前标签: {"Env": "prod", "Team": "backend"}

# 更新后只有新标签
curl -X PUT .../update -d '{
  "bucket": "test",
  "objectKey": "file.txt",
  "updates": {
    "tags": {"Status": "archived"}  # 旧标签 Env 和 Team 会丢失！
  }
}'

# 更新后标签: {"Status": "archived"}
```

### 性能考虑

- 单次更新操作通常在 10-50ms 内完成
- 批量更新建议使用异步/并发方式，限制并发数 ≤ 100
- 大规模更新（> 10000 对象）建议分批执行，避免数据库负载过高

### 权限要求

调用此 API 需要：
- 对目标桶有写权限
- 管理员 API 访问权限（根据系统配置）

## 与其他 API 的配合使用

### 1. 查询 + 更新

```bash
# 步骤1: 查询特定标签的对象
objects=$(curl "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?tags=%7B%22Environment%22:%22dev%22%7D" | \
  jq -r '.objects[].objectKey')

# 步骤2: 批量更新为生产环境
for key in $objects; do
  curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
    -H "Content-Type: application/json" \
    -d "{
      \"bucket\": \"my-bucket\",
      \"objectKey\": \"$key\",
      \"updates\": {
        \"tags\": {\"Environment\": \"production\"}
      }
    }"
done
```

### 2. 健康检查 + 更新

```python
# 确保元数据服务健康后再批量更新
health = requests.get("http://localhost:9000/rustfs/admin/v3/sync/health").json()

if health["status"] == "healthy":
    # 执行批量更新
    update_metadata_batch(updates)
else:
    print(f"Service not healthy: {health['message']}")
    # 延迟更新或告警
```

## 相关文档

- [元数据查询 API](./S3_METADATA_QUERY_API.md)
- [数据库错误处理](./DATABASE_ERROR_HANDLING.md)
- [健康检查 API](./SYNC_HEALTH_API.md)

## 测试验证

### 单元测试

```bash
cargo test --package rustfs test_metadata_updates_deserialization
cargo test --package rustfs test_update_response_serialization
```

### 集成测试

```bash
# 1. 创建测试对象
aws s3 cp test.txt s3://test-bucket/test.txt

# 2. 更新元数据
curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "test-bucket",
    "objectKey": "test.txt",
    "updates": {
      "tags": {"Test": "true"}
    }
  }'

# 3. 验证更新
curl "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?bucket=test-bucket&prefix=test.txt"
```

## 监控建议

建议监控以下指标：
- 更新操作的成功率
- 404 响应（对象不存在）的比例
- 平均响应时间
- 数据库连接错误

示例日志查询：
```bash
# 查看更新失败的对象
grep "Failed to update S3 metadata" /var/log/rustfs/*.log

# 统计404响应
grep "Object not found or already deleted" /var/log/rustfs/*.log | wc -l
```
