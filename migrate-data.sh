#!/bin/bash
# RustFS 数据迁移脚本
# 从旧实例(Docker, 8323端口)迁移到新实例(systemd, 4000端口)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    echo -e "${1}${2}${NC}"
}

print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_message $BLUE "🔄 RustFS 数据迁移"
print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 源数据目录 (旧Docker实例)
OLD_DATA_DIR="/data/volumes/rustfs/data"
# 目标数据目录 (新systemd实例)
NEW_DATA_DIR="/data/rustfs"

print_message $YELLOW "源数据目录: $OLD_DATA_DIR"
print_message $YELLOW "目标数据目录: $NEW_DATA_DIR"
echo ""

# 检查源目录
if [ ! -d "$OLD_DATA_DIR" ]; then
    print_message $RED "❌ 源数据目录不存在: $OLD_DATA_DIR"
    exit 1
fi

# 检查目标目录
if [ ! -d "$NEW_DATA_DIR" ]; then
    print_message $RED "❌ 目标数据目录不存在: $NEW_DATA_DIR"
    exit 1
fi

# 显示源数据大小
print_message $BLUE "步骤 1/5: 检查源数据大小..."
OLD_SIZE=$(du -sh "$OLD_DATA_DIR" | cut -f1)
print_message $GREEN "源数据大小: $OLD_SIZE"
echo ""

# 停止新RustFS服务
print_message $BLUE "步骤 2/5: 停止新RustFS服务..."
systemctl stop rustfs || true
sleep 2
print_message $GREEN "✅ 服务已停止"
echo ""

# 备份现有数据
print_message $BLUE "步骤 3/5: 备份现有目标数据..."
BACKUP_DIR="/data/rustfs_backup_$(date +%Y%m%d_%H%M%S)"
if [ "$(ls -A $NEW_DATA_DIR)" ]; then
    print_message $YELLOW "创建备份: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -a "$NEW_DATA_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
    print_message $GREEN "✅ 备份完成"
else
    print_message $YELLOW "⏭️  目标目录为空，跳过备份"
fi
echo ""

# 复制数据
print_message $BLUE "步骤 4/5: 复制数据..."
print_message $YELLOW "这可能需要几分钟，请耐心等待..."
echo ""

# 使用rsync复制，保留权限和属性
rsync -av --progress "$OLD_DATA_DIR/" "$NEW_DATA_DIR/" | tail -20

# 修正权限
print_message $YELLOW "修正文件权限..."
chown -R rustfs:rustfs "$NEW_DATA_DIR"
chmod -R 755 "$NEW_DATA_DIR"

print_message $GREEN "✅ 数据复制完成"
echo ""

# 显示目标数据大小
NEW_SIZE=$(du -sh "$NEW_DATA_DIR" | cut -f1)
print_message $GREEN "目标数据大小: $NEW_SIZE"
echo ""

# 启动新RustFS服务
print_message $BLUE "步骤 5/5: 启动新RustFS服务..."
systemctl start rustfs
sleep 3

if systemctl is-active --quiet rustfs; then
    print_message $GREEN "✅ RustFS服务已启动"
else
    print_message $RED "❌ RustFS服务启动失败"
    print_message $YELLOW "请检查日志: journalctl -u rustfs -n 50"
    exit 1
fi
echo ""

# 验证服务
print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_message $GREEN "🎉 数据迁移完成！"
print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_message $YELLOW "📊 迁移摘要:"
echo "  源目录: $OLD_DATA_DIR ($OLD_SIZE)"
echo "  目标目录: $NEW_DATA_DIR ($NEW_SIZE)"
if [ -d "$BACKUP_DIR" ]; then
    echo "  备份位置: $BACKUP_DIR"
fi
echo ""

print_message $YELLOW "🔍 验证步骤:"
echo "  1. 检查服务状态: systemctl status rustfs"
echo "  2. 访问API: curl http://localhost:4000"
echo "  3. 访问控制台: http://172.16.111.2:4001/rustfs/console/"
echo "  4. 列出buckets: aws --endpoint-url http://localhost:4000 s3 ls"
echo ""

print_message $YELLOW "⚠️  注意事项:"
echo "  1. 旧实例仍在运行(Docker, 端口8323)"
echo "  2. 如需停止旧实例: docker stop rustfs"
echo "  3. 备份数据保存在: $BACKUP_DIR"
echo ""
