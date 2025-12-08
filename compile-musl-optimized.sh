#!/bin/bash
# 优化的 musl 交叉编译脚本

set -e

# 获取 CPU 核心数
if command -v nproc &> /dev/null; then
    CORES=$(nproc)
elif command -v sysctl &> /dev/null; then
    CORES=$(sysctl -n hw.ncpu)
else
    CORES=8
fi

echo "🔧 系统 CPU 核心数: $CORES"
echo "📦 并行编译任务数: $CORES"

# 清理之前的编译缓存（可选）
# cargo clean --target aarch64-unknown-linux-musl

# 设置环境变量优化编译
export CARGO_BUILD_JOBS=$CORES
export CARGO_INCREMENTAL=1  # 启用增量编译

# 日志文件
LOG_FILE="/tmp/rustfs-musl-build-$(date +%Y%m%d_%H%M%S).log"

echo "📝 日志文件: $LOG_FILE"
echo ""
echo "🚀 开始编译 aarch64-unknown-linux-musl..."
echo "   时间: $(date)"
echo ""

# 使用 cargo zigbuild 进行交叉编译，启用并行编译
cargo zigbuild \
    --release \
    --target aarch64-unknown-linux-musl \
    -j $CORES \
    2>&1 | tee "$LOG_FILE"

# 检查编译结果
if [ -f "target/aarch64-unknown-linux-musl/release/rustfs" ]; then
    echo ""
    echo "✅ 编译成功!"
    echo ""
    ls -lh target/aarch64-unknown-linux-musl/release/rustfs
    echo ""
    file target/aarch64-unknown-linux-musl/release/rustfs
    echo ""
    echo "📊 二进制大小:"
    du -h target/aarch64-unknown-linux-musl/release/rustfs
else
    echo ""
    echo "❌ 编译失败，请检查日志: $LOG_FILE"
    exit 1
fi
