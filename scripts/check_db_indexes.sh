#!/usr/bin/env bash
# =====================================================
# RustFS 数据库索引快速检查脚本
# 用途：验证生产环境数据库索引是否齐全
# =====================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
DATABASE_URL="${DATABASE_URL:-postgres://rustfs_user:rustfs_password@localhost:5432/rustfs_db}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "RustFS Database Index Verification"
echo "========================================="
echo ""

# 检查 psql 是否可用
if ! command -v psql &> /dev/null; then
    echo -e "${RED}✗ Error: psql not found${NC}"
    echo "Please install PostgreSQL client tools"
    exit 1
fi

# 检查数据库连接
echo "Checking database connection..."
if ! psql "$DATABASE_URL" -c "SELECT 1" &> /dev/null; then
    echo -e "${RED}✗ Error: Cannot connect to database${NC}"
    echo "Database URL: ${DATABASE_URL}"
    echo "Please check your DATABASE_URL environment variable"
    exit 1
fi
echo -e "${GREEN}✓ Database connection successful${NC}"
echo ""

# 检查表是否存在
echo "Checking if s3_objects table exists..."
TABLE_EXISTS=$(psql "$DATABASE_URL" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 's3_objects');")

if [ "$TABLE_EXISTS" != "t" ]; then
    echo -e "${RED}✗ Error: s3_objects table not found${NC}"
    echo "Please run: psql \$DATABASE_URL -f scripts/s3_metadata_schema.sql"
    exit 1
fi
echo -e "${GREEN}✓ s3_objects table exists${NC}"
echo ""

# 检查高优先级索引
echo "Checking HIGH priority indexes..."
declare -A HIGH_INDEXES=(
    ["idx_bucket_key"]="Fast object lookup"
    ["idx_tags_gin"]="Tag-based queries (CORE FEATURE)"
    ["idx_last_modified"]="Time-range queries"
)

MISSING_HIGH=0
for index in "${!HIGH_INDEXES[@]}"; do
    INDEX_EXISTS=$(psql "$DATABASE_URL" -tAc "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 's3_objects' AND indexname = '$index');")
    
    if [ "$INDEX_EXISTS" = "t" ]; then
        echo -e "${GREEN}✓${NC} $index - ${HIGH_INDEXES[$index]}"
    else
        echo -e "${RED}✗${NC} $index - ${HIGH_INDEXES[$index]} ${RED}MISSING!${NC}"
        ((MISSING_HIGH++))
    fi
done
echo ""

# 检查中优先级索引
echo "Checking MEDIUM priority indexes..."
declare -A MEDIUM_INDEXES=(
    ["idx_user_metadata_gin"]="User metadata queries"
    ["idx_created_at"]="Creation time queries"
    ["idx_bucket_storage_class"]="Storage class filtering"
)

MISSING_MEDIUM=0
for index in "${!MEDIUM_INDEXES[@]}"; do
    INDEX_EXISTS=$(psql "$DATABASE_URL" -tAc "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 's3_objects' AND indexname = '$index');")
    
    if [ "$INDEX_EXISTS" = "t" ]; then
        echo -e "${GREEN}✓${NC} $index"
    else
        echo -e "${YELLOW}!${NC} $index ${YELLOW}missing (recommended)${NC}"
        ((MISSING_MEDIUM++))
    fi
done
echo ""

# 检查唯一约束
echo "Checking unique constraints..."
CONSTRAINT_EXISTS=$(psql "$DATABASE_URL" -tAc "SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_bucket_key' AND conrelid = 's3_objects'::regclass);")

if [ "$CONSTRAINT_EXISTS" = "t" ]; then
    echo -e "${GREEN}✓ unique_bucket_key constraint exists${NC}"
else
    echo -e "${RED}✗ unique_bucket_key constraint missing${NC}"
fi
echo ""

# 获取表统计信息
echo "Table statistics:"
psql "$DATABASE_URL" -c "
SELECT 
    pg_size_pretty(pg_total_relation_size('s3_objects')) AS total_size,
    pg_size_pretty(pg_relation_size('s3_objects')) AS table_size,
    pg_size_pretty(pg_total_relation_size('s3_objects') - pg_relation_size('s3_objects')) AS indexes_size,
    (SELECT COUNT(*) FROM s3_objects) AS row_count;
" || true
echo ""

# 生成汇总报告
echo "========================================="
echo "Summary"
echo "========================================="

if [ $MISSING_HIGH -eq 0 ]; then
    echo -e "${GREEN}✓ All HIGH priority indexes are present${NC}"
else
    echo -e "${RED}✗ $MISSING_HIGH HIGH priority index(es) missing${NC}"
    echo ""
    echo "CRITICAL: Please create missing indexes immediately:"
    echo ""
    echo "  CREATE INDEX IF NOT EXISTS idx_bucket_key ON s3_objects (bucket, object_key);"
    echo "  CREATE INDEX IF NOT EXISTS idx_tags_gin ON s3_objects USING GIN (tags);"
    echo "  CREATE INDEX IF NOT EXISTS idx_last_modified ON s3_objects (last_modified DESC);"
    echo ""
fi

if [ $MISSING_MEDIUM -gt 0 ]; then
    echo -e "${YELLOW}! $MISSING_MEDIUM MEDIUM priority index(es) missing (recommended)${NC}"
fi

echo ""
if [ $MISSING_HIGH -eq 0 ]; then
    echo -e "${GREEN}Status: PASSED ✓${NC}"
    echo "Your database indexes are properly configured."
else
    echo -e "${RED}Status: FAILED ✗${NC}"
    echo "Critical indexes are missing. System performance will be severely degraded."
    exit 1
fi

echo ""
echo "For detailed verification, run:"
echo "  psql \$DATABASE_URL -f $SCRIPT_DIR/verify_indexes.sql"
echo "========================================="
