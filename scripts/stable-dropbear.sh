#!/bin/bash
set -euo pipefail
# Build only current SSH userspace with the existing MIPS compiler.
version=2026.94
archive=/inputs/stable-base/dropbear-$version.tar.bz2
printf '%s  %s\n' e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81 "$archive" | sha256sum -c -
export STAGING_DIR=/build/openwrt/staging_dir
toolchain=$STAGING_DIR/toolchain-mips_24kc_gcc-14.3.0_musl
export PATH="$toolchain/bin:$PATH"
build=/build/dropbear-$version
if [ -f "$build/Makefile" ]; then
    make -C "$build" clean
fi
mkdir -p "$build"
tar -xjf "$archive" --strip-components=1 -C "$build"
cd "$build"
export CC=mips-openwrt-linux-musl-gcc
export AR=mips-openwrt-linux-musl-ar
export RANLIB=mips-openwrt-linux-musl-ranlib
export CFLAGS='-Os -pipe -ffunction-sections -fdata-sections -mips32r2 -mtune=24kc -msoft-float'
# A private ELF interpreter also survives Dropbear's /proc/self/exe re-exec.
# A shell wrapper invoking ld-musl directly would break that security feature.
export LDFLAGS='-Wl,--gc-sections -Wl,--dynamic-linker=/usr/lib/mr3020-runtime/lib/ld-musl-mips-sf.so.1 -Wl,-rpath,/usr/lib/mr3020-runtime/lib'
./configure --host=mips-openwrt-linux-musl --disable-zlib --enable-bundled-libtom \
    --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx
make -j6 PROGRAMS='dropbear dropbearkey scp' MULTI=1
mkdir -p /build/dropbear-current
cp dropbearmulti /build/dropbear-current/dropbear
mips-openwrt-linux-musl-strip /build/dropbear-current/dropbear
qemu-mips -cpu 24Kc /build/mr3020-lab/root/lib/libc.so \
    --library-path /build/mr3020-lab/root/lib:/build/mr3020-lab/root/usr/lib \
    /build/dropbear-current/dropbear -V
