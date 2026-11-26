FROM ubuntu:20.04@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential gawk gettext git libncurses5-dev libssl-dev python2 python3 \
    rsync unzip zlib1g-dev file wget curl ca-certificates xz-utils bzip2 \
    patch diffutils perl time qemu-user && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 builder && mkdir /build && chown builder:builder /build
USER builder
WORKDIR /build
