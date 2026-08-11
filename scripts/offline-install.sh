#!/usr/bin/env bash
#
# BookStack 离线环境安装脚本
# 适用于: Kylin V10 / Ubuntu 20.04 (amd64 | arm64)
# 前提条件: MySQL (MariaDB) 已安装并运行
#
# 用法:
#   sudo bash offline-install.sh
#
# 或指定 MySQL 连接参数:
#   sudo bash offline-install.sh --mysql-user root --mysql-pass mypassword
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------- 默认参数 ----------
MYSQL_USER="root"
MYSQL_PASS=""
MYSQL_HOST="127.0.0.1"
MYSQL_PORT="3306"
DB_NAME="bookstack"
DB_CHARSET="utf8mb4"
INSTALL_DIR="/opt/bookstack"
HTTP_PORT="8181"
DEB_FILE=""

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mysql-user)   MYSQL_USER="$2"; shift 2 ;;
        --mysql-pass)   MYSQL_PASS="$2"; shift 2 ;;
        --mysql-host)   MYSQL_HOST="$2"; shift 2 ;;
        --mysql-port)   MYSQL_PORT="$2"; shift 2 ;;
        --db-name)      DB_NAME="$2"; shift 2 ;;
        --deb-file)     DEB_FILE="$2"; shift 2 ;;
        --port)         HTTP_PORT="$2"; shift 2 ;;
        -h|--help)
            echo "用法: sudo bash $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --mysql-user  MySQL 用户名          (默认: root)"
            echo "  --mysql-pass  MySQL 密码            (默认: 空)"
            echo "  --mysql-host  MySQL 主机            (默认: 127.0.0.1)"
            echo "  --mysql-port  MySQL 端口            (默认: 3306)"
            echo "  --db-name     数据库名              (默认: bookstack)"
            echo "  --deb-file    deb 包路径            (自动检测)"
            echo "  --port        BookStack 监听端口    (默认: 8181)"
            echo "  -h, --help   显示帮助"
            exit 0
            ;;
        *)  echo "未知参数: $1"; exit 1 ;;
    esac
done

# ---------- 检测架构和 deb 文件 ----------
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  DEB_ARCH="amd64" ;;
    aarch64) DEB_ARCH="arm64" ;;
    *)       echo "错误: 不支持的架构 $ARCH"; exit 1 ;;
esac

if [ -z "$DEB_FILE" ]; then
    # 自动查找 deb 包
    DEB_FILE=$(ls "$PROJECT_DIR"/output/*/bookstack_*_${DEB_ARCH}.deb 2>/dev/null | sort -V | tail -1)
    if [ -z "$DEB_FILE" ]; then
        echo "错误: 未找到 ${DEB_ARCH} 的 deb 包"
        echo "请先运行 build.sh 编译，或通过 --deb-file 指定路径"
        exit 1
    fi
fi

echo "========================================"
echo "  BookStack 离线安装"
echo "========================================"
echo "  deb 包:    $DEB_FILE"
echo "  架构:      $DEB_ARCH"
echo "  MySQL:     ${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}"
echo "  数据库:    $DB_NAME"
echo "  监听端口:  $HTTP_PORT"
echo "========================================"
echo ""

# ---------- 1. 检查前提条件 ----------
echo "==> [1/6] 检查前提条件..."

if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请使用 sudo 运行此脚本"
    exit 1
fi

if ! systemctl is-active --quiet mysql 2>/dev/null; then
    echo "错误: MySQL 服务未运行，请先启动"
    echo "  sudo systemctl start mysql"
    exit 1
fi

# 构建 mysql 命令 (空密码时不加 -p)
MYSQL_CMD="mysql -u ${MYSQL_USER}"
if [ -n "$MYSQL_PASS" ]; then
    MYSQL_CMD="$MYSQL_CMD -p${MYSQL_PASS}"
fi

if ! $MYSQL_CMD -e "SELECT 1;" &>/dev/null; then
    echo "错误: 无法连接 MySQL，请检查用户名和密码"
    echo "  尝试的命令: $MYSQL_CMD -e 'SELECT 1;'"
    exit 1
fi

# 检查并清理残留的 --skip-networking 进程
if ps aux | grep -q "[m]ysqld.*skip-networking"; then
    echo "==> 检测到 MySQL 以 --skip-networking 模式运行，正在清理..."
    systemctl stop mysql 2>/dev/null || true
    pkill -f "skip-networking" 2>/dev/null || true
    sleep 1
    systemctl start mysql
    sleep 2
fi

# 检查 MySQL TCP 是否在目标端口监听
if ! ss -tlnp 2>/dev/null | grep -q ":${MYSQL_PORT} "; then
    echo "==> MySQL 未监听 TCP ${MYSQL_PORT}，正在启用..."
    printf '[mysqld]\nport = %s\n' "$MYSQL_PORT" > /etc/mysql/mariadb.conf.d/99-bookstack.cnf
    systemctl restart mysql
    sleep 2
    if ! ss -tlnp | grep -q ":${MYSQL_PORT} "; then
        echo "警告: 无法启用 MySQL TCP 端口"
        echo "  BookStack 需要 MySQL 开启 TCP 连接，请手动配置后重试"
        exit 1
    fi
fi

# 重启后重新验证 MySQL 连接
if ! $MYSQL_CMD -e "SELECT 1;" &>/dev/null; then
    echo "错误: MySQL 重启后无法连接，请检查用户名和密码"
    exit 1
fi

echo "  前提条件检查通过"

# ---------- 2. 安装 deb 包 ----------
echo "==> [2/6] 安装 deb 包..."

# 先停止旧服务（如果存在）
systemctl stop bookstack 2>/dev/null || true

dpkg -i "$DEB_FILE"

echo "  deb 包安装完成"

# ---------- 3. 创建数据库 ----------
echo "==> [3/6] 创建数据库..."

$MYSQL_CMD -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET ${DB_CHARSET} DEFAULT COLLATE utf8mb4_general_ci;" 2>&1

echo "  数据库 ${DB_NAME} 已就绪"

# ---------- 4. 配置 app.conf ----------
echo "==> [4/6] 配置应用..."

CONF_FILE="${INSTALL_DIR}/conf/app.conf"

# 基于 app.conf.example 生成配置（如果 app.conf 不存在）
if [ ! -f "$CONF_FILE" ] || ! grep -q "db_adapter" "$CONF_FILE"; then
    cp "${INSTALL_DIR}/conf/app.conf.example" "$CONF_FILE"
fi

# 写入数据库配置
sed -i "s|^db_adapter=.*|db_adapter=mysql|" "$CONF_FILE"
sed -i "s|^db_host=.*|db_host=${MYSQL_HOST}|" "$CONF_FILE"
sed -i "s|^db_port=.*|db_port=${MYSQL_PORT}|" "$CONF_FILE"
sed -i "s|^db_username=.*|db_username=${MYSQL_USER}|" "$CONF_FILE"
sed -i "s|^db_password=.*|db_password=${MYSQL_PASS}|" "$CONF_FILE"
sed -i "s|^db_database=.*|db_database=${DB_NAME}|" "$CONF_FILE"
sed -i "s|^httpport *=.*|httpport = ${HTTP_PORT}|" "$CONF_FILE"

# 确保 runmode = prod
sed -i "s|^runmode *=.*|runmode = prod|" "$CONF_FILE"

# 设置正确的权限
chown bookstack:bookstack "$CONF_FILE"
chmod 640 "$CONF_FILE"

# 确保 oss.conf 和 oauth.conf 存在
for f in oss.conf oauth.conf; do
    if [ ! -f "${INSTALL_DIR}/conf/${f}" ]; then
        cp "${INSTALL_DIR}/conf/${f}.example" "${INSTALL_DIR}/conf/${f}"
        chown bookstack:bookstack "${INSTALL_DIR}/conf/${f}"
    fi
done

echo "  配置文件已更新: $CONF_FILE"

# ---------- 5. 初始化数据库表结构 ----------
echo "==> [5/6] 初始化数据库表..."

# BookStack 使用 Beego ORM 自动建表，首次启动时会自动创建
# 这里先启动一次让程序自动 migrate，然后停止
cd "$INSTALL_DIR"
su -s /bin/bash bookstack -c "./bookstack install" 2>&1 || true

echo "  数据库初始化完成"

# ---------- 6. 启动服务 ----------
echo "==> [6/6] 启动服务..."

systemctl daemon-reload
systemctl enable bookstack
systemctl start bookstack

sleep 3

if systemctl is-active --quiet bookstack; then
    echo ""
    echo "========================================"
    echo "  安装成功！"
    echo "  访问地址: http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}"
    echo "  安装目录: $INSTALL_DIR"
    echo "  配置文件: $CONF_FILE"
    echo "========================================"
else
    echo ""
    echo "========================================"
    echo "  服务启动失败，请检查日志:"
    echo "  sudo journalctl -u bookstack -n 50"
    echo "========================================"
    exit 1
fi
