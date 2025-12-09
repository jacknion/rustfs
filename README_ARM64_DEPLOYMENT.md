# RustFS ARM64 Linux 编译和部署 - README

## 📚 文档索引

本目录包含 RustFS ARM64 Linux 版本的编译和部署相关文档：

1. **[QUICK_START_ARM64.md](./QUICK_START_ARM64.md)** - 快速开始指南（推荐新手）
   - 一键命令速查
   - 常见问题排查
   - 快速验证测试

2. **[ARM64_DEPLOYMENT_GUIDE.md](./ARM64_DEPLOYMENT_GUIDE.md)** - 完整部署指南
   - 详细的步骤说明
   - 生产环境配置
   - 安全加固指南
   - 监控和备份策略

3. **脚本工具**
   - `build-rustfs.sh` - 编译脚本（项目自带）
   - `deploy-production-arm64.sh` - 生产环境部署脚本
   - `build-and-deploy-arm64.sh` - 一键编译和部署脚本

---

## 🚀 快速开始

### 方式一：一键编译和部署

```bash
# 完整流程：编译 + 上传 + 部署
./build-and-deploy-arm64.sh --server your-server-ip --user ubuntu

# 或使用环境变量
TARGET_SERVER=192.168.1.100 \
TARGET_USER=ubuntu \
./build-and-deploy-arm64.sh
```

### 方式二：分步执行

```bash
# 步骤 1: 编译
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --skip-verification

# 步骤 2: 上传
scp target/aarch64-unknown-linux-gnu/release/rustfs user@server:/tmp/
scp deploy-production-arm64.sh user@server:/tmp/

# 步骤 3: 部署
ssh user@server
cd /tmp
chmod +x deploy-production-arm64.sh
sudo ./deploy-production-arm64.sh
```

---

## 📋 支持的平台

| 平台 | 说明 | 推荐场景 |
|------|------|----------|
| `aarch64-unknown-linux-gnu` | GNU libc 动态链接 | 推荐，兼容性最好 |
| `aarch64-unknown-linux-musl` | musl libc 静态链接 | 无依赖，Alpine Linux |

---

## 🔧 前置要求

### macOS 编译环境

```bash
# 1. 安装 Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. 安装 cargo-zigbuild
cargo install cargo-zigbuild

# 3. 验证安装
cargo zigbuild --version
```

### ARM64 Linux 服务器

- **操作系统**: Ubuntu 20.04+, Debian 11+, CentOS 8+, Rocky Linux 9+
- **架构**: ARM64 (aarch64)
- **内存**: 最低 2GB，推荐 4GB+
- **磁盘**: 根据数据量规划

---

## 🎯 常用命令

### 编译相关

```bash
# GNU 版本 (推荐)
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --skip-verification

# musl 版本 (静态链接)
./build-rustfs.sh --platform aarch64-unknown-linux-musl --skip-verification

# 开发版本 (编译更快)
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --dev --skip-verification

# 查看帮助
./build-rustfs.sh --help
```

### 部署相关

```bash
# 基础部署
sudo ./deploy-production-arm64.sh

# 使用 PostgreSQL
sudo USE_POSTGRES=true \
  POSTGRES_HOST=localhost \
  ./deploy-production-arm64.sh

# 自定义配置
sudo RUSTFS_DATA_DIR=/mnt/storage \
  RUSTFS_ACCESS_KEY=admin \
  ./deploy-production-arm64.sh

# 查看帮助
./deploy-production-arm64.sh --help
```

### 服务管理

```bash
# 查看状态
sudo systemctl status rustfs

# 启动/停止/重启
sudo systemctl start rustfs
sudo systemctl stop rustfs
sudo systemctl restart rustfs

# 查看日志
sudo journalctl -u rustfs -f
sudo tail -f /var/log/rustfs/rustfs.log
```

---

## 🧪 验证部署

### 使用 curl 测试

```bash
# 健康检查
curl http://your-server:9000/health

# 列出 buckets
curl -X GET http://your-server:9000/ \
  -H "Authorization: AWS4-HMAC-SHA256 ..."
```

### 使用 AWS CLI

```bash
# 配置
aws configure --profile rustfs

# 测试
aws s3 ls --endpoint-url http://your-server:9000 --profile rustfs
aws s3 mb s3://test --endpoint-url http://your-server:9000 --profile rustfs
```

### 使用 MinIO Client

```bash
# 配置
mc alias set rustfs http://your-server:9000 ACCESS_KEY SECRET_KEY

# 测试
mc ls rustfs/
mc mb rustfs/test
```

---

## 🐛 故障排查

### 编译失败

```bash
# 检查 zigbuild
cargo zigbuild --version

# 重新安装
cargo install cargo-zigbuild --force

# 清理重试
cargo clean
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --skip-verification
```

### 服务无法启动

```bash
# 查看详细日志
sudo journalctl -u rustfs -n 100 --no-pager

# 检查配置
cat /etc/rustfs/rustfs.env

# 检查权限
ls -la /data/rustfs/
ls -la /usr/local/bin/rustfs

# 手动测试
sudo -u rustfs /usr/local/bin/rustfs --help
```

### 连接问题

```bash
# 检查端口
sudo ss -tlnp | grep -E '9000|9001'

# 检查防火墙
sudo ufw status
sudo firewall-cmd --list-all

# 测试连接
curl http://localhost:9000/health
curl http://server-ip:9000/health
```

---

## 📖 详细文档

### 开发和调试

- [开发环境配置](../CONTRIBUTING.md)
- [代码风格指南](../AGENTS.md)
- [性能测试](../docs/PERFORMANCE_TESTING.md)

### 运维和监控

- [环境变量说明](../docs/ENVIRONMENT_VARIABLES.md)
- [KMS 配置](../docs/kms/configuration.md)
- [数据库配置](../docs/DATABASE.md)

### 安全配置

- [TLS 配置](https://docs.rustfs.com/zh/integration/tls-configured.html)
- [KMS 安全指南](../docs/kms/security.md)
- [IAM 策略](../docs/kms/frontend-api-guide-zh.md)

---

## 💡 最佳实践

1. **编译**
   - 使用 GNU 版本以获得最佳兼容性
   - 添加 `--skip-verification` 避免交叉编译验证失败
   - 定期更新 cargo-zigbuild

2. **部署**
   - 首次部署后立即修改默认密钥
   - 生产环境启用 PostgreSQL
   - 配置 HTTPS/TLS
   - 设置定期备份

3. **运维**
   - 使用 systemd 管理服务
   - 配置日志轮转
   - 设置监控告警
   - 定期更新系统和应用

4. **安全**
   - 限制防火墙端口
   - 使用强密码和密钥
   - 定期审计访问日志
   - 启用 SELinux/AppArmor

---

## 🔗 相关链接

- 官方文档: <https://docs.rustfs.com>
- GitHub 项目: <https://github.com/rustfs/rustfs>
- 问题反馈: <https://github.com/rustfs/rustfs/issues>
- 社区讨论: <https://github.com/rustfs/rustfs/discussions>

---

## 📞 获取帮助

如果遇到问题：

1. 查看 [故障排查](#-故障排查) 部分
2. 阅读 [详细文档](#-详细文档)
3. 搜索 [GitHub Issues](https://github.com/rustfs/rustfs/issues)
4. 在 [Discussions](https://github.com/rustfs/rustfs/discussions) 提问

---

## 📝 更新日志

- **2025-12-08**: 初始版本
  - 添加 ARM64 Linux 编译支持
  - 创建生产环境部署脚本
  - 完善文档和示例

---

**注意**: 此部署方案专为 ARM64 Linux 设计。如需其他架构，请参考项目根目录的 `build-rustfs.sh` 支持的平台列表。
