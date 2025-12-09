# RustFS ARM64 Linux 编译和部署指南

本指南介绍如何在 macOS 上编译 ARM64 Linux 版本的 RustFS，并部署到 ARM64 Linux 服务器。

## 📦 一、编译 ARM64 Linux 版本

### 1.1 前置要求

在 macOS 上编译前，需要安装以下工具：

```bash
# 安装 Rust (如果还没安装)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 安装 cargo-zigbuild (推荐，用于跨平台编译)
cargo install cargo-zigbuild

# 或者安装 Zig (zigbuild 依赖)
brew install zig
```

### 1.2 执行编译

使用项目提供的 `build-rustfs.sh` 脚本编译 ARM64 Linux 版本：

```bash
# 方法 1: 编译 GNU libc 版本 (推荐，兼容性更好)
./build-rustfs.sh --platform aarch64-unknown-linux-gnu

# 方法 2: 编译 musl libc 版本 (静态链接，无外部依赖)
./build-rustfs.sh --platform aarch64-unknown-linux-musl

# 开发版本 (编译更快，但性能较低)
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --dev

# 跳过验证 (交叉编译时需要)
./build-rustfs.sh --platform aarch64-unknown-linux-gnu --skip-verification
```

### 1.3 编译输出

编译完成后，构建产物位于：

```text
target/aarch64-unknown-linux-gnu/release/
├── rustfs              # 二进制文件
└── rustfs.sha256       # SHA256 校验和 (如果启用了签名)
```

或者对于 musl 版本：

```text
target/aarch64-unknown-linux-musl/release/
└── rustfs              # 静态链接的二进制文件
```

---

## 🚀 二、部署到生产环境

### 2.1 上传文件到服务器

```bash
# 上传二进制文件 (GNU 版本)
scp target/aarch64-unknown-linux-gnu/release/rustfs user@your-server:/tmp/

# 或上传 musl 版本
scp target/aarch64-unknown-linux-musl/release/rustfs user@your-server:/tmp/

# 上传部署脚本
scp deploy-production-arm64.sh user@your-server:/tmp/
```

### 2.2 在服务器上执行部署

```bash
# SSH 登录到服务器
ssh user@your-server

# 切换到 root 或使用 sudo
sudo su -

# 进入上传目录
cd /tmp

# 添加执行权限
chmod +x deploy-production-arm64.sh

# 执行部署 (基础部署)
./deploy-production-arm64.sh

# 或使用 PostgreSQL
USE_POSTGRES=true \
POSTGRES_HOST=localhost \
POSTGRES_USER=rustfs_user \
POSTGRES_PASSWORD=your_secure_password \
./deploy-production-arm64.sh
```

### 2.3 部署配置选项

#### 环境变量配置

```bash
# 自定义管理员凭证
RUSTFS_ACCESS_KEY=myadmin \
RUSTFS_SECRET_KEY=MySecureKey123... \
./deploy-production-arm64.sh

# 自定义路径
RUSTFS_DATA_DIR=/mnt/storage/rustfs \
RUSTFS_LOG_DIR=/var/log/rustfs \
./deploy-production-arm64.sh

# 自定义监听地址
RUSTFS_ADDRESS=0.0.0.0:9000 \
RUSTFS_CONSOLE_ADDRESS=0.0.0.0:9001 \
./deploy-production-arm64.sh
```

---

## 🔧 三、部署后管理

### 3.1 服务管理

```bash
# 查看服务状态
systemctl status rustfs

# 启动服务
systemctl start rustfs

# 停止服务
systemctl stop rustfs

# 重启服务
systemctl restart rustfs

# 禁用开机自启
systemctl disable rustfs

# 启用开机自启
systemctl enable rustfs
```

### 3.2 日志查看

```bash
# 实时查看系统日志
journalctl -u rustfs -f

# 查看最近 100 行日志
journalctl -u rustfs -n 100 --no-pager

# 查看应用日志
tail -f /var/log/rustfs/rustfs.log

# 查看错误日志
tail -f /var/log/rustfs/rustfs-error.log
```

### 3.3 配置修改

```bash
# 编辑配置文件
vim /etc/rustfs/rustfs.env

# 修改后重启服务
systemctl restart rustfs
```

---

## 🧪 四、验证部署

### 4.1 使用 AWS CLI 测试

```bash
# 配置 AWS CLI
aws configure --profile rustfs
# AWS Access Key ID: rustfsadmin
# AWS Secret Access Key: (从部署输出中获取)
# Default region: us-east-1

# 测试连接
aws s3 ls --endpoint-url http://your-server:9000 --profile rustfs

# 创建 bucket
aws s3 mb s3://test-bucket --endpoint-url http://your-server:9000 --profile rustfs

# 上传文件
echo "Hello RustFS" > test.txt
aws s3 cp test.txt s3://test-bucket/ --endpoint-url http://your-server:9000 --profile rustfs

# 列出对象
aws s3 ls s3://test-bucket/ --endpoint-url http://your-server:9000 --profile rustfs

# 下载文件
aws s3 cp s3://test-bucket/test.txt downloaded.txt --endpoint-url http://your-server:9000 --profile rustfs
```

### 4.2 使用 MinIO Client (mc)

```bash
# 安装 mc
wget https://dl.min.io/client/mc/release/linux-arm64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# 配置别名
mc alias set rustfs http://your-server:9000 rustfsadmin YOUR_SECRET_KEY

# 测试连接
mc admin info rustfs

# 创建 bucket
mc mb rustfs/test-bucket

# 上传文件
mc cp test.txt rustfs/test-bucket/

# 列出对象
mc ls rustfs/test-bucket/
```

### 4.3 访问管理控制台

打开浏览器访问：

```
http://your-server:9001/rustfs/console/
```

使用部署时输出的凭证登录。

---

## 📋 五、生产环境检查清单

### 5.1 安全加固

- [ ] 修改默认管理员凭证
- [ ] 配置 HTTPS/TLS
- [ ] 设置防火墙规则
- [ ] 限制管理控制台访问 IP
- [ ] 定期更新系统补丁

```bash
# 生成自签名证书 (测试用)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/rustfs/rustfs.key \
  -out /etc/rustfs/rustfs.crt \
  -subj "/CN=your-server.com"

# 修改配置启用 TLS
vim /etc/rustfs/rustfs.env
# 添加:
# RUSTFS_TLS_CERT=/etc/rustfs/rustfs.crt
# RUSTFS_TLS_KEY=/etc/rustfs/rustfs.key
```

### 5.2 数据备份

```bash
# 创建备份脚本
cat > /opt/rustfs/backup.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/backup/rustfs/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# 备份数据
rsync -av /data/rustfs/ "$BACKUP_DIR/data/"

# 备份配置
cp /etc/rustfs/rustfs.env "$BACKUP_DIR/config.env"

# 如果使用 PostgreSQL，备份数据库
# pg_dump -h localhost -U rustfs_user rustfs_db > "$BACKUP_DIR/database.sql"

# 清理 7 天前的备份
find /backup/rustfs -type d -mtime +7 -exec rm -rf {} \;
EOF

chmod +x /opt/rustfs/backup.sh

# 设置定时任务
crontab -e
# 添加: 0 2 * * * /opt/rustfs/backup.sh
```

### 5.3 监控配置

```bash
# 使用 Prometheus 监控 (可选)
# RustFS 默认暴露 metrics 端点: http://localhost:9000/metrics

# 创建健康检查脚本
cat > /opt/rustfs/healthcheck.sh <<'EOF'
#!/bin/bash
if curl -f http://localhost:9000/health > /dev/null 2>&1; then
  echo "RustFS is healthy"
  exit 0
else
  echo "RustFS is unhealthy"
  systemctl restart rustfs
  exit 1
fi
EOF

chmod +x /opt/rustfs/healthcheck.sh

# 添加定时健康检查
crontab -e
# 添加: */5 * * * * /opt/rustfs/healthcheck.sh
```

### 5.4 性能优化

```bash
# 1. 调整系统参数
cat >> /etc/sysctl.conf <<EOF
# RustFS 优化
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 1048576
EOF

sysctl -p

# 2. 调整文件描述符限制
cat >> /etc/security/limits.conf <<EOF
rustfs soft nofile 1048576
rustfs hard nofile 1048576
rustfs soft nproc 32768
rustfs hard nproc 32768
EOF

# 3. 如果使用 SSD，启用 TRIM
systemctl enable fstrim.timer
```

---

## 🐛 六、故障排查

### 6.1 服务无法启动

```bash
# 查看详细错误
journalctl -u rustfs -n 50 --no-pager

# 检查配置文件
cat /etc/rustfs/rustfs.env

# 检查端口占用
ss -tlnp | grep -E '9000|9001'

# 手动测试启动
sudo -u rustfs /usr/local/bin/rustfs --address 0.0.0.0:9000 --volumes /data/rustfs/vol1
```

### 6.2 性能问题

```bash
# 查看系统资源
htop

# 查看磁盘 IO
iostat -x 1

# 查看网络连接
ss -s

# 查看 RustFS 进程
ps aux | grep rustfs
```

### 6.3 数据访问问题

```bash
# 检查数据目录权限
ls -la /data/rustfs/

# 检查磁盘空间
df -h

# 检查 SELinux (如果启用)
getenforce
setenforce 0  # 临时禁用测试
```

---

## 📞 七、获取帮助

- 文档: https://docs.rustfs.com
- GitHub: https://github.com/rustfs/rustfs
- Issues: https://github.com/rustfs/rustfs/issues
- Discussions: https://github.com/rustfs/rustfs/discussions

---

## 📄 八、附录

### 8.1 系统要求

- **操作系统**: Ubuntu 20.04+, Debian 11+, CentOS 8+, Rocky Linux 9+
- **架构**: ARM64 (aarch64)
- **内存**: 最低 2GB，推荐 4GB+
- **磁盘**: 根据数据量规划，推荐使用 SSD
- **网络**: 稳定的网络连接

### 8.2 目录结构

```
/usr/local/bin/rustfs       # 二进制文件
/etc/rustfs/                # 配置目录
  └── rustfs.env            # 环境变量配置
/opt/rustfs/                # 应用主目录
  └── credentials.txt       # 凭证信息 (部署时生成)
/data/rustfs/               # 数据目录
  ├── vol1/                 # 数据卷 1
  ├── vol2/                 # 数据卷 2
  ├── vol3/                 # 数据卷 3
  └── vol4/                 # 数据卷 4
/var/log/rustfs/            # 日志目录
  ├── rustfs.log            # 应用日志
  └── rustfs-error.log      # 错误日志
```

### 8.3 默认端口

- `9000`: S3 API 端口
- `9001`: 管理控制台端口

### 8.4 常用配置示例

完整配置文件 `/etc/rustfs/rustfs.env` 示例:

```bash
# 管理员凭证
RUSTFS_ROOT_USER=rustfsadmin
RUSTFS_ROOT_PASSWORD=your_secure_password

# 服务配置
RUSTFS_ADDRESS=0.0.0.0:9000
RUSTFS_CONSOLE_ENABLE=true
RUSTFS_CONSOLE_ADDRESS=0.0.0.0:9001

# 数据卷
RUSTFS_VOLUMES=/data/rustfs/vol1,/data/rustfs/vol2,/data/rustfs/vol3,/data/rustfs/vol4

# 日志
RUSTFS_OBS_LOGGER_LEVEL=info
RUSTFS_OBS_LOG_DIRECTORY=/var/log/rustfs

# PostgreSQL (可选)
RUSTFS_DATABASE_URL=postgres://rustfs_user:password@localhost:5432/rustfs_db
RUSTFS_DATABASE_MAX_CONNECTIONS=20

# TLS (可选)
# RUSTFS_TLS_CERT=/etc/rustfs/rustfs.crt
# RUSTFS_TLS_KEY=/etc/rustfs/rustfs.key

# KMS (可选)
# RUSTFS_KMS_BACKEND=local
# RUSTFS_KMS_KEY_DIR=/etc/rustfs/kms-keys

# 其他配置
# RUSTFS_SERVER_DOMAINS=s3.example.com,api.example.com
# RUSTFS_OBS_ENDPOINT=http://localhost:4317
```
