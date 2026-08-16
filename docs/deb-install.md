# BookStack deb 包离线安装指南

适用于 **Kylin V10 SP1 / Ubuntu 20.04** 的 BookStack `.deb` 离线安装包。

支持架构: **amd64** (x86_64) 和 **arm64** (ARM aarch64)。

数据存储使用**嵌入式 SQLite**，安装后**无需配置任何数据库连接**，`dpkg -i` 即用。

## 系统要求

| 组件 | 最低要求 |
|------|---------|
| 操作系统 | Kylin V10 SP1 / Ubuntu 20.04 |
| 数据库 | 无（内置 SQLite，随程序自动创建） |
| 内存 | >= 512MB (推荐 2GB) |
| 磁盘 | >= 200MB (不含上传文件存储) |

## 目录结构

```
bookstack_<version>_<arch>.deb
├── /opt/bookstack/
│   ├── bookstack          # 可执行文件
│   ├── data/              # SQLite 数据库文件目录 (bookstack.db 运行时生成)
│   ├── conf/              # 配置文件目录
│   │   ├── app.conf       # 主配置 (由 app.conf.example 自动生成)
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
# 1. 安装 BookStack（无需安装数据库）
sudo dpkg -i bookstack_2.0_amd64.deb   # x86_64
# 或
sudo dpkg -i bookstack_2.0_arm64.deb   # ARM

# 2. 初始化数据库（首次安装自动执行，也可手动触发）
sudo -u bookstack /opt/bookstack/bookstack install

# 3. 启动服务（postinst 已自动启动，无需重复操作时跳过）
sudo systemctl restart bookstack

# 4. 访问 http://<服务器IP>:8181
#    默认账号: admin / admin888
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
# 基本用法（无需任何数据库参数）
sudo bash /tmp/offline-install.sh

# 指定监听端口
sudo bash /tmp/offline-install.sh --port 8080

# 显式指定 deb 包路径
sudo bash /tmp/offline-install.sh --deb-file /path/to/bookstack_2.0_amd64.deb

# 查看完整参数
bash /tmp/offline-install.sh --help
```

### 方式二: 手动安装

#### 步骤 1: 安装 deb 包

```bash
# 根据机器架构选择:
ARCH=$(uname -m)
# x86_64 → amd64
# aarch64 → arm64

sudo dpkg -i bookstack_2.0_${ARCH}.deb
```

#### 步骤 2: 初始化数据库

```bash
sudo -u bookstack /opt/bookstack/bookstack install
# 会在 /opt/bookstack/data/bookstack.db 生成 SQLite 数据库与表结构
```

#### 步骤 3: 配置（可选）

编辑 `/opt/bookstack/conf/app.conf`（首次会自动从 `app.conf.example` 生成）:

```ini
# 常用配置:
db_file = data/bookstack.db   # SQLite 数据库文件路径（相对运行目录）
httpport = 8181              # 监听端口
runmode = prod               # 生产模式

# 其他可选配置:
static_domain=               # 静态资源 CDN 域名
enable_mail=true             # 是否启用邮件
chrome=/usr/bin/chromium-browser  # Chrome 浏览器路径 (PDF导出)
puppeteer = false            # 是否使用 puppeteer
store_type=local             # 存储类型: local / oss
```

#### 步骤 4: 确认依赖配置文件存在

```bash
cd /opt/bookstack/conf
test -f oss.conf   || cp oss.conf.example oss.conf
test -f oauth.conf || cp oauth.conf.example oauth.conf
```

#### 步骤 5: 启动服务

```bash
sudo systemctl daemon-reload
sudo systemctl enable bookstack
sudo systemctl start bookstack
```

#### 步骤 6: 验证

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
# 1. 备份数据与配置（SQLite 数据库文件 + conf）
sudo cp -r /opt/bookstack/conf /tmp/bookstack-conf-backup
sudo cp -r /opt/bookstack/data /tmp/bookstack-data-backup

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
| `database is locked` | SQLite 并发写锁 | 通常瞬时，程序已启用 busy_timeout + WAL 自动重试；持续出现时降低并发写 |
| `unable to open database file` | data 目录不可写 | `sudo chown -R bookstack:bookstack /opt/bookstack/data` |
| 端口 8181 不通 | 防火墙拦截 | `sudo ufw allow 8181/tcp` |
| 服务不断重启 | 初始化失败或配置错误 | `sudo journalctl -u bookstack -n 50` 查看错误详情 |
