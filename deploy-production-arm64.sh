#!/bin/bash
# RustFS ARM64 Linux 生产环境部署脚本
# 用途：在 ARM64 Linux 服务器上部署和配置 RustFS
# 适用系统：Ubuntu 20.04+, Debian 11+, CentOS/RHEL 8+, Rocky Linux 9+

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 配置变量
RUSTFS_VERSION="${RUSTFS_VERSION:-latest}"
RUSTFS_USER="${RUSTFS_USER:-rustfs}"
RUSTFS_GROUP="${RUSTFS_GROUP:-rustfs}"
RUSTFS_HOME="${RUSTFS_HOME:-/opt/rustfs}"
RUSTFS_DATA_DIR="${RUSTFS_DATA_DIR:-/data/rustfs}"
RUSTFS_LOG_DIR="${RUSTFS_LOG_DIR:-/var/log/rustfs}"
RUSTFS_CONFIG_DIR="${RUSTFS_CONFIG_DIR:-/etc/rustfs}"
RUSTFS_BINARY="${RUSTFS_BINARY:-/usr/local/bin/rustfs}"

# 服务配置
RUSTFS_ACCESS_KEY="${RUSTFS_ACCESS_KEY:-rustfsadmin}"
RUSTFS_SECRET_KEY="${RUSTFS_SECRET_KEY:-$(openssl rand -base64 32 | tr -d /=+ | cut -c -40)}"
RUSTFS_ADDRESS="${RUSTFS_ADDRESS:-0.0.0.0:4000}"
RUSTFS_CONSOLE_ENABLE="${RUSTFS_CONSOLE_ENABLE:-true}"
RUSTFS_CONSOLE_ADDRESS="${RUSTFS_CONSOLE_ADDRESS:-0.0.0.0:4001}"

# PostgreSQL 配置 (可选)
USE_POSTGRES="${USE_POSTGRES:-false}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-rustfs_db}"
POSTGRES_USER="${POSTGRES_USER:-rustfs_user}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-rustfs_password}"

print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_message $BLUE "🚀 RustFS ARM64 Linux 生产环境部署脚本"
print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_message $RED "❌ 请使用 root 用户或 sudo 运行此脚本"
        exit 1
    fi
}

# 检测系统架构
check_architecture() {
    print_message $BLUE "步骤 1/12: 检查系统架构..."
    
    ARCH=$(uname -m)
    if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
        print_message $RED "❌ 此脚本仅适用于 ARM64 架构，当前架构: $ARCH"
        exit 1
    fi
    
    print_message $GREEN "✅ 系统架构: $ARCH"
    echo ""
}

# 检测操作系统
detect_os() {
    print_message $BLUE "步骤 2/12: 检测操作系统..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        print_message $GREEN "✅ 操作系统: $PRETTY_NAME"
    else
        print_message $RED "❌ 无法检测操作系统"
        exit 1
    fi
    echo ""
}

# 安装依赖
install_dependencies() {
    print_message $BLUE "步骤 3/12: 安装系统依赖..."
    
    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get install -y curl wget openssl ca-certificates
            if [ "$USE_POSTGRES" = "true" ]; then
                apt-get install -y postgresql-client
            fi
            ;;
        centos|rhel|rocky)
            yum install -y curl wget openssl ca-certificates
            if [ "$USE_POSTGRES" = "true" ]; then
                yum install -y postgresql
            fi
            ;;
        *)
            print_message $YELLOW "⚠️  未知操作系统，跳过依赖安装"
            ;;
    esac
    
    print_message $GREEN "✅ 依赖安装完成"
    echo ""
}

# 创建系统用户
create_user() {
    print_message $BLUE "步骤 4/12: 创建系统用户..."
    
    if id "$RUSTFS_USER" &>/dev/null; then
        print_message $YELLOW "⚠️  用户 $RUSTFS_USER 已存在"
    else
        useradd -r -s /sbin/nologin -d "$RUSTFS_HOME" -m "$RUSTFS_USER"
        print_message $GREEN "✅ 用户 $RUSTFS_USER 创建成功"
    fi
    echo ""
}

# 创建目录结构
create_directories() {
    print_message $BLUE "步骤 5/12: 创建目录结构..."
    
    # 创建主目录
    mkdir -p "$RUSTFS_HOME"
    mkdir -p "$RUSTFS_CONFIG_DIR"
    mkdir -p "$RUSTFS_LOG_DIR"
    
    # 创建数据卷目录
    mkdir -p "$RUSTFS_DATA_DIR"/{vol1,vol2,vol3,vol4}
    
    # 设置权限
    chown -R "$RUSTFS_USER:$RUSTFS_GROUP" "$RUSTFS_HOME"
    chown -R "$RUSTFS_USER:$RUSTFS_GROUP" "$RUSTFS_DATA_DIR"
    chown -R "$RUSTFS_USER:$RUSTFS_GROUP" "$RUSTFS_LOG_DIR"
    chown -R "$RUSTFS_USER:$RUSTFS_GROUP" "$RUSTFS_CONFIG_DIR"
    
    chmod 755 "$RUSTFS_HOME"
    chmod 755 "$RUSTFS_DATA_DIR"
    chmod 755 "$RUSTFS_LOG_DIR"
    chmod 750 "$RUSTFS_CONFIG_DIR"
    
    print_message $GREEN "✅ 目录结构创建完成"
    echo ""
}

# 下载或复制二进制文件
install_binary() {
    print_message $BLUE "步骤 6/12: 安装 RustFS 二进制文件..."
    
    # 检查当前目录是否有编译好的二进制 (优先使用 GNU 版本)
    if [ -f "/tmp/rustfs" ]; then
        print_message $YELLOW "检测到上传的二进制文件，正在复制..."
        cp /tmp/rustfs "$RUSTFS_BINARY"
    elif [ -f "target/aarch64-unknown-linux-gnu/release/rustfs" ]; then
        print_message $YELLOW "检测到 GNU 版本二进制文件，正在复制..."
        cp target/aarch64-unknown-linux-gnu/release/rustfs "$RUSTFS_BINARY"
    elif [ -f "target/aarch64-unknown-linux-musl/release/rustfs" ]; then
        print_message $YELLOW "检测到 musl 版本二进制文件，正在复制..."
        cp target/aarch64-unknown-linux-musl/release/rustfs "$RUSTFS_BINARY"
    elif [ -f "rustfs" ]; then
        print_message $YELLOW "检测到当前目录的二进制文件，正在复制..."
        cp rustfs "$RUSTFS_BINARY"
    else
        print_message $YELLOW "未找到本地二进制文件"
        print_message $YELLOW "请先运行编译脚本:"
        print_message $YELLOW "  ./build-rustfs.sh --platform aarch64-unknown-linux-gnu"
        print_message $YELLOW "或手动将 rustfs 二进制文件复制到当前目录"
        exit 1
    fi
    
    chmod +x "$RUSTFS_BINARY"
    
    # 检查二进制文件依赖
    print_message $YELLOW "检查二进制文件依赖..."
    if command -v ldd &> /dev/null; then
        ldd "$RUSTFS_BINARY" || true
    fi
    
    # 验证二进制文件
    print_message $YELLOW "验证二进制文件..."
    if "$RUSTFS_BINARY" --version 2>&1 | tee /tmp/rustfs_version.log; then
        VERSION=$("$RUSTFS_BINARY" --version 2>/dev/null || echo "unknown")
        print_message $GREEN "✅ RustFS 安装成功: $VERSION"
    else
        print_message $RED "❌ RustFS 二进制文件验证失败"
        print_message $YELLOW "错误详情:"
        cat /tmp/rustfs_version.log || true
        print_message $YELLOW ""
        print_message $YELLOW "可能的原因:"
        print_message $YELLOW "  1. 缺少运行时依赖库 (glibc, openssl, 等)"
        print_message $YELLOW "  2. 二进制文件损坏"
        print_message $YELLOW "  3. 架构不匹配"
        print_message $YELLOW ""
        print_message $YELLOW "请尝试:"
        print_message $YELLOW "  1. 使用 musl 版本重新编译: --platform aarch64-unknown-linux-musl"
        print_message $YELLOW "  2. 在服务器上安装依赖: apt-get install -y libssl-dev pkg-config"
        exit 1
    fi
    echo ""
}

# 配置 PostgreSQL (可选)
setup_postgres() {
    if [ "$USE_POSTGRES" = "false" ]; then
        print_message $YELLOW "⏭️  跳过 PostgreSQL 配置"
        echo ""
        return
    fi
    
    print_message $BLUE "步骤 7/12: 配置 PostgreSQL..."
    
    # 测试连接
    if PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" &>/dev/null; then
        print_message $GREEN "✅ PostgreSQL 连接成功"
    else
        print_message $YELLOW "⚠️  无法连接到 PostgreSQL，请手动配置数据库"
        print_message $YELLOW "   连接信息: $POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
    fi
    echo ""
}

# 创建配置文件
create_config() {
    print_message $BLUE "步骤 8/12: 创建配置文件..."
    
    # 创建环境配置文件
    cat > "$RUSTFS_CONFIG_DIR/rustfs.env" <<EOF
# RustFS 生产环境配置
# 生成时间: $(date)

# 管理员凭证
RUSTFS_ROOT_USER=$RUSTFS_ACCESS_KEY
RUSTFS_ROOT_PASSWORD=$RUSTFS_SECRET_KEY

# 服务配置
RUSTFS_ADDRESS=$RUSTFS_ADDRESS
RUSTFS_CONSOLE_ENABLE=$RUSTFS_CONSOLE_ENABLE
RUSTFS_CONSOLE_ADDRESS=$RUSTFS_CONSOLE_ADDRESS

# 数据卷配置
RUSTFS_VOLUMES="$RUSTFS_DATA_DIR/vol1 $RUSTFS_DATA_DIR/vol2 $RUSTFS_DATA_DIR/vol3 $RUSTFS_DATA_DIR/vol4"

# 日志配置
RUSTFS_OBS_LOGGER_LEVEL=info
RUSTFS_OBS_LOG_DIRECTORY=$RUSTFS_LOG_DIR
EOF

    if [ "$USE_POSTGRES" = "true" ]; then
        cat >> "$RUSTFS_CONFIG_DIR/rustfs.env" <<EOF

# 数据库配置
RUSTFS_DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
RUSTFS_DATABASE_MAX_CONNECTIONS=20
EOF
    fi
    
    # 设置安全权限
    chmod 640 "$RUSTFS_CONFIG_DIR/rustfs.env"
    chown "$RUSTFS_USER:$RUSTFS_GROUP" "$RUSTFS_CONFIG_DIR/rustfs.env"
    
    print_message $GREEN "✅ 配置文件已创建: $RUSTFS_CONFIG_DIR/rustfs.env"
    echo ""
}

# 创建 systemd 服务
create_systemd_service() {
    print_message $BLUE "步骤 9/12: 创建 systemd 服务..."
    
    # 创建启动脚本
    cat > "$RUSTFS_HOME/start.sh" <<'EOF'
#!/bin/bash
# RustFS 启动脚本
source /etc/rustfs/rustfs.env

# 将空格分隔的volumes转换为命令行参数
exec /usr/local/bin/rustfs \
    --address "${RUSTFS_ADDRESS}" \
    --console-enable \
    --console-address "${RUSTFS_CONSOLE_ADDRESS}" \
    ${RUSTFS_VOLUMES}
EOF
    
    chmod +x "$RUSTFS_HOME/start.sh"
    chown "$RUSTFS_USER:$RUSTFS_GROUP" "$RUSTFS_HOME/start.sh"
    
    cat > /etc/systemd/system/rustfs.service <<EOF
[Unit]
Description=RustFS Object Storage Server
Documentation=https://rustfs.com/docs/
After=network-online.target
Wants=network-online.target
$([ "$USE_POSTGRES" = "true" ] && echo "After=postgresql.service" || echo "")

[Service]
Type=simple
User=$RUSTFS_USER
Group=$RUSTFS_GROUP
WorkingDirectory=$RUSTFS_HOME

# 启动命令
ExecStart=$RUSTFS_HOME/start.sh

# 日志配置
StandardOutput=append:$RUSTFS_LOG_DIR/rustfs.log
StandardError=append:$RUSTFS_LOG_DIR/rustfs-error.log
SyslogIdentifier=rustfs

# 资源限制
LimitNOFILE=1048576
LimitNPROC=32768
TasksMax=infinity

# 重启策略
Restart=always
RestartSec=10s
TimeoutStartSec=30s
TimeoutStopSec=30s

# 安全加固
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictRealtime=true
ReadWritePaths=$RUSTFS_DATA_DIR
ReadWritePaths=$RUSTFS_LOG_DIR

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    print_message $GREEN "✅ systemd 服务已创建"
    echo ""
}

# 配置防火墙
configure_firewall() {
    print_message $BLUE "步骤 10/12: 配置防火墙..."
    
    # 检测防火墙类型
    if command -v ufw &>/dev/null; then
        # Ubuntu/Debian UFW
        ufw allow 4000/tcp comment "RustFS S3 API"
        if [ "$RUSTFS_CONSOLE_ENABLE" = "true" ]; then
            ufw allow 4001/tcp comment "RustFS Console"
        fi
        print_message $GREEN "✅ UFW 防火墙规则已添加"
    elif command -v firewall-cmd &>/dev/null; then
        # CentOS/RHEL firewalld
        firewall-cmd --permanent --add-port=4000/tcp
        if [ "$RUSTFS_CONSOLE_ENABLE" = "true" ]; then
            firewall-cmd --permanent --add-port=4001/tcp
        fi
        firewall-cmd --reload
        print_message $GREEN "✅ firewalld 防火墙规则已添加"
    else
        print_message $YELLOW "⚠️  未检测到防火墙，请手动配置"
    fi
    echo ""
}

# 启动服务
start_service() {
    print_message $BLUE "步骤 11/12: 启动 RustFS 服务..."
    
    # 启用开机自启
    systemctl enable rustfs
    
    # 启动服务
    systemctl start rustfs
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet rustfs; then
        print_message $GREEN "✅ RustFS 服务已启动"
    else
        print_message $RED "❌ RustFS 服务启动失败"
        print_message $YELLOW "查看日志: journalctl -u rustfs -f"
        exit 1
    fi
    echo ""
}

# 显示部署信息
show_deployment_info() {
    print_message $BLUE "步骤 12/12: 部署完成"
    print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_message $GREEN "✅ RustFS 已成功部署到生产环境！"
    echo ""
    print_message $YELLOW "📋 服务信息："
    echo "   服务状态: systemctl status rustfs"
    echo "   查看日志: journalctl -u rustfs -f"
    echo "   或查看: tail -f $RUSTFS_LOG_DIR/rustfs.log"
    echo ""
    print_message $YELLOW "🌐 访问信息："
    
    # 获取服务器 IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo "   S3 API: http://$SERVER_IP:4000"
    if [ "$RUSTFS_CONSOLE_ENABLE" = "true" ]; then
        echo "   管理控制台: http://$SERVER_IP:4001/rustfs/console/"
    fi
    echo ""
    print_message $YELLOW "🔑 管理员凭证："
    echo "   Access Key: $RUSTFS_ACCESS_KEY"
    echo "   Secret Key: $RUSTFS_SECRET_KEY"
    echo ""
    print_message $RED "⚠️  重要提示："
    echo "   1. 请妥善保存管理员凭证"
    echo "   2. 建议修改默认密钥"
    echo "   3. 配置 HTTPS (TLS) 以增强安全性"
    echo "   4. 定期备份数据: $RUSTFS_DATA_DIR"
    echo ""
    print_message $YELLOW "🔧 常用命令："
    echo "   启动服务: systemctl start rustfs"
    echo "   停止服务: systemctl stop rustfs"
    echo "   重启服务: systemctl restart rustfs"
    echo "   查看状态: systemctl status rustfs"
    echo "   查看日志: journalctl -u rustfs -n 100 --no-pager"
    echo ""
    print_message $YELLOW "📂 重要路径："
    echo "   二进制: $RUSTFS_BINARY"
    echo "   配置: $RUSTFS_CONFIG_DIR/rustfs.env"
    echo "   数据: $RUSTFS_DATA_DIR"
    echo "   日志: $RUSTFS_LOG_DIR"
    echo ""
    print_message $YELLOW "📖 下一步："
    echo "   1. 使用 AWS CLI 或 mc 客户端测试连接"
    echo "   2. 创建 bucket 和上传对象"
    echo "   3. 配置备份策略"
    echo "   4. 设置监控和告警"
    echo ""
    
    # 保存凭证到文件
    cat > "$RUSTFS_HOME/credentials.txt" <<EOF
RustFS 凭证信息
==================
部署时间: $(date)
服务器IP: $SERVER_IP

S3 API Endpoint: http://$SERVER_IP:4000
$([ "$RUSTFS_CONSOLE_ENABLE" = "true" ] && echo "Console URL: http://$SERVER_IP:4001/rustfs/console/" || echo "")

Access Key: $RUSTFS_ACCESS_KEY
Secret Key: $RUSTFS_SECRET_KEY

配置文件: $RUSTFS_CONFIG_DIR/rustfs.env
数据目录: $RUSTFS_DATA_DIR
日志目录: $RUSTFS_LOG_DIR
EOF
    
    chown "$RUSTFS_USER:$RUSTFS_GROUP" "$RUSTFS_HOME/credentials.txt"
    chmod 600 "$RUSTFS_HOME/credentials.txt"
    
    print_message $GREEN "凭证已保存到: $RUSTFS_HOME/credentials.txt"
    echo ""
}

# 主流程
main() {
    check_root
    check_architecture
    detect_os
    install_dependencies
    create_user
    create_directories
    install_binary
    setup_postgres
    create_config
    create_systemd_service
    configure_firewall
    start_service
    show_deployment_info
}

# 显示帮助
show_help() {
    cat <<EOF
RustFS ARM64 Linux 生产环境部署脚本

用法: sudo ./deploy-production-arm64.sh [选项]

选项:
  --help              显示此帮助信息
  --with-postgres     启用 PostgreSQL 支持
  --data-dir PATH     指定数据目录 (默认: /data/rustfs)
  --log-dir PATH      指定日志目录 (默认: /var/log/rustfs)

环境变量:
  RUSTFS_ACCESS_KEY         管理员 Access Key (默认: rustfsadmin)
  RUSTFS_SECRET_KEY         管理员 Secret Key (自动生成)
  RUSTFS_ADDRESS            S3 API 监听地址 (默认: 0.0.0.0:4000)
  RUSTFS_CONSOLE_ADDRESS    控制台监听地址 (默认: 0.0.0.0:4001)
  USE_POSTGRES              是否使用 PostgreSQL (默认: false)
  POSTGRES_HOST             PostgreSQL 主机 (默认: localhost)
  POSTGRES_PORT             PostgreSQL 端口 (默认: 5432)
  POSTGRES_DB               数据库名称 (默认: rustfs_db)
  POSTGRES_USER             数据库用户 (默认: rustfs_user)
  POSTGRES_PASSWORD         数据库密码 (默认: rustfs_password)

示例:
  # 基础部署
  sudo ./deploy-production-arm64.sh

  # 使用 PostgreSQL
  sudo USE_POSTGRES=true POSTGRES_HOST=192.168.1.100 ./deploy-production-arm64.sh

  # 自定义路径
  sudo RUSTFS_DATA_DIR=/mnt/storage ./deploy-production-arm64.sh

EOF
}

# 解析参数
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

if [ "$1" = "--with-postgres" ]; then
    USE_POSTGRES=true
fi

# 执行部署
main
