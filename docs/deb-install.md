# BookStack deb 包离线安装指南

适用于 **Kylin V10 SP1 / Ubuntu 20.04** 的 BookStack `.deb` 离线安装包。

支持架构: **amd64** (x86_64) 和 **arm64** (ARM aarch64)。

## 系统要求

| 组件 | 最低要求 |
|------|---------|
| 操作系统 | Kylin V10 SP1 / Ubuntu 20.04 |
| 数据库 | MySQL 5.7+ 或 MariaDB 10.3+ (需预先安装) |
| 内存 | >= 512MB (推荐 2GB) |
| 磁盘 | >= 200MB (不含上传文件存储) |

## 目录结构

```
bookstack_<version>_<arch>.deb
├── /opt/bookstack/
│   ├── bookstack          # 可执行文件
│   ├── conf/              # 配置文件目录
│   │   ├── app.conf       # 主配置 (需按环境修改)
│   │   ├── oss.conf       # 对象存储配置
│   │   └── oauth.conf     # OAuth 登录配置
│   ├── views/             # 页面模板
│   ├── static/            # 静态资源 (CSS/JS/图片)
│   └── dictionary/        # 分词词典
└── /lib/systemd/system/
    └── bookstack.service  # systemd 服务单元
```

## 快速安装 (在线环境)

```bash
# 1. 安装 MySQL (如未安装)
sudo apt update
sudo apt install -y mariadb-server
sudo systemctl start mysql

# 2. 安装 BookStack
sudo dpkg -i bookstack_2.0_amd64.deb   # x86_64
# 或
sudo dpkg -i bookstack_2.0_arm64.deb   # ARM

# 3. 配置数据库连接
sudo vi /opt/bookstack/conf/app.conf

# 4. 重启服务
sudo systemctl restart bookstack

# 5. 访问 http://<服务器IP>:8181
```

## 离线环境安装

### 准备工作

将以下文件拷贝到目标服务器:

| 文件 | 说明 |
|------|------|
| `scripts/offline-install.sh` | 自动安装脚本 |
| `output/<version>/bookstack_<version>_<arch>.deb` | deb 安装包 |

```bash
# 例如:
scp scripts/offline-install.sh user@target:/tmp/
scp output/2.0/bookstack_2.0_amd64.deb user@target:/tmp/
```

### 方式一: 自动安装脚本

```bash
# 基本用法 (MySQL root 无密码)
sudo bash /tmp/offline-install.sh

# 指定 MySQL 连接参数
sudo bash /tmp/offline-install.sh \
    --mysql-user root \
    --mysql-pass mypassword \
    --db-name bookstack \
    --port 8181

# 显式指定 deb 包路径
sudo bash /tmp/offline-install.sh \
    --deb-file /path/to/bookstack_2.0_amd64.deb \
    --mysql-user root \
    --mysql-pass mypassword

# 查看完整参数
bash /tmp/offline-install.sh --help
```

### 方式二: 手动安装

#### 步骤 1: 确认 MySQL 已就绪

```bash
sudo systemctl status mysql    # 确认运行中
sudo mysql -u root -e "SELECT 1;"   # 确认可连接
```

#### 步骤 2: 安装 deb 包

```bash
# 根据机器架构选择:
ARCH=$(uname -m)
# x86_64 → amd64
# aarch64 → arm64

sudo dpkg -i bookstack_2.0_${ARCH}.deb
```

#### 步骤 3: 创建数据库

```bash
sudo mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS bookstack
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
SQL
```

#### 步骤 4: 配置应用

编辑 `/opt/bookstack/conf/app.conf`:

```ini
# 必须修改的项:
db_host=127.0.0.1          # MySQL 地址
db_port=3306               # MySQL 端口
db_username=root           # MySQL 用户名
db_password=your_password  # MySQL 密码
db_database=bookstack      # 数据库名
httpport = 8181            # 监听端口
runmode = prod             # 生产模式

# 其他可选配置:
static_domain=             # 静态资源 CDN 域名
enable_mail=true           # 是否启用邮件
chrome=/usr/bin/chromium-browser  # Chrome 浏览器路径 (PDF导出)
puppeteer = false          # 是否使用 puppeteer
store_type=local           # 存储类型: local / oss
```

#### 步骤 5: 确认依赖配置文件存在

```bash
cd /opt/bookstack/conf
test -f oss.conf   || cp oss.conf.example oss.conf
test -f oauth.conf || cp oauth.conf.example oauth.conf
```

#### 步骤 6: 启动服务

```bash
sudo systemctl daemon-reload
sudo systemctl enable bookstack
sudo systemctl start bookstack
```

#### 步骤 7: 验证

```bash
# 检查服务状态
sudo systemctl status bookstack

# 查看日志
sudo journalctl -u bookstack -f

# 测试 HTTP 端口
curl http://localhost:8181
```

## 常用运维命令

```bash
# 服务管理
sudo systemctl start bookstack      # 启动
sudo systemctl stop bookstack       # 停止
sudo systemctl restart bookstack    # 重启
sudo systemctl status bookstack     # 查看状态

# 查看日志
sudo journalctl -u bookstack -n 100          # 最近 100 行
sudo journalctl -u bookstack -f              # 实时跟踪

# 卸载
sudo systemctl stop bookstack
sudo systemctl disable bookstack
sudo dpkg --purge bookstack
```

## 配置参考

### MySQL 用户创建（推荐使用独立用户）

```sql
CREATE USER 'bookstack'@'127.0.0.1' IDENTIFIED BY 'strong_password';
GRANT ALL PRIVILEGES ON bookstack.* TO 'bookstack'@'127.0.0.1';
FLUSH PRIVILEGES;
```

然后在 `app.conf` 中使用该用户:

```ini
db_username=bookstack
db_password=strong_password
```

### 防火墙放行

```bash
# UFW
sudo ufw allow 8181/tcp

# iptables
sudo iptables -A INPUT -p tcp --dport 8181 -j ACCEPT
```

### 反向代理 (Nginx 示例)

```nginx
server {
    listen 80;
    server_name docs.example.com;

    location / {
        proxy_pass http://127.0.0.1:8181;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## 升级

```bash
# 1. 备份配置
sudo cp -r /opt/bookstack/conf /tmp/bookstack-conf-backup

# 2. 安装新版本
sudo dpkg -i bookstack_3.0_amd64.deb

# 3. 恢复/合并自定义配置 (conf 文件标记为 conffiles, 升级时会提示保留)
# dpkg 会询问是否保留旧配置，选择保留即可

# 4. 重启
sudo systemctl restart bookstack
```

## 故障排查

| 现象 | 可能原因 | 解决 |
|------|---------|------|
| `panic: open /opt/bookstack/conf/oss.conf: no such file` | 缺少配置文件 | `cp /opt/bookstack/conf/oss.conf.example /opt/bookstack/conf/oss.conf` |
| `dial tcp :3306: connect: connection refused` | MySQL 未开启 TCP 监听 | 见下方 "MySQL TCP 配置" |
| `dial tcp 127.0.0.1:3306: connection refused` | MariaDB 以 `--skip-networking` 运行 | `sudo systemctl restart mysql` |
| `Access denied for user` | 数据库凭证错误 | 检查 app.conf 中 db_username/db_password |
| 端口 8181 不通 | 防火墙拦截 | `sudo ufw allow 8181/tcp` |
| 服务不断重启 | 数据库连接失败 | `sudo journalctl -u bookstack -n 50` 查看错误详情 |

### MySQL TCP 配置

BookStack 默认通过 TCP 连接 MySQL（`db_host=127.0.0.1`），如果 MySQL 未开启 TCP:

```bash
# 启用 MySQL TCP 端口
echo '[mysqld]' | sudo tee /etc/mysql/mariadb.conf.d/99-bookstack.cnf
echo 'port = 3306' | sudo tee -a /etc/mysql/mariadb.conf.d/99-bookstack.cnf

# 清理可能的 --skip-networking 残留进程
sudo systemctl stop mysql
sudo pkill -f "skip-networking" 2>/dev/null || true

# 重启 MySQL
sudo systemctl start mysql

# 验证
sudo ss -tlnp | grep 3306
```
