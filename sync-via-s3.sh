#!/bin/bash
# RustFS 数据同步脚本
# 使用 S3 协议从旧实例同步到新实例

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
print_message $BLUE "🔄 RustFS S3协议数据同步"
print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 旧实例配置
OLD_ENDPOINT="http://127.0.0.1:8323"
OLD_ACCESS_KEY="xjjadmin"
OLD_SECRET_KEY="s7cTzMZeoXD*tBbWa4D"

# 新实例配置
NEW_ENDPOINT="http://127.0.0.1:4000"
NEW_ACCESS_KEY="xjjadmin"  # 使用相同的访问密钥
NEW_SECRET_KEY="s7cTzMZeoXD*tBbWa4D"

print_message $YELLOW "源实例: $OLD_ENDPOINT"
print_message $YELLOW "目标实例: $NEW_ENDPOINT"
echo ""

# 检查 awscli 是否安装
if ! command -v aws &> /dev/null; then
    print_message $RED "❌ AWS CLI 未安装"
    print_message $YELLOW "安装命令: pip3 install awscli"
    exit 1
fi

# 配置 AWS CLI 凭证
print_message $BLUE "步骤 1/3: 配置 AWS CLI..."
export AWS_ACCESS_KEY_ID="$OLD_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$OLD_SECRET_KEY"
print_message $GREEN "✅ 完成"
echo ""

# 列出旧实例的所有 buckets
print_message $BLUE "步骤 2/3: 列出源实例 buckets..."
BUCKETS=$(aws --endpoint-url "$OLD_ENDPOINT" s3 ls | awk '{print $3}')

if [ -z "$BUCKETS" ]; then
    print_message $RED "❌ 未找到任何 bucket"
    exit 1
fi

print_message $GREEN "找到以下 buckets:"
echo "$BUCKETS" | while read bucket; do
    echo "  - $bucket"
done
echo ""

# 同步每个 bucket
print_message $BLUE "步骤 3/3: 同步数据..."
echo "$BUCKETS" | while read bucket; do
    print_message $YELLOW "正在同步 bucket: $bucket"
    
    # 在新实例创建 bucket
    aws --endpoint-url "$NEW_ENDPOINT" \
        --aws-access-key-id "$NEW_ACCESS_KEY" \
        --aws-secret-access-key "$NEW_SECRET_KEY" \
        s3 mb "s3://$bucket" 2>/dev/null || echo "  (bucket已存在)"
    
    # 使用 aws s3 sync 同步数据
    aws --endpoint-url "$OLD_ENDPOINT" s3 sync \
        "s3://$bucket" \
        "s3://$bucket" \
        --endpoint-url "$NEW_ENDPOINT" \
        --aws-access-key-id "$NEW_ACCESS_KEY" \
        --aws-secret-access-key "$NEW_SECRET_KEY" \
        --no-progress
    
    if [ $? -eq 0 ]; then
        print_message $GREEN "  ✅ $bucket 同步完成"
    else
        print_message $RED "  ❌ $bucket 同步失败"
    fi
done
echo ""

print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_message $GREEN "🎉 数据同步完成！"
print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_message $YELLOW "验证命令:"
echo "  aws --endpoint-url $NEW_ENDPOINT s3 ls"
echo ""
