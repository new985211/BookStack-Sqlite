#!/usr/bin/env bash
#
# BookStack 离线环境安装脚本（嵌入式 SQLite，无需外部数据库）
# 适用于: Kylin V10 / Ubuntu 20.04 (amd64 | arm64)
#
# 用法:
#   sudo bash offline-install.sh
#
# 或指定 deb 包与监听端口:
#   sudo bash offline-install.sh --deb-file /path/bookstack_x.y_amd64.deb --port 8181
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------- 默认参数 ----------
INSTALL_DIR="/opt/bookstack"
HTTP_PORT="8181"
DEB_FILE=""

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --deb-file)     DEB_FILE="$2"; shift 2 ;;
        --port)         HTTP_PORT="$2"; shift 2 ;;
        -h|--help)
            echo "用法: sudo bash $0 [选项]"
            echo ""
            echo "选项:"
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
echo "  BookStack 离线安装 (嵌入式 SQLite)"
echo "========================================"
echo "  deb 包:    $DEB_FILE"
echo "  架构:      $DEB_ARCH"
echo "  监听端口:  $HTTP_PORT"
echo "========================================"
echo ""

# ---------- 1. 检查前提条件 ----------
echo "==> [1/5] 检查前提条件..."

if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请使用 sudo 运行此脚本"
    exit 1
fi

echo "  前提条件检查通过"

# ---------- 2. 安装 deb 包 ----------
echo "==> [2/5] 安装 deb 包..."

# 先停止旧服务（如果存在）
systemctl stop bookstack 2>/dev/null || true

dpkg -i "$DEB_FILE"

echo "  deb 包安装完成"

# ---------- 3. 配置 app.conf ----------
echo "==> [3/5] 配置应用..."

CONF_FILE="${INSTALL_DIR}/conf/app.conf"

# 基于 app.conf.example 生成配置（如果 app.conf 不存在）
if [ ! -f "$CONF_FILE" ] || ! grep -q "db_adapter" "$CONF_FILE"; then
    cp "${INSTALL_DIR}/conf/app.conf.example" "$CONF_FILE"
fi

# 嵌入式 SQLite：无需配置数据库连接，仅设置监听端口与运行模式
sed -i "s|^httpport *=.*|httpport = ${HTTP_PORT}|" "$CONF_FILE"
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

# ---------- 4. 初始化数据库（生成 SQLite 文件与表结构） ----------
echo "==> [4/5] 初始化数据库..."

cd "$INSTALL_DIR"
su -s /bin/bash bookstack -c "./bookstack install" 2>&1 || true

echo "  数据库初始化完成（$INSTALL_DIR/data/bookstack.db）"

# ---------- 5. 启动服务 ----------
echo "==> [5/5] 启动服务..."

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
    echo "  默认账号: admin / admin888"
    echo "========================================"
else
    echo ""
    echo "========================================"
    echo "  服务启动失败，请检查日志:"
    echo "  sudo journalctl -u bookstack -n 50"
    echo "========================================"
    exit 1
fi
