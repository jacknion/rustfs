# RustFS 标签 API 参考文档

## 概述

RustFS 提供完整的 S3 兼容标签管理 API，支持对象标签的增删改查操作，并提供高级查询功能。所有标签操作会自动同步到 PostgreSQL 数据库（如果配置了数据库）。

## 目录

- [对象标签操作](#对象标签操作)
  - [PUT Object Tagging](#put-object-tagging)
  - [GET Object Tagging](#get-object-tagging)
  - [DELETE Object Tagging](#delete-object-tagging)
  - [PUT Object (带标签)](#put-object-带标签)
- [标签查询 API](#标签查询-api)
  - [精确匹配查询](#精确匹配查询)
  - [模糊搜索查询](#模糊搜索查询)
  - [分页查询](#分页查询)
- [标签限制](#标签限制)
- [最佳实践](#最佳实践)
- [示例代码](#示例代码)

---

## 对象标签操作

### PUT Object Tagging

为已存在的对象添加或更新标签。

**端点**
```
PUT /{bucket}/{object}?tagging
```

**请求头**
```
Content-Type: application/xml
Content-MD5: <md5-hash>  (可选)
x-amz-tagging-directive: REPLACE  (默认)
```

**请求体**
```xml
<Tagging>
  <TagSet>
    <Tag>
      <Key>Project</Key>
      <Value>Analytics</Value>
    </Tag>
    <Tag>
      <Key>Environment</Key>
      <Value>Production</Value>
    </Tag>
  </TagSet>
</Tagging>
```

**响应**
```
HTTP/1.1 200 OK
```

**示例（AWS CLI）**
```bash
# 设置标签
aws s3api put-object-tagging \
  --bucket my-bucket \
  --key my-object.txt \
  --tagging 'TagSet=[{Key=Project,Value=Analytics},{Key=Environment,Value=Production}]' \
  --endpoint-url http://localhost:9000

# 使用文件设置标签
cat > tags.json <<EOF
{
  "TagSet": [
    {"Key": "Project", "Value": "Analytics"},
    {"Key": "Owner", "Value": "DataTeam"},
    {"Key": "CostCenter", "Value": "CC-1234"}
  ]
}
EOF

aws s3api put-object-tagging \
  --bucket my-bucket \
  --key my-object.txt \
  --tagging file://tags.json \
  --endpoint-url http://localhost:9000
```

**示例（Python boto3）**
```python
import boto3

s3 = boto3.client('s3', endpoint_url='http://localhost:9000')

# 设置标签
s3.put_object_tagging(
    Bucket='my-bucket',
    Key='my-object.txt',
    Tagging={
        'TagSet': [
            {'Key': 'Project', 'Value': 'Analytics'},
            {'Key': 'Environment', 'Value': 'Production'},
            {'Key': 'Owner', 'Value': 'alice'}
        ]
    }
)
```

**特性**
- ✅ 自动同步到数据库（如果配置了 PostgreSQL）
- ✅ 支持批量更新（覆盖所有已有标签）
- ✅ 异步处理，不阻塞响应
- ✅ 自动重试机制

---

### GET Object Tagging

获取对象的标签。

**端点**
```
GET /{bucket}/{object}?tagging
```

**请求头**
```
(无特殊头部要求)
```

**响应**
```xml
HTTP/1.1 200 OK
Content-Type: application/xml

<Tagging>
  <TagSet>
    <Tag>
      <Key>Project</Key>
      <Value>Analytics</Value>
    </Tag>
    <Tag>
      <Key>Environment</Key>
      <Value>Production</Value>
    </Tag>
  </TagSet>
</Tagging>
```

**示例（AWS CLI）**
```bash
aws s3api get-object-tagging \
  --bucket my-bucket \
  --key my-object.txt \
  --endpoint-url http://localhost:9000
```

**示例（Python boto3）**
```python
response = s3.get_object_tagging(
    Bucket='my-bucket',
    Key='my-object.txt'
)

print("Tags:", response['TagSet'])
# 输出: Tags: [{'Key': 'Project', 'Value': 'Analytics'}, ...]
```

**示例（curl）**
```bash
curl -X GET "http://localhost:9000/my-bucket/my-object.txt?tagging" \
  -H "Authorization: AWS4-HMAC-SHA256 ..."
```

---

### DELETE Object Tagging

删除对象的所有标签。

**端点**
```
DELETE /{bucket}/{object}?tagging
```

**请求头**
```
(无特殊头部要求)
```

**响应**
```
HTTP/1.1 204 No Content
```

**示例（AWS CLI）**
```bash
aws s3api delete-object-tagging \
  --bucket my-bucket \
  --key my-object.txt \
  --endpoint-url http://localhost:9000
```

**示例（Python boto3）**
```python
s3.delete_object_tagging(
    Bucket='my-bucket',
    Key='my-object.txt'
)
print("Tags deleted successfully")
```

**特性**
- ✅ 清空对象的所有标签
- ✅ 自动同步到数据库（标签字段设为空）
- ✅ 不影响对象本身的数据和元数据

---

### PUT Object (带标签)

上传对象时同时设置标签。

**端点**
```
PUT /{bucket}/{object}
```

**请求头**
```
Content-Type: <mime-type>
x-amz-tagging: <url-encoded-tags>
```

**标签格式**
```
x-amz-tagging: Key1=Value1&Key2=Value2&Key3=Value3
```

**示例（AWS CLI）**
```bash
# 上传文件并设置标签
aws s3 cp local-file.txt s3://my-bucket/remote-file.txt \
  --tagging "Project=Analytics&Environment=Production&Owner=alice" \
  --endpoint-url http://localhost:9000

# 或使用 put-object
aws s3api put-object \
  --bucket my-bucket \
  --key my-object.txt \
  --body local-file.txt \
  --tagging "Project=Analytics&Environment=Production" \
  --endpoint-url http://localhost:9000
```

**示例（Python boto3）**
```python
# 方式1：使用 Tagging 参数
s3.put_object(
    Bucket='my-bucket',
    Key='my-object.txt',
    Body=b'file content',
    Tagging='Project=Analytics&Environment=Production&Owner=alice'
)

# 方式2：上传后再设置标签
s3.put_object(Bucket='my-bucket', Key='my-object.txt', Body=b'content')
s3.put_object_tagging(
    Bucket='my-bucket',
    Key='my-object.txt',
    Tagging={'TagSet': [{'Key': 'Project', 'Value': 'Analytics'}]}
)
```

**示例（curl）**
```bash
curl -X PUT "http://localhost:9000/my-bucket/my-object.txt" \
  -H "x-amz-tagging: Project=Analytics&Environment=Production" \
  -H "Content-Type: text/plain" \
  --data-binary "@local-file.txt"
```

---

## 标签查询 API

RustFS 提供强大的标签查询功能，支持精确匹配和模糊搜索。

### 精确匹配查询

查询包含指定标签的所有对象。

**端点**
```
GET /rustfs/admin/v3/s3-metadata/query-by-tags?tags[Key1]=Value1&tags[Key2]=Value2
POST /rustfs/admin/v3/s3-metadata/query-by-tags
```

**GET 请求示例**
```bash
# 查询 Project=Analytics 的所有对象
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags[Project]=Analytics"

# 多标签查询（AND 逻辑）
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags[Project]=Analytics&tags[Environment]=Production"

# 指定桶查询
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?bucket=my-bucket&tags[Owner]=alice"

# 分页查询
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags[Project]=Analytics&limit=50&offset=0"
```

**POST 请求体**
```json
{
  "bucket": "my-bucket",
  "tags": {
    "Project": "Analytics",
    "Environment": "Production"
  },
  "limit": 100,
  "offset": 0
}
```

**响应**
```json
{
  "total": 42,
  "limit": 100,
  "offset": 0,
  "objects": [
    {
      "id": 123,
      "bucket": "my-bucket",
      "object_key": "data/report-2024.csv",
      "size_bytes": 1048576,
      "content_type": "text/csv",
      "etag": "\"abc123...\"",
      "tags": {
        "Project": "Analytics",
        "Environment": "Production",
        "Owner": "alice"
      },
      "last_modified": "2024-12-08T10:30:00Z",
      "created_at": "2024-12-08T10:30:00Z"
    },
    {
      "id": 124,
      "bucket": "my-bucket",
      "object_key": "logs/app-2024-12-08.log",
      "size_bytes": 524288,
      "tags": {
        "Project": "Analytics",
        "Environment": "Production",
        "Type": "logs"
      },
      "last_modified": "2024-12-08T12:00:00Z"
    }
  ]
}
```

**Python 示例**
```python
import requests

# GET 请求
response = requests.get(
    'http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags',
    params={
        'tags[Project]': 'Analytics',
        'tags[Environment]': 'Production',
        'limit': 50
    }
)
result = response.json()
print(f"Found {result['total']} objects")

# POST 请求
response = requests.post(
    'http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags',
    json={
        'bucket': 'my-bucket',
        'tags': {
            'Project': 'Analytics',
            'Owner': 'alice'
        },
        'limit': 100
    }
)
```

---

### 模糊搜索查询

使用部分匹配搜索标签（支持通配符风格）。

**端点**
```
GET /rustfs/admin/v3/s3-metadata/query-by-tags?tags_fuzzy[Key]=PartialValue
POST /rustfs/admin/v3/s3-metadata/query-by-tags
```

**特性**
- ✅ 支持标签键（Key）模糊匹配
- ✅ 支持标签值（Value）模糊匹配
- ✅ 不区分大小写
- ✅ 使用 PostgreSQL ILIKE 实现

**GET 请求示例**
```bash
# 查找所有 Project 包含 "Anal" 的对象
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags_fuzzy[Project]=Anal"

# 查找 Environment 包含 "prod" 的对象（不区分大小写）
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags_fuzzy[Environment]=prod"

# 混合使用精确匹配和模糊匹配
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags[Owner]=alice&tags_fuzzy[Project]=data"

# 多个模糊匹配条件
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags_fuzzy[Project]=analytics&tags_fuzzy[Environment]=prod"
```

**POST 请求体**
```json
{
  "bucket": "my-bucket",
  "tags_fuzzy": {
    "Project": "anal",
    "Environment": "prod"
  },
  "limit": 50,
  "offset": 0
}
```

**示例场景**

1. **查找所有生产环境对象**
```bash
# "Production", "production", "Prod" 都能匹配
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags_fuzzy[Environment]=prod"
```

2. **查找特定项目的所有变体**
```bash
# 匹配 "DataAnalytics", "data-analytics", "analytics-data" 等
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags_fuzzy[Project]=data"
```

3. **按所有者搜索**
```bash
# 查找所有 "alice" 相关的对象
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags_fuzzy[Owner]=alice"
```

**Python 示例**
```python
import requests

# 模糊搜索
response = requests.get(
    'http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags',
    params={
        'tags_fuzzy[Project]': 'data',
        'tags_fuzzy[Environment]': 'prod'
    }
)

for obj in response.json()['objects']:
    print(f"{obj['object_key']}: {obj['tags']}")
```

---

### 分页查询

处理大量查询结果。

**参数**
- `limit`: 每页返回的对象数量（默认：100，最大：1000）
- `offset`: 跳过的对象数量（用于分页）

**示例**
```bash
# 第1页（前100条）
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags[Project]=Analytics&limit=100&offset=0"

# 第2页（101-200条）
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags[Project]=Analytics&limit=100&offset=100"

# 第3页（201-300条）
curl "http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags?tags[Project]=Analytics&limit=100&offset=200"
```

**Python 分页示例**
```python
def fetch_all_tagged_objects(tags, page_size=100):
    """获取所有匹配标签的对象（自动分页）"""
    offset = 0
    all_objects = []
    
    while True:
        response = requests.get(
            'http://localhost:9000/rustfs/admin/v3/s3-metadata/query-by-tags',
            params={
                **{f'tags[{k}]': v for k, v in tags.items()},
                'limit': page_size,
                'offset': offset
            }
        )
        
        data = response.json()
        all_objects.extend(data['objects'])
        
        # 检查是否还有更多数据
        if len(data['objects']) < page_size or offset + len(data['objects']) >= data['total']:
            break
        
        offset += page_size
    
    return all_objects

# 使用示例
objects = fetch_all_tagged_objects({'Project': 'Analytics', 'Environment': 'Production'})
print(f"Total objects: {len(objects)}")
```

---

## 标签限制

根据 S3 API 规范，RustFS 遵循以下限制：

| 限制项 | 最大值 | 说明 |
|-------|--------|------|
| 每个对象的标签数量 | 10 | S3 兼容限制 |
| 标签键（Key）长度 | 128 字符 | Unicode 字符 |
| 标签值（Value）长度 | 256 字符 | Unicode 字符 |
| 标签键字符集 | `a-z, A-Z, 0-9, +, -, =, ., _, :, /, @` | |
| 标签值字符集 | `a-z, A-Z, 0-9, +, -, =, ., _, :, /, @, 空格` | |

**注意事项**
- ⚠️ 标签键区分大小写（`Project` 和 `project` 是不同的键）
- ⚠️ 标签键在同一对象内必须唯一
- ⚠️ 标签键不能以 `aws:` 开头（保留前缀）
- ✅ 标签值可以为空字符串

---

## 最佳实践

### 1. 标签命名规范

**推荐格式**
```
PascalCase: Project, Environment, CostCenter
kebab-case: project-name, cost-center, owner-name
snake_case: project_name, cost_center, owner_name
```

**标签分类建议**
```bash
# 业务分类
Project=Analytics
Department=Engineering
CostCenter=CC-1234

# 环境标签
Environment=Production
Stage=Beta
Version=v2.1.0

# 管理标签
Owner=alice
Team=DataTeam
CreatedBy=automated-script
ExpirationDate=2024-12-31

# 合规标签
Classification=Confidential
RetentionPolicy=7years
DataType=PII
```

### 2. 标签策略设计

**按生命周期管理**
```python
# 示例：自动过期策略
tags = {
    'RetentionDays': '90',
    'CreatedAt': '2024-12-08',
    'AutoDelete': 'true'
}
```

**成本分配追踪**
```python
tags = {
    'CostCenter': 'CC-1234',
    'Project': 'Analytics',
    'Environment': 'Production',
    'BillingMonth': '2024-12'
}
```

**数据分类和合规**
```python
tags = {
    'DataClassification': 'Confidential',
    'GDPR': 'true',
    'RetentionPolicy': 'P7Y',
    'Owner': 'alice@company.com'
}
```

### 3. 查询优化

**使用索引优化的标签查询**
```sql
-- RustFS 自动创建的 GIN 索引
CREATE INDEX idx_tags_gin ON rustfs.s3_objects USING GIN (tags);
```

**高效查询示例**
```python
# ✅ 好：使用精确匹配
tags = {'Project': 'Analytics', 'Environment': 'Production'}

# ⚠️ 慎用：模糊匹配较慢
tags_fuzzy = {'Project': 'anal'}

# ✅ 好：限制结果集大小
params = {'tags[Project]': 'Analytics', 'limit': 100}
```

### 4. 批量标签操作

**批量设置标签**
```python
import boto3
from concurrent.futures import ThreadPoolExecutor

s3 = boto3.client('s3', endpoint_url='http://localhost:9000')

def tag_object(bucket, key, tags):
    """为单个对象设置标签"""
    s3.put_object_tagging(
        Bucket=bucket,
        Key=key,
        Tagging={'TagSet': [{'Key': k, 'Value': v} for k, v in tags.items()]}
    )
    print(f"Tagged: {key}")

# 批量处理
objects_to_tag = [
    ('my-bucket', 'file1.txt', {'Project': 'A', 'Owner': 'alice'}),
    ('my-bucket', 'file2.txt', {'Project': 'A', 'Owner': 'bob'}),
    ('my-bucket', 'file3.txt', {'Project': 'B', 'Owner': 'charlie'}),
]

with ThreadPoolExecutor(max_workers=10) as executor:
    for bucket, key, tags in objects_to_tag:
        executor.submit(tag_object, bucket, key, tags)
```

**批量查询和导出**
```python
def export_tags_to_csv(bucket, output_file='tags_export.csv'):
    """导出所有对象的标签到 CSV"""
    import csv
    
    offset = 0
    limit = 1000
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Bucket', 'Key', 'Tags', 'Size', 'LastModified'])
        
        while True:
            response = requests.get(
                f'http://localhost:9000/rustfs/admin/v3/s3-metadata/query',
                params={'bucket': bucket, 'limit': limit, 'offset': offset}
            )
            
            data = response.json()
            if not data['objects']:
                break
            
            for obj in data['objects']:
                writer.writerow([
                    obj['bucket'],
                    obj['object_key'],
                    str(obj.get('tags', {})),
                    obj['size_bytes'],
                    obj['last_modified']
                ])
            
            offset += limit
    
    print(f"Exported to {output_file}")

export_tags_to_csv('my-bucket')
```

---

## 示例代码

### 完整的 Python 标签管理类

```python
import boto3
import requests
from typing import Dict, List, Optional

class RustFSTagManager:
    """RustFS 标签管理工具类"""
    
    def __init__(self, endpoint_url: str, access_key: str, secret_key: str):
        self.endpoint_url = endpoint_url
        self.s3 = boto3.client(
            's3',
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key
        )
    
    def set_tags(self, bucket: str, key: str, tags: Dict[str, str]):
        """设置对象标签"""
        tag_set = [{'Key': k, 'Value': v} for k, v in tags.items()]
        self.s3.put_object_tagging(
            Bucket=bucket,
            Key=key,
            Tagging={'TagSet': tag_set}
        )
        print(f"✓ Tags set for {bucket}/{key}")
    
    def get_tags(self, bucket: str, key: str) -> Dict[str, str]:
        """获取对象标签"""
        response = self.s3.get_object_tagging(Bucket=bucket, Key=key)
        return {tag['Key']: tag['Value'] for tag in response['TagSet']}
    
    def delete_tags(self, bucket: str, key: str):
        """删除对象所有标签"""
        self.s3.delete_object_tagging(Bucket=bucket, Key=key)
        print(f"✓ Tags deleted for {bucket}/{key}")
    
    def query_by_tags(
        self,
        tags: Optional[Dict[str, str]] = None,
        tags_fuzzy: Optional[Dict[str, str]] = None,
        bucket: Optional[str] = None,
        limit: int = 100,
        offset: int = 0
    ) -> dict:
        """通过标签查询对象"""
        params = {'limit': limit, 'offset': offset}
        
        if bucket:
            params['bucket'] = bucket
        
        if tags:
            for key, value in tags.items():
                params[f'tags[{key}]'] = value
        
        if tags_fuzzy:
            for key, value in tags_fuzzy.items():
                params[f'tags_fuzzy[{key}]'] = value
        
        response = requests.get(
            f'{self.endpoint_url}/rustfs/admin/v3/s3-metadata/query-by-tags',
            params=params
        )
        response.raise_for_status()
        return response.json()
    
    def batch_set_tags(
        self,
        objects: List[tuple],  # [(bucket, key, tags), ...]
        max_workers: int = 10
    ):
        """批量设置标签"""
        from concurrent.futures import ThreadPoolExecutor
        
        def set_tags_wrapper(item):
            bucket, key, tags = item
            try:
                self.set_tags(bucket, key, tags)
                return True
            except Exception as e:
                print(f"✗ Failed to tag {bucket}/{key}: {e}")
                return False
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            results = list(executor.map(set_tags_wrapper, objects))
        
        success_count = sum(results)
        print(f"\n📊 Batch operation complete: {success_count}/{len(objects)} succeeded")

# 使用示例
if __name__ == '__main__':
    manager = RustFSTagManager(
        endpoint_url='http://localhost:9000',
        access_key='your-access-key',
        secret_key='your-secret-key'
    )
    
    # 1. 设置标签
    manager.set_tags(
        bucket='my-bucket',
        key='data/report.csv',
        tags={'Project': 'Analytics', 'Owner': 'alice', 'Environment': 'Production'}
    )
    
    # 2. 获取标签
    tags = manager.get_tags('my-bucket', 'data/report.csv')
    print(f"Tags: {tags}")
    
    # 3. 精确查询
    results = manager.query_by_tags(
        tags={'Project': 'Analytics', 'Environment': 'Production'},
        limit=50
    )
    print(f"Found {results['total']} objects")
    
    # 4. 模糊查询
    results = manager.query_by_tags(
        tags_fuzzy={'Project': 'anal', 'Owner': 'alice'}
    )
    print(f"Fuzzy search found {results['total']} objects")
    
    # 5. 批量设置标签
    objects_to_tag = [
        ('my-bucket', 'file1.txt', {'Project': 'A', 'Owner': 'alice'}),
        ('my-bucket', 'file2.txt', {'Project': 'A', 'Owner': 'bob'}),
        ('my-bucket', 'file3.txt', {'Project': 'B', 'Owner': 'charlie'}),
    ]
    manager.batch_set_tags(objects_to_tag, max_workers=5)
```

### Shell 脚本示例

```bash
#!/bin/bash
# RustFS 标签管理脚本

ENDPOINT="http://localhost:9000"
BUCKET="my-bucket"

# 设置标签
set_tags() {
    local key=$1
    shift
    local tags="$@"
    
    aws s3api put-object-tagging \
        --bucket "$BUCKET" \
        --key "$key" \
        --tagging "TagSet=[$tags]" \
        --endpoint-url "$ENDPOINT"
    
    echo "✓ Tags set for $key"
}

# 获取标签
get_tags() {
    local key=$1
    
    aws s3api get-object-tagging \
        --bucket "$BUCKET" \
        --key "$key" \
        --endpoint-url "$ENDPOINT"
}

# 查询标签
query_tags() {
    local project=$1
    local environment=$2
    
    curl -s "${ENDPOINT}/rustfs/admin/v3/s3-metadata/query-by-tags?tags[Project]=${project}&tags[Environment]=${environment}" \
        | jq -r '.objects[] | "\(.object_key) - Size: \(.size_bytes) bytes"'
}

# 使用示例
set_tags "report.csv" "{Key=Project,Value=Analytics},{Key=Owner,Value=alice}"
get_tags "report.csv"
query_tags "Analytics" "Production"
```

---

## 错误处理

### 常见错误代码

| 错误代码 | 说明 | 解决方案 |
|---------|------|---------|
| `NoSuchBucket` | 桶不存在 | 检查桶名称是否正确 |
| `NoSuchKey` | 对象不存在 | 确认对象键是否正确 |
| `InvalidTag` | 标签格式无效 | 检查标签键值是否符合规范 |
| `TooManyTags` | 标签数量超过限制 | 每个对象最多10个标签 |
| `AccessDenied` | 权限不足 | 检查 IAM 权限配置 |
| `InternalError` | 服务器内部错误 | 检查服务日志 |

### Python 错误处理示例

```python
from botocore.exceptions import ClientError

try:
    s3.put_object_tagging(
        Bucket='my-bucket',
        Key='my-object.txt',
        Tagging={'TagSet': [{'Key': 'Project', 'Value': 'Analytics'}]}
    )
except ClientError as e:
    error_code = e.response['Error']['Code']
    
    if error_code == 'NoSuchKey':
        print("Error: Object does not exist")
    elif error_code == 'TooManyTags':
        print("Error: Too many tags (maximum 10)")
    elif error_code == 'InvalidTag':
        print("Error: Invalid tag format")
    else:
        print(f"Unexpected error: {e}")
```

---

## 监控和日志

### 查看标签同步日志

```bash
# 查看 RustFS 日志
tail -f /var/log/rustfs/rustfs.log | grep -i "tag\|sync"

# 检查数据库同步状态
curl http://localhost:9000/rustfs/admin/v3/s3-metadata/sync-stats
```

### 同步统计 API

```bash
curl http://localhost:9000/rustfs/admin/v3/s3-metadata/sync-stats
```

**响应示例**
```json
{
  "upsert_success": 15234,
  "upsert_failed": 2,
  "delete_success": 456,
  "delete_failed": 0,
  "update_success": 892,
  "update_failed": 1,
  "queue_depth": 5,
  "last_flush": "2024-12-08T15:30:00Z"
}
```

---

## 性能建议

1. **批量操作**: 使用多线程/并发处理批量标签操作
2. **数据库索引**: RustFS 自动创建 GIN 索引优化标签查询
3. **分页查询**: 大结果集使用分页避免内存溢出
4. **精确匹配优先**: 精确匹配比模糊搜索快
5. **异步同步**: 标签同步是异步的，不影响 API 响应速度

---

## 相关文档

- [RustFS 数据库集成文档](./DATABASE.md)
- [S3 元数据快速参考](./S3_METADATA_QUICK_REFERENCE.md)
- [AWS S3 标签规范](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-tagging.html)

---

## 支持

如有问题，请：
- 查看日志: `/var/log/rustfs/rustfs.log`
- 检查数据库: `SELECT * FROM rustfs.s3_objects WHERE bucket='your-bucket' LIMIT 10;`
- 提交 Issue: https://github.com/jacknion/rustfs/issues

---

**最后更新**: 2024年12月9日  
**版本**: v0.0.5
