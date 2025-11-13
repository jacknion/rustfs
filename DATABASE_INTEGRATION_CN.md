# PostgreSQL 数据库集成

## 概述

RustFS 现已支持可选的 PostgreSQL 数据库集成，用于元数据存储和自定义数据操作。数据库连接是**可选的**，仅在配置后才会初始化。

## 功能特性

- ✅ **可选集成**：如果未配置数据库 URL，RustFS 将正常启动而不连接数据库
- ✅ **连接池管理**：自动管理数据库连接池，支持并发访问
- ✅ **健康检查**：提供 API 端点检查数据库连接状态
- ✅ **优雅关闭**：服务器关闭时正确关闭数据库连接池
- ✅ **安全日志**：数据库凭据在日志中自动脱敏
- ✅ **示例 API**：包含示例 handler 展示如何使用数据库

## 配置方式

### 环境变量

```bash
# PostgreSQL 连接 URL
export RUSTFS_DATABASE_URL="postgres://username:password@localhost:5432/rustfs"

# 连接池最大连接数（默认: 10）
export RUSTFS_DATABASE_MAX_CONNECTIONS=10
```

### 命令行参数

```bash
rustfs \
  --database-url "postgres://username:password@localhost:5432/rustfs" \
  --database-max-connections 10 \
  --volumes /data1 /data2
```

## 快速开始

### 方式一：使用 Docker Compose（推荐）

```bash
# 启动 PostgreSQL 和 RustFS
docker-compose -f docker-compose-database.yml up -d

# 查看日志
docker-compose -f docker-compose-database.yml logs -f rustfs

# 停止服务
docker-compose -f docker-compose-database.yml down
```

### 方式二：使用本地 PostgreSQL

```bash
# 1. 启动 PostgreSQL（使用 Docker）
docker run -d \
  --name rustfs-postgres \
  -e POSTGRES_USER=rustfs_user \
  -e POSTGRES_PASSWORD=rustfs_password \
  -e POSTGRES_DB=rustfs_db \
  -p 5432:5432 \
  postgres:16-alpine

# 2. 初始化数据库
psql -U rustfs_user -d rustfs_db -f scripts/init-db.sql

# 3. 启动 RustFS
./scripts/run_with_database.sh
```

### 方式三：不使用数据库（原有方式）

```bash
# 不配置数据库 URL，RustFS 将正常启动
rustfs --volumes /data1 /data2
```

## API 端点

### 数据库健康检查

```bash
curl http://localhost:9000/rustfs/admin/v3/database/health
```

**响应示例（连接成功）：**

```json
{
  "status": "ok",
  "connected": true,
  "message": "Database connection is healthy",
  "timestamp": "2025-11-13T10:00:00Z"
}
```

**响应示例（未配置数据库）：**

```json
{
  "status": "error",
  "connected": false,
  "message": "Database not configured or initialized",
  "timestamp": "2025-11-13T10:00:00Z"
}
```

### 数据库示例查询

```bash
curl http://localhost:9000/rustfs/admin/v3/database/example
```

**响应示例：**

```json
{
  "status": "success",
  "currentTime": "2025-11-13 10:00:00.123456+00",
  "databaseVersion": "PostgreSQL 16.0 on x86_64-pc-linux-gnu",
  "message": "Database query executed successfully"
}
```

## 文件结构

新增的文件和修改：

```
rustfs/
├── Cargo.toml                          # 添加 sqlx 依赖
├── rustfs/
│   ├── src/
│   │   ├── config/mod.rs              # 添加数据库配置参数
│   │   ├── main.rs                    # 集成数据库初始化和关闭
│   │   ├── storage/
│   │   │   ├── mod.rs                 # 导出 database 模块
│   │   │   └── database.rs            # [新增] 数据库连接池管理
│   │   └── admin/
│   │       ├── mod.rs                 # 注册数据库 API 路由
│   │       └── handlers/
│   │           ├── mod.rs             # 导出 database 模块
│   │           └── database.rs        # [新增] 数据库 API handlers
│   └── Cargo.toml                     # 添加 sqlx 和 once_cell 依赖
├── scripts/
│   ├── run_with_database.sh           # [新增] 启动脚本示例
│   └── init-db.sql                    # [新增] 数据库初始化脚本
├── docker-compose-database.yml        # [新增] Docker Compose 配置
└── docs/
    └── DATABASE.md                    # [新增] 详细文档
```

## 数据库配置参数

| 参数 | 环境变量 | 默认值 | 说明 |
|------|----------|--------|------|
| Database URL | `RUSTFS_DATABASE_URL` | None | PostgreSQL 连接字符串 |
| Max Connections | `RUSTFS_DATABASE_MAX_CONNECTIONS` | 10 | 连接池最大连接数 |
| Connect Timeout | - | 30秒 | 连接超时时间 |
| Idle Timeout | - | 600秒 | 空闲连接超时时间 |

## 在自定义 Handler 中使用数据库

### 获取数据库连接池

```rust
use crate::storage::database::get_database_pool;

// 获取全局数据库连接池
let pool = get_database_pool()
    .ok_or_else(|| s3_error!(InternalError, "Database not initialized"))?;
```

### 执行查询示例

```rust
// 简单查询
let result: (String,) = sqlx::query_as("SELECT NOW()::TEXT")
    .fetch_one(pool)
    .await
    .map_err(|e| s3_error!(InternalError, "Query failed: {}", e))?;

// 参数化查询
let bucket_name = "my-bucket";
let result = sqlx::query!(
    "SELECT * FROM buckets WHERE name = $1",
    bucket_name
)
.fetch_one(pool)
.await?;
```

## 数据库架构

数据库初始化脚本（`scripts/init-db.sql`）创建了以下表：

1. **custom_metadata** - 自定义元数据存储
2. **audit_logs** - 审计日志（示例）
3. **bucket_statistics** - Bucket 统计信息（示例）

您可以根据需要修改或扩展架构。

## 测试

### 运行编译检查

```bash
cargo check --all-targets
```

### 测试数据库连接

```bash
# 检查数据库健康状态
curl http://localhost:9000/rustfs/admin/v3/database/health

# 运行示例查询
curl http://localhost:9000/rustfs/admin/v3/database/example
```

## 故障排除

### 连接超时

如果遇到连接超时，可以检查：

1. PostgreSQL 是否正在运行
2. 连接 URL 是否正确
3. 网络连接是否正常
4. PostgreSQL 配置是否允许远程连接

### 连接数过多

如果提示连接数过多，可以：

```bash
# 减少最大连接数
export RUSTFS_DATABASE_MAX_CONNECTIONS=5
```

### SSL/TLS 连接

如果需要 SSL 连接：

```bash
export RUSTFS_DATABASE_URL="postgres://user:pass@host/db?sslmode=require"
```

## 性能建议

1. **连接池大小**：根据工作负载调整（默认: 10）
2. **连接复用**：连接池会自动复用连接
3. **查询优化**：使用索引并优化查询
4. **监控**：定期检查数据库健康端点

## 安全建议

1. **凭据管理**：安全存储数据库凭据，使用环境变量或密钥管理服务
2. **网络安全**：对数据库连接使用 SSL/TLS
3. **访问控制**：限制数据库用户权限
4. **日志安全**：数据库 URL 在日志中自动脱敏

## 更多信息

详细文档请参阅：[docs/DATABASE.md](docs/DATABASE.md)

## 兼容性

- PostgreSQL 12+
- Rust 1.85+
- SQLx 0.8+
