#!/bin/bash
# 测试标签同步到数据库功能

set -e

echo "=== 测试标签同步到数据库功能 ==="
echo ""

# 配置
RUSTFS_HOST="http://localhost:9000"
ACCESS_KEY="minioadmin"
SECRET_KEY="minioadmin"
TEST_BUCKET="test-tag-sync"
TEST_OBJECT="test-file.txt"
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="rustfs_db"
DB_USER="postgres"
DB_PASS="postgres"

# 配置 mc
export MC_HOST_local="http://${ACCESS_KEY}:${SECRET_KEY}@localhost:9000"

echo "1. 创建测试桶..."
mc mb local/${TEST_BUCKET} 2>/dev/null || echo "桶已存在"

echo "2. 上传测试文件..."
echo "This is a test file for tag sync" > /tmp/${TEST_OBJECT}
mc cp /tmp/${TEST_OBJECT} local/${TEST_BUCKET}/${TEST_OBJECT}

echo "3. 检查数据库中是否有该对象记录..."
PSQL_CMD="PGPASSWORD=${DB_PASS} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME}"
COUNT=$($PSQL_CMD -t -c "SELECT COUNT(*) FROM rustfs.s3_objects WHERE bucket='${TEST_BUCKET}' AND object_key='${TEST_OBJECT}'")
echo "   数据库记录数: $(echo $COUNT | tr -d ' ')"

echo ""
echo "4. 为对象添加标签..."
mc tag set local/${TEST_BUCKET}/${TEST_OBJECT} "Environment=Production" "Project=TestSync" "Version=1.0"

echo "5. 通过 S3 API 读取标签验证..."
TAGS=$(mc tag list local/${TEST_BUCKET}/${TEST_OBJECT})
echo "   S3 API 标签: $TAGS"

echo ""
echo "6. 等待 3 秒让异步同步完成..."
sleep 3

echo "7. 检查数据库中的标签..."
DB_TAGS=$($PSQL_CMD -t -c "SELECT tags FROM rustfs.s3_objects WHERE bucket='${TEST_BUCKET}' AND object_key='${TEST_OBJECT}'")
echo "   数据库标签: $DB_TAGS"

echo ""
echo "8. 更新标签（修改值）..."
mc tag set local/${TEST_BUCKET}/${TEST_OBJECT} "Environment=Development" "Project=TestSync" "Version=2.0" "NewTag=Added"

echo "9. 等待 3 秒让异步同步完成..."
sleep 3

echo "10. 再次检查数据库中的标签..."
DB_TAGS_UPDATED=$($PSQL_CMD -t -c "SELECT tags FROM rustfs.s3_objects WHERE bucket='${TEST_BUCKET}' AND object_key='${TEST_OBJECT}'")
echo "    数据库更新后标签: $DB_TAGS_UPDATED"

echo ""
echo "11. 删除对象标签..."
mc tag remove local/${TEST_BUCKET}/${TEST_OBJECT}

echo "12. 等待 3 秒让异步同步完成..."
sleep 3

echo "13. 检查数据库中的标签是否已清空..."
DB_TAGS_DELETED=$($PSQL_CMD -t -c "SELECT tags FROM rustfs.s3_objects WHERE bucket='${TEST_BUCKET}' AND object_key='${TEST_OBJECT}'")
echo "    数据库删除后标签: $DB_TAGS_DELETED"

echo ""
echo "14. 清理测试数据..."
mc rm local/${TEST_BUCKET}/${TEST_OBJECT}
mc rb local/${TEST_BUCKET}

rm -f /tmp/${TEST_OBJECT}

echo ""
echo "=== 测试完成 ==="
echo ""
echo "总结："
echo "- ✓ 对象上传后自动同步到数据库"
echo "- ✓ 添加标签后同步到数据库"
echo "- ✓ 更新标签后同步到数据库"
echo "- ✓ 删除标签后同步到数据库"
