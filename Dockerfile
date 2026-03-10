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
# SS_Stack was introduced in gcc 8's Ada runtime and bindgen.adb; __gnat_begin_handler_v1
# was introduced in gcc 11.  So:
#   MAJOR <= 7 : gcc-7.5.0 host (bindgen predates SS_Stack; compatible with gcc 5-7)
#   MAJOR 8-10 : gcc-8.5.0 host (bindgen has SS_Stack; no __gnat_begin_handler_v1)
RUN git clone --depth=1 https://github.com/compiler-explorer/infra /opt/compiler-explorer/infra && \
    cd /opt/compiler-explorer/infra && make ce && \
    /opt/compiler-explorer/infra/bin/ce_install install 'compilers/c++/x86/gcc 7.5.0' && \
    /opt/compiler-explorer/infra/bin/ce_install install 'compilers/c++/x86/gcc 8.5.0'

# We build from a directory that must be at least searchable with
# EPERM on the CE nodes. Older GCCs erroneously search the $prefix
# used during building, and if they hit a path that gives EPERM they
# bail out. /opt/compiler-explorer/* is a safe spot to build these.
RUN mkdir -p /opt/compiler-explorer/gcc-build
COPY build /opt/compiler-explorer/gcc-build

WORKDIR /opt/compiler-explorer/gcc-build
