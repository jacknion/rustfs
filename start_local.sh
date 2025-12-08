#!/bin/bash
set -e

# 数据库配置 (默认使用 init_database.sh 的默认值)
# 请确保已运行 ./scripts/init_database.sh 初始化数据库
export RUSTFS_DATABASE_URL="postgres://rustfs_user:rustfs_password@localhost:5432/rustfs_db"
export RUSTFS_DATABASE_MAX_CONNECTIONS=20

# RustFS 基础配置
export RUSTFS_VOLUMES="./data"
export RUSTFS_ADDRESS="0.0.0.0:9000"
export RUSTFS_CONSOLE_ENABLE=true
export RUSTFS_CONSOLE_ADDRESS="0.0.0.0:9001"

# 日志配置
export RUSTFS_OBS_LOGGER_LEVEL=info
export RUSTFS_OBS_LOG_DIRECTORY="./logs"

echo "🚀 正在启动 RustFS..."
echo "   数据库: $RUSTFS_DATABASE_URL"
echo "   S3 接口: http://localhost:9000"
echo "   控制台: http://localhost:9001"
echo ""

# 确保数据目录存在
mkdir -p data logs

# 启动
cargo run --bin rustfs
