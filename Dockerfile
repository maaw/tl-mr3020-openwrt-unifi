FROM debian:bookworm
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential clang flex bison g++ gawk gettext git libncurses-dev \
    libssl-dev python3 python3-setuptools python3-dev python3-cryptography \
    rsync swig unzip zlib1g-dev file wget curl ca-certificates xz-utils \
    patch diffutils perl time sudo qemu-user \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 builder && mkdir /build && chown builder:builder /build
USER builder
WORKDIR /build
