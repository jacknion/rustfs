#!/bin/bash
# 在目标 ARM64 服务器上编译 RustFS
# 用途：避免交叉编译的兼容性问题

set -e

SERVER="${1:-}"
PORT="${2:-22}"
USER="${3:-root}"

if [ -z "$SERVER" ]; then
    echo "用法: $0 <服务器地址> [端口] [用户]"
    echo "示例: $0 120.222.149.108 322 root"
    exit 1
fi

echo "=========================================="
echo "在服务器上编译 RustFS"
echo "服务器: $SERVER:$PORT"
echo "用户: $USER"
echo "=========================================="
echo ""

# 1. 上传源代码
echo "📤 上传源代码..."
rsync -avz --progress \
    --exclude 'target/' \
    --exclude '.git/' \
    --exclude 'deploy/' \
    --exclude 'test_standalone/' \
    -e "ssh -p $PORT" \
    ./ "$USER@$SERVER:/tmp/rustfs-build/"

echo ""
echo "✅ 源代码上传完成"
echo ""

# 2. 在服务器上编译
echo "🔨 在服务器上编译..."
ssh -p "$PORT" "$USER@$SERVER" 'bash -s' <<'ENDSSH'
set -e

cd /tmp/rustfs-build

# 安装 Rust (如果未安装)
if ! command -v cargo &> /dev/null; then
    echo "安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# 安装编译依赖
if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y build-essential pkg-config libssl-dev
elif command -v yum &> /dev/null; then
    sudo yum install -y gcc gcc-c++ make pkgconfig openssl-devel
elif command -v dnf &> /dev/null; then
    sudo dnf install -y gcc gcc-c++ make pkgconfig openssl-devel
fi

# 编译
echo "开始编译..."
export JEMALLOC_SYS_WITH_LG_PAGE=16  # 支持 64KB 页面大小
cargo build --release -p rustfs --bins

echo ""
echo "✅ 编译完成"
ls -lh target/release/rustfs

ENDSSH

echo ""
echo "📥 下载编译结果..."
scp -P "$PORT" "$USER@$SERVER:/tmp/rustfs-build/target/release/rustfs" ./rustfs-arm64

echo ""
echo "✅ 全部完成！"
echo "编译好的二进制文件: ./rustfs-arm64"
echo ""
echo "现在可以部署:"
echo "  scp -P $PORT ./rustfs-arm64 $USER@$SERVER:/tmp/rustfs"
echo "  scp -P $PORT deploy-production-arm64.sh $USER@$SERVER:/tmp/"
echo "  ssh -p $PORT $USER@$SERVER 'cd /tmp && chmod +x deploy-production-arm64.sh && ./deploy-production-arm64.sh'"
