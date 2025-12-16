#!/bin/bash
# RustFS 服务器部署脚本
# 用法: 先上传二进制文件，然后在服务器上执行此脚本

set -e

echo "🚀 开始部署 RustFS..."

# 1. 停止服务
echo "1. 停止服务..."
systemctl stop rustfs || true

# 2. 备份旧二进制文件
echo "2. 备份旧二进制文件..."
if [ -f /usr/local/bin/rustfs ]; then
    mv /usr/local/bin/rustfs /usr/local/bin/rustfs.bak.$(date +%Y%m%d_%H%M%S)
fi

# 3. 部署新二进制文件
echo "3. 部署新二进制文件..."
if [ -f /usr/local/bin/rustfs.new ]; then
    mv /usr/local/bin/rustfs.new /usr/local/bin/rustfs
    chmod +x /usr/local/bin/rustfs
else
    echo "错误: 未找到 /usr/local/bin/rustfs.new"
    exit 1
fi

# 4. 更新配置文件
echo "4. 更新配置文件..."
cat > /etc/rustfs/rustfs.env << 'ENVEOF'
# RustFS 生产环境配置
# 更新时间: 2025年12月15日

# 管理员凭证
RUSTFS_ROOT_USER=xjjadmin
RUSTFS_ROOT_PASSWORD=s7cTzMZeoXD*tBbWa4D

# 服务配置 - 单端口模式
RUSTFS_ADDRESS=0.0.0.0:8323
RUSTFS_CONSOLE_ENABLE=true
RUSTFS_CONSOLE_ADDRESS=

# 公开访问 URL (反向代理后的地址)
RUSTFS_PUBLIC_URL=https://xmgl.tsxjj.com:59000/rustfs

# 数据卷配置
RUSTFS_VOLUMES="/data/rustfs"

# 日志配置
RUSTFS_OBS_LOGGER_LEVEL=info
RUSTFS_OBS_LOG_DIRECTORY=/var/log/rustfs

# 数据库配置
RUSTFS_DATABASE_URL="postgres://postgres:123.com..@172.16.111.3:5432/rustfs_db?sslmode=disable"
RUSTFS_DATABASE_MAX_CONNECTIONS=20
ENVEOF

# 5. 更新启动脚本
echo "5. 更新启动脚本..."
cat > /opt/rustfs/start.sh << 'SCRIPTEOF'
#!/bin/bash
# RustFS 启动脚本 - 从环境变量读取配置

# 数据库参数
DATABASE_ARG=""
if [ -n "$RUSTFS_DATABASE_URL" ]; then
    DATABASE_ARG="--database-url $RUSTFS_DATABASE_URL"
    if [ -n "$RUSTFS_DATABASE_MAX_CONNECTIONS" ]; then
        DATABASE_ARG="$DATABASE_ARG --database-max-connections $RUSTFS_DATABASE_MAX_CONNECTIONS"
    fi
fi

# PUBLIC_URL 参数
PUBLIC_URL_ARG=""
if [ -n "$RUSTFS_PUBLIC_URL" ]; then
    PUBLIC_URL_ARG="--public-url $RUSTFS_PUBLIC_URL"
fi

# Console 地址参数 (为空时与主端口共用)
CONSOLE_ADDR_ARG=""
if [ -n "$RUSTFS_CONSOLE_ADDRESS" ]; then
    CONSOLE_ADDR_ARG="--console-address $RUSTFS_CONSOLE_ADDRESS"
fi

# 构建并执行命令
exec /usr/local/bin/rustfs \
    --address "${RUSTFS_ADDRESS}" \
    --access-key "${RUSTFS_ROOT_USER}" \
    --secret-key "${RUSTFS_ROOT_PASSWORD}" \
    --console-enable \
    ${CONSOLE_ADDR_ARG} \
    ${PUBLIC_URL_ARG} \
    ${DATABASE_ARG} \
    ${RUSTFS_VOLUMES}
SCRIPTEOF

chmod +x /opt/rustfs/start.sh

# 6. 启动服务
echo "6. 启动服务..."
systemctl start rustfs
sleep 3

# 7. 检查状态
echo "7. 检查服务状态..."
systemctl status rustfs --no-pager

echo ""
echo "✅ 部署完成!"
echo "Console URL: https://www.jjj.com:444/rustfs/console/"
