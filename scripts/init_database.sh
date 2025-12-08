#!/bin/bash
# RustFS 数据库初始化脚本
# 用途：自动创建 PostgreSQL 数据库、用户和授权

set -e

# 默认配置
DB_NAME="${RUSTFS_DB_NAME:-rustfs_db}"
DB_USER="${RUSTFS_DB_USER:-rustfs_user}"
DB_PASSWORD="${RUSTFS_DB_PASSWORD:-rustfs_password}"
DB_HOST="${RUSTFS_DB_HOST:-localhost}"
DB_PORT="${RUSTFS_DB_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗄️  RustFS 数据库初始化脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "配置信息："
echo "  数据库名称: $DB_NAME"
echo "  数据库用户: $DB_USER"
echo "  数据库主机: $DB_HOST"
echo "  数据库端口: $DB_PORT"
echo ""
echo "⚠️  注意：需要 PostgreSQL 超级用户 ($POSTGRES_USER) 权限"
echo ""
read -p "是否继续？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 已取消"
    exit 1
fi

echo ""
echo "步骤 1/4: 检查 PostgreSQL 连接..."
if ! psql -U "$POSTGRES_USER" -h "$DB_HOST" -p "$DB_PORT" -d postgres -c "SELECT version();" > /dev/null 2>&1; then
    echo "❌ 无法连接到 PostgreSQL，请检查："
    echo "   1. PostgreSQL 是否运行"
    echo "   2. 用户名 $POSTGRES_USER 是否正确"
    echo "   3. 主机 $DB_HOST:$DB_PORT 是否可访问"
    exit 1
fi
echo "✅ PostgreSQL 连接成功"

echo ""
echo "步骤 2/4: 创建数据库和用户..."
psql -U "$POSTGRES_USER" -h "$DB_HOST" -p "$DB_PORT" -d postgres <<EOF
-- 检查数据库是否已存在
SELECT 'Database already exists' 
FROM pg_database 
WHERE datname = '$DB_NAME';

-- 创建数据库（如果不存在）
SELECT 'CREATE DATABASE $DB_NAME'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec

-- 创建用户（如果不存在）
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER') THEN
        EXECUTE 'CREATE USER $DB_USER WITH PASSWORD ''$DB_PASSWORD''';
    ELSE
        EXECUTE 'ALTER USER $DB_USER WITH PASSWORD ''$DB_PASSWORD''';
    END IF;
END
\$\$;

-- 授权
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

echo "✅ 数据库和用户创建成功"

echo ""
echo "步骤 3/4: 配置数据库权限..."
psql -U "$POSTGRES_USER" -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" <<EOF
GRANT ALL ON SCHEMA public TO $DB_USER;
ALTER DATABASE $DB_NAME OWNER TO $DB_USER;

-- 为 PostgreSQL 15+ 配置 public schema 权限
GRANT ALL ON SCHEMA public TO $DB_USER;
GRANT CREATE ON SCHEMA public TO $DB_USER;
EOF

echo "✅ 权限配置完成"

echo ""
echo "步骤 4/4: 验证配置..."
if psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -c "SELECT current_database(), current_user;" > /dev/null 2>&1; then
    echo "✅ 用户 $DB_USER 可以正常连接到数据库 $DB_NAME"
else
    echo "❌ 验证失败：用户无法连接到数据库"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 数据库初始化完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 下一步操作："
echo ""
echo "1. 设置环境变量："
echo "   export RUSTFS_DATABASE_URL=\"postgres://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME\""
echo ""
echo "2. 启动 RustFS（会自动创建 schema 和表）："
echo "   ./rustfs"
echo ""
echo "3. 验证表是否创建："
echo "   psql -U $DB_USER -d $DB_NAME -c '\\dt rustfs.*'"
echo ""
