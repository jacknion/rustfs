# RustFS S3 元数据管理 API 完整使用指南

## 目录

1. [概述](#概述)
2. [API 端点总览](#api-端点总览)
3. [元数据查询 API](#元数据查询-api)
4. [按标签查询 API](#按标签查询-api)
5. [元数据更新 API](#元数据更新-api)
6. [服务健康检查 API](#服务健康检查-api)
7. [完整使用示例](#完整使用示例)
8. [最佳实践](#最佳实践)
9. [故障排查](#故障排查)

---

## 概述

RustFS 提供了完整的 S3 对象元数据管理功能，允许您：

- 📊 **查询对象元数据** - 使用多种过滤条件搜索对象
- 🏷️ **按标签查询** - 基于对象标签快速检索
- ✏️ **更新元数据** - 修改对象属性而无需重新上传
- 🏥 **监控服务健康** - 实时检查元数据同步服务状态

### 架构说明

```
┌─────────────┐      ┌──────────────────┐      ┌──────────────┐
│   S3 API    │─────▶│  Metadata Hooks  │─────▶│  Sync Queue  │
│ (PUT/DELETE)│      │  (Non-blocking)  │      │  (Bounded)   │
└─────────────┘      └──────────────────┘      └──────┬───────┘
                                                       │
                                                       ▼
┌─────────────┐      ┌──────────────────┐      ┌──────────────┐
│  Query API  │◀─────│   PostgreSQL     │◀─────│ Sync Worker  │
│  (GET/POST) │      │   Database       │      │  (Batching)  │
└─────────────┘      └──────────────────┘      └──────────────┘
```

**关键特性：**
- ✅ 异步非阻塞元数据同步
- ✅ 批量处理优化（默认 100 条/批）
- ✅ 自动重试机制（3 次指数退避）
- ✅ 通道背压控制（最大 10,000 事件）
- ✅ N+1 查询优化（窗口函数）

---

## API 端点总览

| 端点 | 方法 | 功能 | 认证 |
|------|------|------|------|
| `/rustfs/admin/v3/s3/metadata/query` | GET | 元数据查询 | 需要 |
| `/rustfs/admin/v3/s3/metadata/query-by-tags` | POST | 按标签查询 | 需要 |
| `/rustfs/admin/v3/s3/metadata/update` | PUT | 更新元数据 | 需要 |
| `/rustfs/admin/v3/sync/health` | GET | 健康检查 | 需要 |

**Base URL:** `http://localhost:9000` (默认)

---

## 元数据查询 API

### 端点信息

```
GET /rustfs/admin/v3/s3/metadata/query
```

### 查询参数

| 参数 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `bucket` | string | ❌ | 桶名称过滤 | `my-bucket` |
| `prefix` | string | ❌ | 对象键前缀 | `logs/2024/` |
| `storage_class` | string | ❌ | 存储类别 | `GLACIER` |
| `encryption` | string | ❌ | 加密算法 | `AES256` |
| `owner_id` | string | ❌ | 所有者ID | `user123` |
| `min_size` | integer | ❌ | 最小大小（字节） | `1024` |
| `max_size` | integer | ❌ | 最大大小（字节） | `10485760` |
| `modified_after` | string | ❌ | 修改时间起始（RFC3339） | `2024-01-01T00:00:00Z` |
| `modified_before` | string | ❌ | 修改时间结束（RFC3339） | `2024-12-31T23:59:59Z` |
| `include_deleted` | boolean | ❌ | 包含已删除对象 | `false` |
| `limit` | integer | ❌ | 返回记录数（1-1000） | `100` |
| `offset` | integer | ❌ | 分页偏移量 | `0` |
| `tags` | string | ❌ | 标签JSON字符串 | `{"Project":"analytics"}` |

### 响应格式

```json
{
  "metadata": {
    "totalCount": 1523,
    "returnedCount": 100,
    "offset": 0,
    "queryTimeMs": 45
  },
  "objects": [
    {
      "id": 12345,
      "bucket": "my-bucket",
      "objectKey": "logs/2024/11/access.log",
      "versionId": null,
      "sizeBytes": 2048576,
      "contentType": "text/plain",
      "etag": "d41d8cd98f00b204e9800998ecf8427e",
      "storageClass": "STANDARD",
      "encryption": "AES256",
      "tags": {
        "Environment": "production",
        "Year": "2024"
      },
      "userMetadata": {
        "x-amz-meta-created-by": "log-collector"
      },
      "ownerId": "admin",
      "isDeleted": false,
      "lastModified": "2024-11-13T10:30:00Z",
      "createdAt": "2024-11-13T10:30:00Z",
      "updatedAt": "2024-11-13T10:30:00Z"
    }
  ]
}
```

### 使用示例

#### 示例 1: 查询特定桶的所有对象

```bash
curl -X GET "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?bucket=my-bucket&limit=50"
```

#### 示例 2: 按前缀查询日志文件

```bash
curl -X GET "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?bucket=logs&prefix=2024/11/&limit=100"
```

#### 示例 3: 查询大文件（>100MB）

```bash
curl -X GET "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?min_size=104857600&limit=20"
```

#### 示例 4: 查询特定时间范围的对象

```bash
curl -X GET "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?\
bucket=analytics&\
modified_after=2024-11-01T00:00:00Z&\
modified_before=2024-11-30T23:59:59Z&\
limit=100"
```

#### 示例 5: 复杂过滤条件

```bash
curl -X GET "http://localhost:9000/rustfs/admin/v3/s3/metadata/query?\
bucket=documents&\
prefix=contracts/&\
storage_class=GLACIER&\
min_size=1024&\
max_size=10485760&\
limit=50&\
offset=0"
```

#### 示例 6: 使用标签过滤

```bash
# URL编码的标签JSON: {"Environment":"production","Team":"backend"}
curl -X GET 'http://localhost:9000/rustfs/admin/v3/s3/metadata/query?tags=%7B%22Environment%22%3A%22production%22%2C%22Team%22%3A%22backend%22%7D&limit=100'
```

#### Python 客户端示例

```python
import requests
from urllib.parse import urlencode
from datetime import datetime, timedelta

def query_s3_metadata(
    bucket=None,
    prefix=None,
    storage_class=None,
    min_size=None,
    max_size=None,
    modified_after=None,
    modified_before=None,
    tags=None,
    limit=100,
    offset=0
):
    """查询S3对象元数据"""
    base_url = "http://localhost:9000/rustfs/admin/v3/s3/metadata/query"
    
    # 构建查询参数
    params = {}
    if bucket:
        params['bucket'] = bucket
    if prefix:
        params['prefix'] = prefix
    if storage_class:
        params['storage_class'] = storage_class
    if min_size:
        params['min_size'] = min_size
    if max_size:
        params['max_size'] = max_size
    if modified_after:
        params['modified_after'] = modified_after.isoformat() + 'Z'
    if modified_before:
        params['modified_before'] = modified_before.isoformat() + 'Z'
    if tags:
        import json
        params['tags'] = json.dumps(tags)
    params['limit'] = limit
    params['offset'] = offset
    
    response = requests.get(base_url, params=params)
    response.raise_for_status()
    
    return response.json()

# 使用示例1: 查询最近7天的大文件
result = query_s3_metadata(
    bucket="my-bucket",
    min_size=10 * 1024 * 1024,  # 10MB
    modified_after=datetime.utcnow() - timedelta(days=7),
    limit=50
)

print(f"找到 {result['metadata']['totalCount']} 个对象")
for obj in result['objects']:
    print(f"  - {obj['objectKey']}: {obj['sizeBytes']/1024/1024:.2f}MB")

# 使用示例2: 分页查询
def query_all_objects(bucket, batch_size=100):
    """分页查询所有对象"""
    offset = 0
    all_objects = []
    
    while True:
        result = query_s3_metadata(
            bucket=bucket,
            limit=batch_size,
            offset=offset
        )
        
        objects = result['objects']
        all_objects.extend(objects)
        
        print(f"已获取 {len(all_objects)}/{result['metadata']['totalCount']} 个对象")
        
        # 检查是否还有更多数据
        if len(objects) < batch_size:
            break
        
        offset += batch_size
    
    return all_objects

# 查询所有对象
all_objects = query_all_objects("my-bucket")
```

---

## 按标签查询 API

### 端点信息

```
POST /rustfs/admin/v3/s3/metadata/query-by-tags
```

### 请求体格式

```json
{
  "tags": {
    "key1": "value1",
    "key2": "value2"
  },
  "limit": 100,
  "bucket": "optional-bucket-filter",
  "prefix": "optional-prefix-filter",
  "includeDeleted": false
}
```

### 请求参数

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tags` | object | ✅ | 标签键值对（精确匹配） |
| `limit` | integer | ❌ | 返回记录数（1-1000，默认100） |
| `bucket` | string | ❌ | 额外的桶名称过滤 |
| `prefix` | string | ❌ | 额外的对象键前缀过滤 |
| `includeDeleted` | boolean | ❌ | 包含已删除对象（默认false） |

### 响应格式

与查询 API 相同的响应格式。

### 使用示例

#### 示例 1: 按单个标签查询

```bash
curl -X POST "http://localhost:9000/rustfs/admin/v3/s3/metadata/query-by-tags" \
  -H "Content-Type: application/json" \
  -d '{
    "tags": {
      "Environment": "production"
    },
    "limit": 100
  }'
```

#### 示例 2: 按多个标签查询（AND 逻辑）

```bash
curl -X POST "http://localhost:9000/rustfs/admin/v3/s3/metadata/query-by-tags" \
  -H "Content-Type: application/json" \
  -d '{
    "tags": {
      "Project": "analytics",
      "Environment": "production",
      "Year": "2024"
    },
    "limit": 50
  }'
```

#### 示例 3: 结合桶和前缀过滤

```bash
curl -X POST "http://localhost:9000/rustfs/admin/v3/s3/metadata/query-by-tags" \
  -H "Content-Type: application/json" \
  -d '{
    "tags": {
      "Type": "report"
    },
    "bucket": "documents",
    "prefix": "2024/",
    "limit": 100
  }'
```

#### Python 客户端示例

```python
import requests

def query_by_tags(tags, bucket=None, prefix=None, limit=100):
    """按标签查询对象"""
    url = "http://localhost:9000/rustfs/admin/v3/s3/metadata/query-by-tags"
    
    payload = {
        "tags": tags,
        "limit": limit
    }
    
    if bucket:
        payload["bucket"] = bucket
    if prefix:
        payload["prefix"] = prefix
    
    response = requests.post(url, json=payload)
    response.raise_for_status()
    
    return response.json()

# 使用示例1: 查找所有生产环境对象
result = query_by_tags({
    "Environment": "production"
})

print(f"生产环境对象数量: {result['metadata']['totalCount']}")

# 使用示例2: 查找特定项目的对象
result = query_by_tags(
    tags={
        "Project": "Q4-Analytics",
        "Department": "Sales"
    },
    bucket="analytics-data",
    limit=50
)

for obj in result['objects']:
    print(f"{obj['objectKey']}: {obj['tags']}")
```

---

## 元数据更新 API

### 端点信息

```
PUT /rustfs/admin/v3/s3/metadata/update
```

### 请求体格式

```json
{
  "bucket": "my-bucket",
  "objectKey": "path/to/object.txt",
  "updates": {
    "storageClass": "GLACIER",
    "encryption": "AES256",
    "contentType": "application/json",
    "tags": {
      "Environment": "production",
      "Year": "2024"
    },
    "userMetadata": {
      "x-amz-meta-custom": "value"
    },
    "ownerId": "user123"
  }
}
```

### 请求参数

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bucket` | string | ✅ | 桶名称 |
| `objectKey` | string | ✅ | 对象键（完整路径） |
| `updates` | object | ✅ | 要更新的字段（至少一个） |
| `updates.storageClass` | string | ❌ | 存储类别 |
| `updates.encryption` | string | ❌ | 加密算法 |
| `updates.contentType` | string | ❌ | MIME 类型 |
| `updates.tags` | object | ❌ | 对象标签（完全替换） |
| `updates.userMetadata` | object | ❌ | 用户元数据（完全替换） |
| `updates.ownerId` | string | ❌ | 所有者ID |

### 响应格式

```json
{
  "success": true,
  "message": "Metadata updated successfully",
  "rowsAffected": 1
}
```

### 不可修改字段

以下字段无法通过此 API 修改：
- `bucket` - 桶名称
- `objectKey` - 对象键
- `versionId` - 版本ID
- `sizeBytes` - 对象大小
- `etag` - ETag 值
- `lastModified` - 最后修改时间

### 使用示例

#### 示例 1: 更新存储类别

```bash
curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "logs",
    "objectKey": "2023/01/access.log",
    "updates": {
      "storageClass": "GLACIER"
    }
  }'
```

#### 示例 2: 更新对象标签

```bash
curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "documents",
    "objectKey": "contracts/2024/contract-001.pdf",
    "updates": {
      "tags": {
        "Status": "signed",
        "Year": "2024",
        "Department": "Legal"
      }
    }
  }'
```

#### 示例 3: 更新多个字段

```bash
curl -X PUT "http://localhost:9000/rustfs/admin/v3/s3/metadata/update" \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "analytics",
    "objectKey": "reports/q4-2024.csv",
    "updates": {
      "storageClass": "STANDARD_IA",
      "contentType": "text/csv",
      "tags": {
        "Quarter": "Q4",
        "Year": "2024",
        "Type": "report"
      },
      "userMetadata": {
        "x-amz-meta-generated-by": "reporting-tool-v2",
        "x-amz-meta-report-date": "2024-11-13"
      }
    }
  }'
```

#### Python 客户端示例

```python
import requests

def update_metadata(bucket, object_key, **updates):
    """更新对象元数据"""
    url = "http://localhost:9000/rustfs/admin/v3/s3/metadata/update"
    
    # 过滤掉None值
    filtered_updates = {k: v for k, v in updates.items() if v is not None}
    
    if not filtered_updates:
        raise ValueError("至少需要提供一个更新字段")
    
    payload = {
        "bucket": bucket,
        "objectKey": object_key,
        "updates": filtered_updates
    }
    
    response = requests.put(url, json=payload)
    response.raise_for_status()
    
    return response.json()

# 使用示例1: 归档旧日志
result = update_metadata(
    bucket="logs",
    object_key="2023/12/access.log",
    storageClass="GLACIER"
)
print(result['message'])

# 使用示例2: 添加标签
result = update_metadata(
    bucket="images",
    object_key="photos/vacation/beach.jpg",
    tags={
        "Location": "Hawaii",
        "Year": "2024",
        "Event": "Vacation"
    }
)

# 使用示例3: 批量更新（保留现有标签）
def update_tags_merge(bucket, object_key, new_tags):
    """合并更新标签（保留现有标签）"""
    # 1. 查询当前对象
    current = query_s3_metadata(bucket=bucket, prefix=object_key, limit=1)
    
    if not current['objects']:
        raise ValueError(f"对象不存在: {bucket}/{object_key}")
    
    # 2. 获取当前标签
    current_tags = current['objects'][0].get('tags') or {}
    
    # 3. 合并新标签
    merged_tags = {**current_tags, **new_tags}
    
    # 4. 更新
    return update_metadata(bucket, object_key, tags=merged_tags)

# 添加新标签而不删除旧标签
update_tags_merge(
    bucket="documents",
    object_key="report.pdf",
    new_tags={"Status": "reviewed"}  # 保留其他现有标签
)
```

#### 批量更新脚本示例

```python
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

def batch_update_storage_class(bucket, prefix, new_storage_class, max_workers=10):
    """批量更新存储类别"""
    # 1. 查询所有匹配的对象
    all_objects = []
    offset = 0
    batch_size = 100
    
    print(f"正在查询 {bucket}/{prefix} 下的对象...")
    while True:
        result = query_s3_metadata(
            bucket=bucket,
            prefix=prefix,
            limit=batch_size,
            offset=offset
        )
        
        objects = result['objects']
        all_objects.extend(objects)
        
        if len(objects) < batch_size:
            break
        
        offset += batch_size
    
    print(f"找到 {len(all_objects)} 个对象需要更新")
    
    # 2. 并发更新
    def update_one(obj):
        try:
            result = update_metadata(
                bucket=obj['bucket'],
                object_key=obj['objectKey'],
                storageClass=new_storage_class
            )
            return {'success': True, 'key': obj['objectKey']}
        except Exception as e:
            return {'success': False, 'key': obj['objectKey'], 'error': str(e)}
    
    results = {'success': 0, 'failed': 0, 'errors': []}
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(update_one, obj) for obj in all_objects]
        
        for future in tqdm(as_completed(futures), total=len(all_objects), desc="更新进度"):
            result = future.result()
            if result['success']:
                results['success'] += 1
            else:
                results['failed'] += 1
                results['errors'].append(result)
    
    print(f"\n更新完成: 成功 {results['success']}, 失败 {results['failed']}")
    
    if results['errors']:
        print("\n失败的对象:")
        for error in results['errors'][:10]:  # 显示前10个错误
            print(f"  - {error['key']}: {error['error']}")
    
    return results

# 使用示例：将所有2023年的日志归档到GLACIER
batch_update_storage_class(
    bucket="logs",
    prefix="2023/",
    new_storage_class="GLACIER",
    max_workers=20
)
```

---

## 服务健康检查 API

### 端点信息

```
GET /rustfs/admin/v3/sync/health
```

### 响应格式

```json
{
  "status": "healthy",
  "syncStats": {
    "upsertSuccess": 12456,
    "upsertFailed": 3,
    "deleteSuccess": 892,
    "deleteFailed": 0,
    "eventsDropped": 0,
    "totalProcessed": 13348,
    "totalFailed": 3,
    "successRate": 0.9998
  },
  "message": "Metadata sync service is operating normally"
}
```

### 状态级别

| 状态 | 条件 | HTTP 状态码 | 说明 |
|------|------|------------|------|
| `healthy` | 成功率 > 95% 且丢弃 < 1000 | 200 OK | 服务正常 |
| `degraded` | 成功率 80-95% 或 丢弃 >= 1000 | 200 OK | 服务降级 |
| `unhealthy` | 成功率 < 80% | 503 | 服务异常 |
| `unavailable` | 服务未初始化 | 503 | 服务不可用 |

### 使用示例

#### 示例 1: 基本健康检查

```bash
curl -X GET "http://localhost:9000/rustfs/admin/v3/sync/health"
```

#### 示例 2: Python 监控脚本

```python
import requests
import time
from datetime import datetime

def check_health():
    """检查元数据同步服务健康状态"""
    url = "http://localhost:9000/rustfs/admin/v3/sync/health"
    
    try:
        response = requests.get(url, timeout=5)
        data = response.json()
        
        status = data['status']
        stats = data.get('syncStats', {})
        
        return {
            'healthy': status == 'healthy',
            'status': status,
            'success_rate': stats.get('successRate', 0),
            'events_dropped': stats.get('eventsDropped', 0),
            'total_processed': stats.get('totalProcessed', 0),
            'message': data.get('message', '')
        }
    except Exception as e:
        return {
            'healthy': False,
            'status': 'error',
            'error': str(e)
        }

# 使用示例1: 单次检查
health = check_health()
print(f"状态: {health['status']}")
print(f"成功率: {health['success_rate']*100:.2f}%")
print(f"已处理: {health['total_processed']}")
print(f"丢弃: {health['events_dropped']}")

# 使用示例2: 持续监控
def monitor_health(interval=60):
    """持续监控健康状态"""
    print("开始监控元数据同步服务健康状态...")
    print("按 Ctrl+C 停止\n")
    
    try:
        while True:
            health = check_health()
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            status_emoji = {
                'healthy': '🟢',
                'degraded': '🟡',
                'unhealthy': '🔴',
                'error': '⚫'
            }.get(health['status'], '❓')
            
            print(f"[{timestamp}] {status_emoji} {health['status'].upper()}")
            
            if health.get('success_rate'):
                print(f"  成功率: {health['success_rate']*100:.2f}%")
                print(f"  已处理: {health['total_processed']}")
                print(f"  丢弃: {health['events_dropped']}")
            
            if not health['healthy']:
                print(f"  ⚠️ {health.get('message', health.get('error', 'Unknown'))}")
                # 发送告警（邮件、Slack等）
                # send_alert(health)
            
            print()
            time.sleep(interval)
    
    except KeyboardInterrupt:
        print("\n监控已停止")

# 每60秒检查一次
monitor_health(interval=60)
```

#### 示例 3: 集成到 CI/CD

```bash
#!/bin/bash
# check_metadata_service.sh - 部署前检查元数据服务健康

ENDPOINT="http://localhost:9000/rustfs/admin/v3/sync/health"
MAX_RETRIES=3
RETRY_DELAY=5

echo "检查 RustFS 元数据同步服务健康状态..."

for i in $(seq 1 $MAX_RETRIES); do
    response=$(curl -s -w "\n%{http_code}" "$ENDPOINT")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "200" ]; then
        status=$(echo "$body" | jq -r '.status')
        success_rate=$(echo "$body" | jq -r '.syncStats.successRate')
        
        echo "状态: $status"
        echo "成功率: $(echo "$success_rate * 100" | bc)%"
        
        if [ "$status" = "healthy" ]; then
            echo "✅ 服务健康，可以继续部署"
            exit 0
        elif [ "$status" = "degraded" ]; then
            echo "⚠️ 服务降级，建议检查后再部署"
            exit 1
        fi
    fi
    
    echo "❌ 检查失败 (尝试 $i/$MAX_RETRIES)"
    
    if [ $i -lt $MAX_RETRIES ]; then
        echo "等待 ${RETRY_DELAY}s 后重试..."
        sleep $RETRY_DELAY
    fi
done

echo "❌ 元数据服务不健康，部署中止"
exit 1
```

---

## 完整使用示例

### 场景 1: 对象生命周期管理

将超过 90 天的日志文件自动归档到 GLACIER：

```python
from datetime import datetime, timedelta
import requests

def archive_old_logs(bucket, days_old=90, dry_run=True):
    """归档旧日志文件"""
    cutoff_date = datetime.utcnow() - timedelta(days=days_old)
    
    print(f"查询 {days_old} 天前的对象...")
    
    # 1. 查询旧对象
    result = query_s3_metadata(
        bucket=bucket,
        modified_before=cutoff_date,
        storage_class="STANDARD",  # 只归档STANDARD类别
        limit=1000
    )
    
    total = result['metadata']['totalCount']
    objects = result['objects']
    
    print(f"找到 {total} 个需要归档的对象")
    
    if dry_run:
        print("\n预览模式，不执行实际归档:")
        for obj in objects[:10]:  # 显示前10个
            size_mb = obj['sizeBytes'] / 1024 / 1024
            print(f"  - {obj['objectKey']} ({size_mb:.2f}MB)")
        print(f"  ... 还有 {len(objects)-10} 个对象")
        return
    
    # 2. 批量归档
    archived = 0
    failed = 0
    
    for obj in objects:
        try:
            update_metadata(
                bucket=obj['bucket'],
                object_key=obj['objectKey'],
                storageClass="GLACIER"
            )
            archived += 1
            
            if archived % 100 == 0:
                print(f"已归档 {archived}/{total} 个对象")
        
        except Exception as e:
            print(f"归档失败 {obj['objectKey']}: {e}")
            failed += 1
    
    print(f"\n归档完成:")
    print(f"  成功: {archived}")
    print(f"  失败: {failed}")
    
    return {'archived': archived, 'failed': failed}

# 预览模式
archive_old_logs("logs", days_old=90, dry_run=True)

# 执行归档
# archive_old_logs("logs", days_old=90, dry_run=False)
```

### 场景 2: 标签管理和分类

为所有缺少标签的对象自动添加标签：

```python
def auto_tag_objects(bucket, prefix=""):
    """根据对象路径自动添加标签"""
    
    # 1. 查询所有对象
    all_objects = []
    offset = 0
    
    while True:
        result = query_s3_metadata(
            bucket=bucket,
            prefix=prefix,
            limit=100,
            offset=offset
        )
        
        all_objects.extend(result['objects'])
        
        if len(result['objects']) < 100:
            break
        
        offset += 100
    
    print(f"找到 {len(all_objects)} 个对象")
    
    # 2. 分析和打标签
    updated = 0
    
    for obj in all_objects:
        # 跳过已有标签的对象
        if obj.get('tags'):
            continue
        
        # 根据路径生成标签
        parts = obj['objectKey'].split('/')
        tags = {}
        
        # 示例：logs/2024/11/access.log
        if len(parts) >= 3 and parts[0] == 'logs':
            tags['Type'] = 'log'
            tags['Year'] = parts[1]
            tags['Month'] = parts[2]
        
        # 示例：documents/contracts/2024/contract.pdf
        elif len(parts) >= 2 and parts[0] == 'documents':
            tags['Type'] = 'document'
            tags['Category'] = parts[1]
        
        # 通用标签
        tags['Bucket'] = bucket
        
        # 更新标签
        if tags:
            try:
                update_metadata(
                    bucket=obj['bucket'],
                    object_key=obj['objectKey'],
                    tags=tags
                )
                updated += 1
                print(f"已打标签: {obj['objectKey']} -> {tags}")
            
            except Exception as e:
                print(f"打标签失败 {obj['objectKey']}: {e}")
    
    print(f"\n完成: {updated} 个对象已添加标签")
    
    return updated

# 为 logs 桶下的所有对象自动打标签
auto_tag_objects("logs")
```

### 场景 3: 数据审计和报告

生成对象存储使用报告：

```python
from collections import defaultdict
import json

def generate_storage_report(bucket=None):
    """生成存储使用报告"""
    print("正在生成存储报告...")
    
    # 1. 查询所有对象
    all_objects = []
    offset = 0
    
    while True:
        result = query_s3_metadata(
            bucket=bucket,
            limit=1000,
            offset=offset
        )
        
        all_objects.extend(result['objects'])
        
        print(f"  已加载 {len(all_objects)} 个对象...")
        
        if len(result['objects']) < 1000:
            break
        
        offset += 1000
    
    # 2. 统计分析
    report = {
        'total_objects': len(all_objects),
        'total_size_bytes': 0,
        'by_storage_class': defaultdict(lambda: {'count': 0, 'size': 0}),
        'by_bucket': defaultdict(lambda: {'count': 0, 'size': 0}),
        'by_content_type': defaultdict(lambda: {'count': 0, 'size': 0}),
        'by_encryption': defaultdict(lambda: {'count': 0, 'size': 0}),
        'deleted_objects': 0,
        'tagged_objects': 0,
        'encryption_coverage': 0
    }
    
    for obj in all_objects:
        size = obj['sizeBytes']
        report['total_size_bytes'] += size
        
        # 按存储类别
        storage_class = obj.get('storageClass') or 'UNKNOWN'
        report['by_storage_class'][storage_class]['count'] += 1
        report['by_storage_class'][storage_class]['size'] += size
        
        # 按桶
        bucket_name = obj['bucket']
        report['by_bucket'][bucket_name]['count'] += 1
        report['by_bucket'][bucket_name]['size'] += size
        
        # 按内容类型
        content_type = obj.get('contentType') or 'UNKNOWN'
        report['by_content_type'][content_type]['count'] += 1
        report['by_content_type'][content_type]['size'] += size
        
        # 按加密
        encryption = obj.get('encryption') or 'NONE'
        report['by_encryption'][encryption]['count'] += 1
        report['by_encryption'][encryption]['size'] += size
        
        # 其他统计
        if obj.get('isDeleted'):
            report['deleted_objects'] += 1
        
        if obj.get('tags'):
            report['tagged_objects'] += 1
        
        if obj.get('encryption'):
            report['encryption_coverage'] += 1
    
    # 3. 计算百分比
    total = report['total_objects']
    report['tagged_percentage'] = (report['tagged_objects'] / total * 100) if total > 0 else 0
    report['encryption_percentage'] = (report['encryption_coverage'] / total * 100) if total > 0 else 0
    
    # 4. 格式化输出
    print("\n" + "="*60)
    print("存储使用报告")
    print("="*60)
    
    print(f"\n总计:")
    print(f"  对象数量: {report['total_objects']:,}")
    print(f"  总大小: {report['total_size_bytes']/1024/1024/1024:.2f} GB")
    print(f"  已删除: {report['deleted_objects']}")
    print(f"  有标签: {report['tagged_objects']} ({report['tagged_percentage']:.1f}%)")
    print(f"  已加密: {report['encryption_coverage']} ({report['encryption_percentage']:.1f}%)")
    
    print(f"\n按存储类别:")
    for sc, stats in sorted(report['by_storage_class'].items()):
        print(f"  {sc:20} {stats['count']:8,} 对象  {stats['size']/1024/1024/1024:10.2f} GB")
    
    print(f"\n按桶:")
    for bucket, stats in sorted(report['by_bucket'].items(), key=lambda x: x[1]['size'], reverse=True):
        print(f"  {bucket:20} {stats['count']:8,} 对象  {stats['size']/1024/1024/1024:10.2f} GB")
    
    print(f"\n按内容类型 (前10):")
    top_types = sorted(report['by_content_type'].items(), key=lambda x: x[1]['count'], reverse=True)[:10]
    for ct, stats in top_types:
        print(f"  {ct:30} {stats['count']:8,} 对象")
    
    # 5. 保存为JSON
    report_file = f"storage_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    
    # 转换 defaultdict 为 dict
    report_json = {
        **report,
        'by_storage_class': dict(report['by_storage_class']),
        'by_bucket': dict(report['by_bucket']),
        'by_content_type': dict(report['by_content_type']),
        'by_encryption': dict(report['by_encryption'])
    }
    
    with open(report_file, 'w') as f:
        json.dump(report_json, f, indent=2)
    
    print(f"\n报告已保存到: {report_file}")
    
    return report

# 生成全局报告
report = generate_storage_report()

# 或者生成特定桶的报告
# report = generate_storage_report(bucket="my-bucket")
```

### 场景 4: 合规性检查

检查所有对象是否符合安全策略：

```python
def compliance_check(bucket):
    """检查对象是否符合合规策略"""
    
    issues = {
        'missing_encryption': [],
        'missing_tags': [],
        'wrong_storage_class': [],
        'outdated_objects': []
    }
    
    # 定义合规策略
    REQUIRED_TAGS = ['Environment', 'Department', 'Owner']
    ALLOWED_STORAGE_CLASSES = ['STANDARD', 'GLACIER']
    MAX_AGE_DAYS = 365
    
    print(f"正在检查 {bucket} 的合规性...")
    
    # 查询所有对象
    offset = 0
    checked = 0
    
    while True:
        result = query_s3_metadata(
            bucket=bucket,
            limit=100,
            offset=offset
        )
        
        for obj in result['objects']:
            checked += 1
            
            # 检查1: 必须加密
            if not obj.get('encryption'):
                issues['missing_encryption'].append(obj['objectKey'])
            
            # 检查2: 必须有必需标签
            tags = obj.get('tags') or {}
            missing_tags = [tag for tag in REQUIRED_TAGS if tag not in tags]
            if missing_tags:
                issues['missing_tags'].append({
                    'key': obj['objectKey'],
                    'missing': missing_tags
                })
            
            # 检查3: 存储类别
            storage_class = obj.get('storageClass')
            if storage_class not in ALLOWED_STORAGE_CLASSES:
                issues['wrong_storage_class'].append({
                    'key': obj['objectKey'],
                    'current': storage_class
                })
            
            # 检查4: 对象年龄
            modified = datetime.fromisoformat(obj['lastModified'].replace('Z', '+00:00'))
            age_days = (datetime.now(modified.tzinfo) - modified).days
            if age_days > MAX_AGE_DAYS and storage_class == 'STANDARD':
                issues['outdated_objects'].append({
                    'key': obj['objectKey'],
                    'age_days': age_days
                })
        
        if len(result['objects']) < 100:
            break
        
        offset += 100
    
    # 生成报告
    print(f"\n合规性检查完成 (检查了 {checked} 个对象)")
    print("="*60)
    
    total_issues = sum(len(v) for v in issues.values())
    
    if total_issues == 0:
        print("✅ 所有对象均符合合规策略")
    else:
        print(f"⚠️ 发现 {total_issues} 个合规问题:\n")
        
        if issues['missing_encryption']:
            print(f"❌ 缺少加密 ({len(issues['missing_encryption'])} 个对象):")
            for key in issues['missing_encryption'][:5]:
                print(f"   - {key}")
            if len(issues['missing_encryption']) > 5:
                print(f"   ... 还有 {len(issues['missing_encryption'])-5} 个")
        
        if issues['missing_tags']:
            print(f"\n❌ 缺少必需标签 ({len(issues['missing_tags'])} 个对象):")
            for item in issues['missing_tags'][:5]:
                print(f"   - {item['key']}: 缺少 {', '.join(item['missing'])}")
            if len(issues['missing_tags']) > 5:
                print(f"   ... 还有 {len(issues['missing_tags'])-5} 个")
        
        if issues['wrong_storage_class']:
            print(f"\n❌ 存储类别不符 ({len(issues['wrong_storage_class'])} 个对象):")
            for item in issues['wrong_storage_class'][:5]:
                print(f"   - {item['key']}: {item['current']}")
        
        if issues['outdated_objects']:
            print(f"\n❌ 过期对象未归档 ({len(issues['outdated_objects'])} 个对象):")
            for item in issues['outdated_objects'][:5]:
                print(f"   - {item['key']}: {item['age_days']} 天")
    
    return issues

# 检查合规性
issues = compliance_check("production-data")

# 自动修复（可选）
if issues['outdated_objects']:
    print("\n是否将过期对象归档到GLACIER? (y/n)")
    if input().lower() == 'y':
        for item in issues['outdated_objects']:
            update_metadata(
                bucket="production-data",
                object_key=item['key'],
                storageClass="GLACIER"
            )
        print("✅ 已归档所有过期对象")
```

---

## 最佳实践

### 1. 查询优化

```python
# ✅ 好：使用精确的过滤条件
query_s3_metadata(
    bucket="my-bucket",
    prefix="logs/2024/11/",
    limit=100
)

# ❌ 差：过于宽泛的查询
query_s3_metadata(
    limit=10000  # 可能超时
)

# ✅ 好：分页查询大量数据
def query_with_pagination(bucket, batch_size=100):
    offset = 0
    while True:
        result = query_s3_metadata(bucket=bucket, limit=batch_size, offset=offset)
        yield from result['objects']
        
        if len(result['objects']) < batch_size:
            break
        
        offset += batch_size

# ❌ 差：一次性加载所有数据
all_data = query_s3_metadata(bucket="huge-bucket", limit=100000)
```

### 2. 标签管理

```python
# ❌ 错误：直接更新会删除现有标签
update_metadata(
    bucket="my-bucket",
    object_key="file.txt",
    tags={"NewTag": "value"}  # 丢失所有旧标签！
)

# ✅ 正确：先查询再合并
current = query_s3_metadata(bucket="my-bucket", prefix="file.txt", limit=1)
current_tags = current['objects'][0].get('tags') or {}
merged_tags = {**current_tags, "NewTag": "value"}

update_metadata(
    bucket="my-bucket",
    object_key="file.txt",
    tags=merged_tags
)
```

### 3. 批量操作

```python
# ✅ 好：控制并发数
from concurrent.futures import ThreadPoolExecutor

def batch_update(updates, max_workers=10):
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(update_metadata, **upd) for upd in updates]
        results = [f.result() for f in futures]
    return results

# ❌ 差：无限制并发
import asyncio

async def bad_batch_update(updates):
    tasks = [update_async(**upd) for upd in updates]  # 可能上千个并发
    await asyncio.gather(*tasks)
```

### 4. 错误处理

```python
# ✅ 好：优雅的错误处理
def safe_update(bucket, object_key, **updates):
    max_retries = 3
    retry_delay = 1
    
    for attempt in range(max_retries):
        try:
            return update_metadata(bucket, object_key, **updates)
        
        except requests.exceptions.Timeout:
            if attempt < max_retries - 1:
                time.sleep(retry_delay * (2 ** attempt))  # 指数退避
                continue
            raise
        
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 404:
                print(f"对象不存在: {bucket}/{object_key}")
                return None
            elif e.response.status_code >= 500:
                # 服务器错误，可以重试
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
            raise

# ❌ 差：忽略错误
try:
    update_metadata(bucket, key, tags={})
except:
    pass  # 静默失败
```

### 5. 性能监控

```python
import time

def monitored_query(*args, **kwargs):
    """带性能监控的查询"""
    start = time.time()
    
    try:
        result = query_s3_metadata(*args, **kwargs)
        elapsed = time.time() - start
        
        # 记录慢查询
        if elapsed > 1.0:
            print(f"⚠️ 慢查询 ({elapsed:.2f}s): {kwargs}")
        
        return result
    
    except Exception as e:
        elapsed = time.time() - start
        print(f"❌ 查询失败 ({elapsed:.2f}s): {e}")
        raise
```

---

## 故障排查

### 问题 1: 查询返回空结果

**症状：**
```python
result = query_s3_metadata(bucket="my-bucket", prefix="logs/")
print(result['metadata']['totalCount'])  # 输出: 0
```

**排查步骤：**

1. 检查对象是否已同步到数据库：
```bash
# 检查同步服务健康状态
curl http://localhost:9000/rustfs/admin/v3/sync/health
```

2. 检查查询条件：
```python
# 尝试不带过滤条件查询
result = query_s3_metadata(limit=10)
print(f"数据库中共有 {result['metadata']['totalCount']} 个对象")
```

3. 检查是否包含已删除对象：
```python
result = query_s3_metadata(
    bucket="my-bucket",
    include_deleted=True  # 包含已删除对象
)
```

### 问题 2: 更新失败返回 404

**症状：**
```json
{
  "success": false,
  "message": "Object not found or already deleted: bucket=test, key=file.txt",
  "rowsAffected": 0
}
```

**原因：**
- 对象不存在于数据库（可能尚未同步）
- 对象已被删除（`is_deleted = true`）
- bucket 或 objectKey 拼写错误

**解决：**
```python
# 1. 确认对象存在
result = query_s3_metadata(bucket="test", prefix="file.txt", limit=1)
if not result['objects']:
    print("对象未同步到数据库")
    # 等待同步或手动触发同步

# 2. 检查是否已删除
result = query_s3_metadata(
    bucket="test",
    prefix="file.txt",
    include_deleted=True,
    limit=1
)
if result['objects'] and result['objects'][0]['isDeleted']:
    print("对象已删除，无法更新")
```

### 问题 3: 同步延迟

**症状：**
刚上传的对象无法立即查询到。

**原因：**
- 异步同步机制有延迟（通常 < 1秒）
- 同步队列满导致丢弃事件
- 数据库性能问题

**排查：**
```python
import time

# 上传对象后等待同步
def wait_for_sync(bucket, object_key, timeout=10):
    """等待对象同步到数据库"""
    start = time.time()
    
    while time.time() - start < timeout:
        result = query_s3_metadata(bucket=bucket, prefix=object_key, limit=1)
        
        if result['objects']:
            print(f"✅ 对象已同步 (用时 {time.time()-start:.2f}s)")
            return result['objects'][0]
        
        time.sleep(0.5)
    
    print(f"❌ 同步超时 ({timeout}s)")
    return None

# 检查同步服务状态
health = check_health()
if health['events_dropped'] > 0:
    print(f"⚠️ 有 {health['events_dropped']} 个事件被丢弃")
```

### 问题 4: 数据库连接失败

**症状：**
```
Database connection failed. Please try again later.
```

**排查：**
```bash
# 1. 检查PostgreSQL是否运行
systemctl status postgresql

# 2. 测试数据库连接
psql -h localhost -U rustfs -d rustfs_metadata -c "SELECT 1;"

# 3. 检查连接池状态（查看日志）
grep "Database pool" /var/log/rustfs/*.log

# 4. 检查网络
telnet localhost 5432
```

### 问题 5: 查询超时

**症状：**
```
Database query timeout. Please refine your search criteria.
```

**解决：**
```python
# 1. 添加更具体的过滤条件
result = query_s3_metadata(
    bucket="large-bucket",
    prefix="2024/11/",  # 缩小范围
    limit=100  # 限制返回数
)

# 2. 检查数据库索引
# 运行索引验证脚本
# ./scripts/check_db_indexes.sh

# 3. 分批查询
def query_in_batches(bucket, batch_size=100):
    offset = 0
    
    while True:
        try:
            result = query_s3_metadata(
                bucket=bucket,
                limit=batch_size,
                offset=offset,
                timeout=30  # 设置超时
            )
            
            yield result['objects']
            
            if len(result['objects']) < batch_size:
                break
            
            offset += batch_size
        
        except Timeout:
            print(f"查询超时，跳过 offset={offset}")
            offset += batch_size
```

---

## 相关文档

- [数据库索引指南](./DATABASE_INDEX_GUIDE.md) - 索引创建和优化
- [数据库错误处理](./DATABASE_ERROR_HANDLING.md) - 错误处理详解
- [N+1 查询优化](./N1_QUERY_OPTIMIZATION.md) - 性能优化说明
- [环境变量配置](./ENVIRONMENT_VARIABLES.md) - 配置参数

---

## 附录

### API 错误码参考

| HTTP 状态码 | 错误码 | 说明 |
|-----------|--------|------|
| 200 | - | 请求成功 |
| 400 | InvalidRequest | 请求参数错误 |
| 404 | - | 对象不存在 |
| 500 | InternalError | 服务器内部错误 |
| 503 | - | 服务不可用 |

### 性能基准

在标准配置下（PostgreSQL 16, 8 核 CPU, 16GB RAM）：

| 操作 | 延迟 (P50) | 延迟 (P99) | 吞吐量 |
|------|-----------|-----------|--------|
| 简单查询 | 15ms | 50ms | 2000 req/s |
| 复杂查询（多过滤） | 45ms | 150ms | 500 req/s |
| 按标签查询 | 30ms | 100ms | 1000 req/s |
| 元数据更新 | 20ms | 80ms | 1500 req/s |
| 健康检查 | 5ms | 20ms | 5000 req/s |

### 配置建议

```toml
# 元数据同步服务配置
[metadata_sync]
batch_size = 100              # 批次大小
flush_interval_secs = 1       # 刷新间隔（秒）
max_queue_size = 10000        # 最大队列大小
max_retries = 3               # 最大重试次数
retry_delay_ms = 100          # 重试延迟（毫秒）

# 查询限制
[metadata_query]
default_limit = 100           # 默认返回数
max_limit = 1000              # 最大返回数
query_timeout_secs = 30       # 查询超时（秒）
```

---

**文档版本：** 1.0  
**最后更新：** 2024-11-13  
**维护者：** RustFS Team
