#!/usr/bin/env bash

##########
VERSION=${1}

# These are the values we want to pass for Version and BuildTime
GITHASH=`git rev-parse HEAD 2>/dev/null`

BUILDAT=`date +%FT%T%z`

# Setup the -ldflags option for go build here, interpolate the variable values
LDFLAGS="-s -w -X github.com/TruthHun/BookStack/utils.GitHash=${GITHASH} -X github.com/TruthHun/BookStack/utils.BuildAt=${BUILDAT} -X github.com/TruthHun/BookStack/utils.Version=${VERSION}"

##########

rm -rf output/${VERSION}
mkdir -p output/${VERSION}

CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -v -o output/${VERSION}/mac/BookStack -ldflags "${LDFLAGS}"
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -o output/${VERSION}/linux_amd64/BookStack -ldflags "${LDFLAGS}"
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -v -o output/${VERSION}/windows/BookStack.exe -ldflags "${LDFLAGS}"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -o output/${VERSION}/linux_arm64/BookStack -ldflags "${LDFLAGS}"

if command -v upx &>/dev/null; then
    upx -f -9 output/${VERSION}/mac/BookStack
    upx -f -9 output/${VERSION}/linux_amd64/BookStack
    upx -f -9 output/${VERSION}/windows/BookStack.exe
    upx -f -9 output/${VERSION}/linux_arm64/BookStack
else
    echo "==> upx not found, skipping compression"
fi

cp -r conf output/${VERSION}/mac/
cp -r conf output/${VERSION}/linux_amd64/
cp -r conf output/${VERSION}/windows/
cp -r conf output/${VERSION}/linux_arm64/

cp -r views output/${VERSION}/mac/
cp -r views output/${VERSION}/linux_amd64/
cp -r views output/${VERSION}/windows/
cp -r views output/${VERSION}/linux_arm64/

cp -r dictionary output/${VERSION}/mac/
cp -r dictionary output/${VERSION}/linux_amd64/
cp -r dictionary output/${VERSION}/windows/
cp -r dictionary output/${VERSION}/linux_arm64/

cp -r static output/${VERSION}/mac/
cp -r static output/${VERSION}/linux_amd64/
cp -r static output/${VERSION}/windows/
cp -r static output/${VERSION}/linux_arm64/

########## deb packaging ##########

build_deb() {
    local ARCH=$1
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

build_deb amd64
build_deb arm64