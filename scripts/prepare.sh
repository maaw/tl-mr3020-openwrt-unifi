#!/bin/bash
set -euo pipefail
commit=64900e756efa667774214f9c6b17c113222e01f7
cd /build
if [[ ! -d openwrt/.git ]]; then
    git clone --depth 1 --branch v25.12.6 https://github.com/openwrt/openwrt.git openwrt
fi
cd openwrt
[[ $(git rev-parse HEAD) == "$commit" ]] || { echo 'Unexpected OpenWrt revision' >&2; exit 1; }
if git apply --check /project/config/openwrt.patch 2>/dev/null; then
    git apply /project/config/openwrt.patch
else
    git apply --reverse --check /project/config/openwrt.patch
fi
cp /project/config/openwrt.config .config
make defconfig
DOWNLOAD_MIRROR=https://sources.openwrt.org make download -j"${JOBS:-6}"
make -j"${JOBS:-6}"
test -s bin/targets/ath79/tiny/openwrt-ath79-tiny-tplink_tl-mr3020-v1-squashfs-factory.bin
# Source/static-library inputs for the custom module, not runtime image packages.
DOWNLOAD_MIRROR=https://sources.openwrt.org make package/libs/mbedtls/prepare package/libs/zlib/compile
