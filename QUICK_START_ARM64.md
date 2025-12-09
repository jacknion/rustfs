# RustFS ARM64 快速部署指南

## 🚀 一键编译和部署

### 步骤 1: 在 macOS 上编译

```bash
# 安装 zigbuild (如果还没安装)
cargo install cargo-zigbuild

# 编译 ARM64 Linux 版本
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --skip-verification

# 编译完成后，二进制位于:
# target/aarch64-unknown-linux-gnu/release/rustfs
```

### 步骤 2: 部署到 ARM64 Linux 服务器

```bash
# 上传二进制和部署脚本
scp target/aarch64-unknown-linux-gnu/release/rustfs user@your-server:/tmp/
scp deploy-production-arm64.sh user@your-server:/tmp/

# SSH 到服务器
ssh user@your-server

# 执行部署
cd /tmp
chmod +x deploy-production-arm64.sh
sudo ./deploy-production-arm64.sh
```

### 步骤 3: 验证部署

```bash
# 查看服务状态
sudo systemctl status rustfs

# 查看日志
sudo journalctl -u rustfs -f

# 测试连接
curl http://localhost:9000/health
```

---

## 📋 常用命令速查

### 编译相关

```bash
# GNU 版本 (推荐)
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --skip-verification

# musl 版本 (静态链接)
./build-rustfs.sh --platform aarch64-unknown-linux-musl --skip-verification

# 开发版本 (更快)
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --dev --skip-verification

# 查看所有支持的平台
./build-rustfs.sh --help
```

### 部署相关

```bash
# 基础部署
sudo ./deploy-production-arm64.sh

# 使用 PostgreSQL
sudo USE_POSTGRES=true \
  POSTGRES_HOST=localhost \
  POSTGRES_USER=rustfs_user \
  POSTGRES_PASSWORD=your_password \
  ./deploy-production-arm64.sh

# 自定义路径
sudo RUSTFS_DATA_DIR=/mnt/storage \
  RUSTFS_LOG_DIR=/var/log/rustfs \
  ./deploy-production-arm64.sh

# 自定义凭证
sudo RUSTFS_ACCESS_KEY=myadmin \
  RUSTFS_SECRET_KEY=$(openssl rand -base64 40) \
  ./deploy-production-arm64.sh
```

### 服务管理

```bash
# 启动/停止/重启
sudo systemctl start rustfs
sudo systemctl stop rustfs
sudo systemctl restart rustfs

# 查看状态
sudo systemctl status rustfs

# 查看日志
sudo journalctl -u rustfs -f
sudo journalctl -u rustfs -n 100 --no-pager
sudo tail -f /var/log/rustfs/rustfs.log

# 开机自启
sudo systemctl enable rustfs
sudo systemctl disable rustfs
```

### 客户端测试

```bash
# 使用 AWS CLI
aws configure --profile rustfs
aws s3 ls --endpoint-url http://your-server:9000 --profile rustfs
aws s3 mb s3://test --endpoint-url http://your-server:9000 --profile rustfs

# 使用 MinIO Client
mc alias set rustfs http://your-server:9000 ACCESS_KEY SECRET_KEY
mc ls rustfs/
mc mb rustfs/test
```

---

## 🔧 故障排查

### 编译失败

```bash
# 1. 确认 zigbuild 已安装
cargo zigbuild --version

# 2. 如果 zigbuild 未安装
cargo install cargo-zigbuild

# 3. 确认 Rust 工具链
rustup target list --installed
rustup target add aarch64-unknown-linux-gnu

# 4. 清理重新编译
cargo clean
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --skip-verification
```

### 服务无法启动

```bash
# 查看详细错误
sudo journalctl -u rustfs -n 50 --no-pager

# 检查配置
cat /etc/rustfs/rustfs.env

# 检查权限
ls -la /data/rustfs/
ls -la /usr/local/bin/rustfs

# 手动测试
sudo -u rustfs /usr/local/bin/rustfs --address 0.0.0.0:9000 --volumes /data/rustfs/vol1
```

### 连接问题

```bash
# 检查端口监听
sudo ss -tlnp | grep -E '9000|9001'

# 检查防火墙
sudo ufw status
sudo firewall-cmd --list-all

# 测试本地连接
curl -v http://localhost:9000/health

# 测试网络连接
curl -v http://server-ip:9000/health
```

---

## 📚 更多信息

详细文档请参考：
- [完整部署指南](./ARM64_DEPLOYMENT_GUIDE.md)
- [RustFS 官方文档](https://docs.rustfs.com)
- [GitHub 项目](https://github.com/rustfs/rustfs)

---

## 💡 提示

1. **推荐使用 GNU 版本** - 兼容性更好，支持所有发行版
2. **musl 版本优势** - 静态链接，无需系统依赖，但可能性能略低
3. **交叉编译必须加 `--skip-verification`** - macOS 无法运行 Linux 二进制
4. **生产环境建议**：
   - 使用 PostgreSQL 存储元数据
   - 配置 HTTPS/TLS
   - 设置定期备份
   - 配置监控告警
5. **首次部署后记得修改默认密钥！**
