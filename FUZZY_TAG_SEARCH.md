# 标签模糊搜索功能

## 功能概述

为 RustFS 元数据查询系统添加了标签模糊搜索功能，支持对对象标签进行部分匹配、不区分大小写的查询。

## 实现细节

### 1. 后端改动

#### 数据模型 (`rustfs/src/storage/database/models.rs`)
- 在 `S3ObjectQuery` 结构体中添加了 `tags_fuzzy` 字段：
```rust
/// Filter by tags using fuzzy search (partial match, case-insensitive)
/// Key-value pairs where values support wildcards (%, _)
pub tags_fuzzy: Option<HashMap<String, String>>,
```

#### 查询逻辑 (`rustfs/src/storage/database/repositories/s3_objects.rs`)
- 实现了基于 PostgreSQL `ILIKE` 的模糊搜索：
```rust
// Apply fuzzy tag filters if specified (partial match, case-insensitive)
if let Some(ref tags_fuzzy) = query.tags_fuzzy {
    if !tags_fuzzy.is_empty() {
        for (key, value) in tags_fuzzy {
            qb.push(" AND EXISTS (");
            qb.push("   SELECT 1 FROM jsonb_each_text(tags) AS t(k, v)");
            qb.push("   WHERE LOWER(t.k) ILIKE ");
            qb.push_bind(format!("%{}%", key.to_lowercase()));
            qb.push("   AND LOWER(t.v) ILIKE ");
            qb.push_bind(format!("%{}%", value.to_lowercase()));
            qb.push(" )");
        }
    }
}
```

#### API 处理器 (`rustfs/src/admin/handlers/s3_metadata.rs`)
- 在 `parse_query_params` 函数中添加了 `tags_fuzzy` 参数解析
- 在 `QueryByTagsRequest` 结构体中添加了 `tags_fuzzy` 字段支持

### 2. 前端改动

#### JavaScript (`rustfs/static/metadata-query/app.js`)
- 添加了 `useFuzzySearch` 响应式变量控制搜索模式
- 修改 `buildQueryUrl` 函数根据模式选择不同的查询参数：
  - 精确匹配：`tags` 参数
  - 模糊匹配：`tags_fuzzy` 参数

#### HTML 界面 (`rustfs/static/metadata-query/index.html`)
- 添加了模糊搜索开关复选框
- 根据模糊搜索状态动态调整输入框提示文本
- 添加了使用提示说明

## 使用方法

### Web 界面使用

1. 访问 `http://your-server:9001/rustfs/metadata-query/`
2. 在"标签过滤"区域勾选"模糊搜索"复选框
3. 输入标签键和值（支持部分匹配）
4. 点击"查询"执行搜索

**示例：**
- 输入键：`env`，值：`prod`
- 可以匹配：
  - `environment=production`
  - `ENV=prod-server`
  - `dev-env=prod-db`
  - `deployment_env=prod123`

### API 使用

#### GET 方式（精确匹配）
```bash
curl 'http://localhost:4000/rustfs/admin/v3/s3/metadata/query?tags={"Project":"analytics"}'
```

#### GET 方式（模糊匹配）
```bash
curl 'http://localhost:4000/rustfs/admin/v3/s3/metadata/query?tags_fuzzy={"proj":"analy"}'
```

#### POST 方式
```bash
curl -X POST http://localhost:4000/rustfs/admin/v3/s3/metadata/query-by-tags \
  -H 'Content-Type: application/json' \
  -d '{
    "tagsFuzzy": {"env": "prod"},
    "bucket": "my-bucket",
    "limit": 100
  }'
```

## 性能考虑

- 模糊搜索使用 `ILIKE` 操作符，相比精确匹配（`@>` 操作符）性能稍低
- 对于大规模数据集，建议：
  1. 结合其他过滤条件（bucket、prefix）缩小搜索范围
  2. 设置合理的 limit 限制返回结果数
  3. 考虑在 tags JSONB 列上创建 GIN 索引（如果尚未创建）

## 数据库索引建议

为提升模糊搜索性能，可以考虑创建 GIN 索引：

```sql
-- 创建 GIN 索引用于 JSONB 模糊搜索
CREATE INDEX IF NOT EXISTS idx_s3_objects_tags_gin 
ON rustfs.s3_objects USING gin(tags jsonb_path_ops);

-- 或使用完整的 GIN 索引（支持更多查询类型）
CREATE INDEX IF NOT EXISTS idx_s3_objects_tags_gin_full 
ON rustfs.s3_objects USING gin(tags);
```

## 测试验证

### 编译测试
```bash
cargo check --package rustfs
cargo test --package rustfs --lib storage::database
```

### 功能测试

1. **精确搜索测试**：
```bash
# 创建带标签的对象
mc tag set new/test-bucket/test.txt "Environment=Production" "Project=Analytics"

# 精确匹配查询（应该找到）
curl 'http://localhost:4000/rustfs/admin/v3/s3/metadata/query?tags={"Environment":"Production"}'

# 精确匹配查询（不应该找到）
curl 'http://localhost:4000/rustfs/admin/v3/s3/metadata/query?tags={"Environment":"Prod"}'
```

2. **模糊搜索测试**：
```bash
# 模糊匹配查询（应该找到）
curl 'http://localhost:4000/rustfs/admin/v3/s3/metadata/query?tags_fuzzy={"env":"prod"}'
curl 'http://localhost:4000/rustfs/admin/v3/s3/metadata/query?tags_fuzzy={"proj":"anal"}'
```

## 部署说明

1. 编译 ARM64 版本：
```bash
JEMALLOC_SYS_WITH_LG_PAGE=16 cargo zigbuild --package rustfs --release --target aarch64-unknown-linux-gnu
```

2. 上传到服务器：
```bash
scp -P 322 target/aarch64-unknown-linux-gnu/release/rustfs root@120.222.149.108:/usr/local/bin/
```

3. 重启服务：
```bash
ssh -p 322 root@120.222.149.108 'systemctl restart rustfs'
```

4. 验证功能：
- 访问控制台：`http://120.222.149.108:9001/rustfs/console/`
- 访问元数据查询：`http://120.222.149.108:9001/rustfs/metadata-query/`

## 向后兼容性

- 原有的精确匹配功能（`tags` 参数）保持不变
- 模糊搜索为可选功能，不影响现有 API 调用
- 前端默认使用精确匹配模式，需手动开启模糊搜索

## 未来改进方向

1. 支持正则表达式搜索
2. 支持多标签组合的复杂查询（AND/OR/NOT）
3. 添加标签值的自动完成建议
4. 性能监控和查询优化建议
