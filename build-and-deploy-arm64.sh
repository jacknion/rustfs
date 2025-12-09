#!/bin/bash
# RustFS ARM64 编译和部署 - 完整流程脚本

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    echo -e "${1}${2}${NC}"
}

print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_message $BLUE "🚀 RustFS ARM64 Linux 一键编译和部署"
print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 配置
TARGET_PLATFORM="${TARGET_PLATFORM:-aarch64-unknown-linux-gnu}"
TARGET_SERVER="${TARGET_SERVER:-}"
TARGET_USER="${TARGET_USER:-root}"
TARGET_PORT="${TARGET_PORT:-22}"

# 显示帮助
show_help() {
    cat <<EOF
用法: $0 [选项]

选项:
  --server SERVER     目标服务器地址 (必需)
  --user USER         SSH 用户 (默认: root)
  --port PORT         SSH 端口 (默认: 22)
  --platform TARGET   目标平台 (默认: aarch64-unknown-linux-gnu)
                      可选: aarch64-unknown-linux-musl
  --compile-only      仅编译，不部署
  --deploy-only       仅部署 (跳过编译)
  --help              显示此帮助

环境变量:
  TARGET_SERVER       目标服务器地址
  TARGET_USER         SSH 用户名
  TARGET_PORT         SSH 端口
  TARGET_PLATFORM     目标平台

示例:
  # 完整流程：编译 + 部署
  $0 --server 192.168.1.100 --user ubuntu --port 322

  # 仅编译
  $0 --compile-only

  # 仅部署
  $0 --deploy-only --server 192.168.1.100 --port 322

  # 使用 musl 版本
  $0 --server 192.168.1.100 --platform aarch64-unknown-linux-musl --port 322

EOF
    exit 0
}

# 解析参数
COMPILE_ONLY=false
DEPLOY_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            TARGET_SERVER="$2"
            shift 2
            ;;
        --user)
            TARGET_USER="$2"
            shift 2
            ;;
        --port)
            TARGET_PORT="$2"
            shift 2
            ;;
        --platform)
            TARGET_PLATFORM="$2"
            shift 2
            ;;
        --compile-only)
            COMPILE_ONLY=true
            shift
            ;;
        --deploy-only)
            DEPLOY_ONLY=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            print_message $RED "未知参数: $1"
            show_help
            ;;
    esac
done

# 验证参数
if [ "$DEPLOY_ONLY" = false ] || [ "$COMPILE_ONLY" = false ]; then
    if [ -z "$TARGET_SERVER" ] && [ "$COMPILE_ONLY" = false ]; then
        print_message $RED "错误: 缺少 --server 参数"
        echo ""
        show_help
    fi
fi

# 步骤 1: 编译
compile() {
    print_message $BLUE "步骤 1: 编译 ARM64 Linux 版本"
    print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 检查 zigbuild
    if ! command -v cargo-zigbuild &> /dev/null; then
        print_message $YELLOW "cargo-zigbuild 未安装，正在安装..."
        cargo install cargo-zigbuild
    fi
    
    # 确保 PATH 包含 cargo bin
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # 执行编译
    print_message $YELLOW "开始编译 $TARGET_PLATFORM 版本..."
    ./build-rustfs.sh --platform "$TARGET_PLATFORM" --skip-verification
    
    if [ $? -eq 0 ]; then
        BINARY_PATH="target/${TARGET_PLATFORM}/release/rustfs"
        BINARY_SIZE=$(du -h "$BINARY_PATH" | cut -f1)
        print_message $GREEN "✅ 编译成功！"
        print_message $GREEN "   二进制: $BINARY_PATH"
        print_message $GREEN "   大小: $BINARY_SIZE"
        echo ""
    else
        print_message $RED "❌ 编译失败"
        exit 1
    fi
}

# 步骤 2: 上传文件
upload() {
    print_message $BLUE "步骤 2: 上传文件到服务器"
    print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    BINARY_PATH="target/${TARGET_PLATFORM}/release/rustfs"
    
    if [ ! -f "$BINARY_PATH" ]; then
        print_message $RED "❌ 二进制文件不存在: $BINARY_PATH"
        print_message $YELLOW "   请先运行编译: $0 --compile-only"
        exit 1
    fi
    
    print_message $YELLOW "上传二进制文件..."
    scp -P "${TARGET_PORT}" "$BINARY_PATH" "${TARGET_USER}@${TARGET_SERVER}:/tmp/rustfs"
    
    print_message $YELLOW "上传部署脚本..."
    scp -P "${TARGET_PORT}" deploy-production-arm64.sh "${TARGET_USER}@${TARGET_SERVER}:/tmp/"
    
    print_message $GREEN "✅ 文件上传完成"
    echo ""
}

# 步骤 3: 远程部署
deploy() {
    print_message $BLUE "步骤 3: 在服务器上部署"
    print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    print_message $YELLOW "连接到服务器 ${TARGET_USER}@${TARGET_SERVER}:${TARGET_PORT}..."
    
    ssh -p "${TARGET_PORT}" "${TARGET_USER}@${TARGET_SERVER}" 'bash -s' <<'ENDSSH'
set -e

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}准备部署环境...${NC}"
cd /tmp
chmod +x deploy-production-arm64.sh
chmod +x rustfs

echo -e "${YELLOW}执行部署脚本...${NC}"
./deploy-production-arm64.sh

echo -e "${GREEN}✅ 部署完成${NC}"
echo ""
echo "服务状态:"
systemctl status rustfs --no-pager -l
ENDSSH
    
    if [ $? -eq 0 ]; then
        print_message $GREEN "✅ 部署成功！"
        echo ""
        print_message $YELLOW "访问信息："
        print_message $YELLOW "  S3 API: http://${TARGET_SERVER}:9000"
        print_message $YELLOW "  控制台: http://${TARGET_SERVER}:9001/rustfs/console/"
        echo ""
    else
        print_message $RED "❌ 部署失败"
        exit 1
    fi
}

# 主流程
main() {
    if [ "$DEPLOY_ONLY" = true ]; then
        upload
        deploy
    elif [ "$COMPILE_ONLY" = true ]; then
        compile
    else
        compile
        upload
        deploy
    fi
    
    print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message $GREEN "🎉 所有步骤完成！"
    print_message $BLUE "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "$COMPILE_ONLY" = false ]; then
        print_message $YELLOW "后续操作："
        echo "  1. 查看日志: ssh ${TARGET_USER}@${TARGET_SERVER} 'sudo journalctl -u rustfs -f'"
        echo "  2. 查看状态: ssh ${TARGET_USER}@${TARGET_SERVER} 'sudo systemctl status rustfs'"
        echo "  3. 查看凭证: ssh ${TARGET_USER}@${TARGET_SERVER} 'sudo cat /opt/rustfs/credentials.txt'"
        echo ""
    fi
}

main
