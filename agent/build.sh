#!/bin/bash
set -euo pipefail
cd /build/openwrt
out=/build/ucode-unifi
src=${UCODE_AGENT_SRC:-/inputs/ucode-unifi}
mkdir -p "$out"
mbed=$(echo "$PWD"/build_dir/target-mips_24kc_musl/mbedtls-*)
sysroot="$PWD/staging_dir/target-mips_24kc_musl/usr"
cc="$PWD/staging_dir/toolchain-mips_24kc_gcc-14.3.0_musl/bin/mips-openwrt-linux-musl-gcc"
strip="$PWD/staging_dir/toolchain-mips_24kc_gcc-14.3.0_musl/bin/mips-openwrt-linux-musl-strip"
flags=(-Os -fPIC -ffunction-sections -fdata-sections -I"$src" -I"$sysroot/include" -I"$mbed/include" -I"$mbed/library" '-DMBEDTLS_CONFIG_FILE="crypto-config.h"')
for name in aes gcm cipher cipher_wrap platform_util constant_time; do
    "$cc" "${flags[@]}" -c "$mbed/library/$name.c" -o "$out/$name.o"
done
"$cc" "${flags[@]}" -Wall -Wextra -Wno-unused-parameter -c "$src/inform.c" -o "$out/inform.o"
"$cc" -shared -Wl,--gc-sections -Wl,-z,relro,-z,now -o "$out/inform.so" "$out/"*.o "$sysroot/lib/libz.a"
"$strip" --strip-unneeded "$out/inform.so"
ls -l "$out/inform.so"
