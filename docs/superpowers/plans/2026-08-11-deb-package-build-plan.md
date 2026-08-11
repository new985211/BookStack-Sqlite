# deb 包构建设施实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 改造 build.sh，支持交叉编译 ARM64 并生成 amd64 + arm64 两个架构的 `.deb` 安装包。

**Architecture:** 扩展已有 build.sh 脚本，新增 ARM64 Go 交叉编译目标，新增 `build_deb()` 函数使用 `dpkg-deb` 构建 deb 包。systemd 服务文件独立存放于 `scripts/` 目录作为模板。

**Tech Stack:** bash, Go 1.13+ (CGO_ENABLED=0), dpkg-deb, systemd

## Global Constraints

- 不修改 Go 源码
- 不引入 npm/composer 等额外依赖
- 交叉编译使用 CGO_ENABLED=0
- 目标系统: Ubuntu 20.04/22.04, amd64 + arm64

---

### Task 1: 创建 systemd 服务文件

**Files:**
- Create: `scripts/bookstack.service`

**Interfaces:**
- Produces: `scripts/bookstack.service` — systemd 单元文件，被 Task 2 的 deb 打包复制到 `lib/systemd/system/`

- [ ] **Step 1: 创建 scripts 目录并写入服务文件**

```bash
mkdir -p scripts
```

写入 `scripts/bookstack.service`:

```ini
[Unit]
Description=BookStack Document Management Service
After=network.target

[Service]
Type=simple
User=bookstack
ExecStart=/opt/bookstack/bookstack
WorkingDirectory=/opt/bookstack
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: 验证文件存在**

```bash
test -f scripts/bookstack.service && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/bookstack.service
git commit -m "feat: add systemd service unit file for deb packaging"
```

---

### Task 2: 改造 build.sh，添加 ARM64 编译和 deb 打包

**Files:**
- Modify: `build.sh` — 在文件末尾追加 ARM64 编译 + deb 打包逻辑
- Create: (通过 build.sh 生成) `output/<version>/bookstack_<version>_amd64.deb`
- Create: (通过 build.sh 生成) `output/<version>/bookstack_<version>_arm64.deb`

**Interfaces:**
- Consumes: `scripts/bookstack.service` (Task 1 产物), 原有 `conf/`, `views/`, `static/`, `dictionary/` 目录
- Produces: deb 包文件

- [ ] **Step 1: 在 build.sh 末尾追加 ARM64 编译目标**

现有 build.sh 第 19-21 行编译三个平台，在第 21 行后追加 ARM64:

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -o output/${VERSION}/linux_arm64/BookStack -ldflags "${LDFLAGS}"
```

- [ ] **Step 2: 追加 deb 打包函数 `build_deb()`**

在 build.sh 末尾追加:

```bash

########## deb packaging ##########

build_deb() {
    local ARCH=$1
    local SRC_DIR="output/${VERSION}/linux_${ARCH}"
    local DEB_TMP="output/${VERSION}/bookstack_${VERSION}_${ARCH}"
    local BINARY_SRC="output/${VERSION}/linux_${ARCH}/BookStack"

    echo "==> Building deb for ${ARCH}..."

    # 1. Clean and create staging dirs
    rm -rf "${DEB_TMP}"
    mkdir -p "${DEB_TMP}/opt/bookstack"
    mkdir -p "${DEB_TMP}/lib/systemd/system"
    mkdir -p "${DEB_TMP}/DEBIAN"

    # 2. Copy binary and resources
    cp "${BINARY_SRC}" "${DEB_TMP}/opt/bookstack/bookstack"
    chmod 755 "${DEB_TMP}/opt/bookstack/bookstack"
    cp -r conf "${DEB_TMP}/opt/bookstack/"
    cp -r views "${DEB_TMP}/opt/bookstack/"
    cp -r static "${DEB_TMP}/opt/bookstack/"
    cp -r dictionary "${DEB_TMP}/opt/bookstack/"
    cp scripts/bookstack.service "${DEB_TMP}/lib/systemd/system/"

    # 3. Write DEBIAN/control
    cat > "${DEB_TMP}/DEBIAN/control" <<EOF
Package: bookstack
Version: ${VERSION}
Section: web
Priority: optional
Architecture: ${ARCH}
Maintainer: TruthHun
Depends: systemd
Description: BookStack - Document online management system
 BookStack is a document management system for creating,
 organizing, and sharing knowledge.
EOF

    # 4. Write DEBIAN/postinst
    cat > "${DEB_TMP}/DEBIAN/postinst" <<'SCRIPT'
#!/bin/bash
set -e

# Create system user if not exists
if ! id -u bookstack &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin bookstack
fi

chown -R bookstack:bookstack /opt/bookstack

systemctl daemon-reload
systemctl enable bookstack
systemctl start bookstack || true

echo "BookStack installed. Visit http://<host>:8181"
SCRIPT
    chmod 755 "${DEB_TMP}/DEBIAN/postinst"

    # 5. Write DEBIAN/postrm
    cat > "${DEB_TMP}/DEBIAN/postrm" <<'SCRIPT'
#!/bin/bash
set -e

systemctl stop bookstack 2>/dev/null || true
systemctl disable bookstack 2>/dev/null || true

if [ "$1" = "purge" ]; then
    userdel bookstack 2>/dev/null || true
    rm -rf /opt/bookstack
fi
SCRIPT
    chmod 755 "${DEB_TMP}/DEBIAN/postrm"

    # 6. Write DEBIAN/conffiles
    find "${DEB_TMP}/opt/bookstack/conf" -type f | sed "s|^${DEB_TMP}||" > "${DEB_TMP}/DEBIAN/conffiles"

    # 7. Build the deb
    dpkg-deb --build "${DEB_TMP}" "output/${VERSION}/"
    rm -rf "${DEB_TMP}"

    echo "==> Done: output/${VERSION}/bookstack_${VERSION}_${ARCH}.deb"
}

# ARM64: copy resources and build deb
cp -r conf output/${VERSION}/linux_arm64/
cp -r views output/${VERSION}/linux_arm64/
cp -r dictionary output/${VERSION}/linux_arm64/
cp -r static output/${VERSION}/linux_arm64/

build_deb amd64
build_deb arm64
```

- [ ] **Step 3: 验证 build.sh 语法正确**

```bash
bash -n build.sh && echo "Syntax OK"
```

- [ ] **Step 4: 验证脚本结构完整性**

```bash
# 确认关键函数和命令都存在
grep -q "linux_arm64" build.sh && echo "ARM64 build target: OK"
grep -q "build_deb" build.sh && echo "build_deb function: OK"
grep -q "scripts/bookstack.service" build.sh && echo "systemd service ref: OK"
grep -q "dpkg-deb" build.sh && echo "dpkg-deb invocation: OK"
```

- [ ] **Step 5: Commit**

```bash
git add build.sh
git commit -m "feat: add ARM64 cross-compile and deb packaging for amd64+arm64"
```
