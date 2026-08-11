# BookStack deb 包构建设计

## 目标

为 BookStack 生成可用于 Ubuntu 20.04/22.04 的 `.deb` 安装包，支持 **amd64** 和 **arm64** 两个架构，在 x86_64 机器上交叉编译。

## 安装布局

```
/opt/bookstack/
├── bookstack           # 编译产物 (Go 二进制)
├── conf/               # 配置文件 (conffiles, 升级时保留)
├── views/              # 模板文件
├── static/             # 静态资源
└── dictionary/         # 字典
```

systemd 服务文件: `/lib/systemd/system/bookstack.service`

## systemd 服务

```
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

## DEBIAN 元数据

### control

```
Package: bookstack
Version: <version>
Section: web
Priority: optional
Architecture: arm64 | amd64
Maintainer: TruthHun
Description: BookStack - 文档在线管理系统
```

### postinst

1. 创建 `bookstack` 系统用户（`--system --no-create-home`）
2. `chown -R bookstack:bookstack /opt/bookstack`
3. `systemctl daemon-reload`
4. `systemctl enable bookstack`
5. `systemctl start bookstack`

### postrm

1. `systemctl stop bookstack` / `systemctl disable bookstack`
2. purge 时：`userdel bookstack`，`rm -rf /opt/bookstack`

### conffiles

列出 `conf/` 下的用户可编辑配置文件，升级时不会被覆盖。

## 构建脚本

在现有 `build.sh` 基础上扩展，保留原有逻辑，在末尾追加：

1. **ARM64 编译**: `CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build ...`
2. **AMD64 编译**: 已有（复用）
3. **deb 打包**:
   - 创建临时 `DEBIAN/` 目录
   - 生成 `control`、`postinst`、`postrm`、`conffiles`
   - 复制二进制 + 资源目录到 `opt/bookstack/`
   - 复制 `bookstack.service` 到 `lib/systemd/system/`
   - `dpkg-deb --build` 生成 `.deb`

产物:
```
output/<version>/
├── bookstack_<version>_amd64.deb
├── bookstack_<version>_arm64.deb
├── linux/        # 原有: amd64 裸二进制
├── mac/          # 原有: darwin
└── windows/      # 原有: windows
```

## 约束

- 不修改 Go 源码
- 不引入 npm/composer 等额外依赖（打包脚本只用 bash + dpkg-deb）
- 交叉编译已设置 `CGO_ENABLED=0`，ARM64 无障碍
