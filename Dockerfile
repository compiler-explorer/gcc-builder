FROM ubuntu:22.04
MAINTAINER Matt Godbolt <matt@godbolt.org>

ARG DEBIAN_FRONTEND=noninteractive
RUN apt update -y -q && apt upgrade -y -q && apt upgrade -y -q && apt install -y -q \
    bison \
    bzip2 \
    curl \
    file \
    flex \
    gawk \
    g++ \
    gcc \
    gdc \
    git \
    gnat-11 \
    libc6-dev-i386 \
    libxml2-dev \
    libelf-dev \
    linux-libc-dev \
    make \
    patch \
    subversion \
    texinfo \
    unzip \
    wget \
    xz-utils && \
    cd /tmp && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws*

## The Rust frontend now requires rustc to build.
RUN curl  --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s - -y

# Install CE compilers for use as host when building old GCC versions.
# Modern g++ (11+) is too strict for gcc 5.x-8.x source (C++17 changes,
# stricter template rules). We use CE-built gcc 9.4.0 as host for MAJOR <= 8.
RUN git clone --depth=1 https://github.com/compiler-explorer/infra /opt/compiler-explorer/infra && \
    cd /opt/compiler-explorer/infra && make ce && \
    /opt/compiler-explorer/infra/bin/ce_install install 'compilers/c++/x86/gcc 9.4.0'

# We build from a directory that must be at least searchable with
# EPERM on the CE nodes. Older GCCs erroneously search the $prefix
# used during building, and if they hit a path that gives EPERM they
# bail out. /opt/compiler-explorer/* is a safe spot to build these.
RUN mkdir -p /opt/compiler-explorer/gcc-build
COPY build /opt/compiler-explorer/gcc-build

WORKDIR /opt/compiler-explorer/gcc-build
