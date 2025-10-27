#!/bin/bash

set -ex

ROOT=$(pwd)
VERSION=$1
if [[ "$VERSION" != "1.27" ]]; then
    echo "Wrong version"
    exit 1
fi

OUTPUT=/root/g++-${VERSION}.tar.xz
S3OUTPUT=""
if echo $2 | grep s3://; then
    S3OUTPUT=$2
else
    OUTPUT=${2-/root/g++-${VERSION}.tar.xz}
fi

# Workaround for Ubuntu builds
export LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
STAGING_DIR=/opt/compiler-explorer/g++-${VERSION}

MAJOR=1
MAJOR_MINOR=1.27

GCCURL=https://gcc.gnu.org/pub/gcc/old-releases/gcc-${MAJOR}/gcc-${MAJOR_MINOR}.tar.bz2
URL=https://gcc.gnu.org/pub/gcc/old-releases/gcc-${MAJOR}/g++-${MAJOR_MINOR}.0.tar.bz2

# “unload the tapes”
curl -L ${GCCURL} | tar jxf -
curl -L ${URL} | tar jxf -

applyPatches() {
    local PATCH_DIR=${ROOT}/patches/$2
    local PATCH=""
    if [[ -d ${PATCH_DIR} ]]; then
        echo "Applying patches from ${PATCH_DIR}"
        pushd $1
        for PATCH in ${PATCH_DIR}/*; do
            echo "...${PATCH}"
            patch -p1 <${PATCH}
        done
        popd
    fi
}

applyPatches gcc-${MAJOR_MINOR} gcc${MAJOR_MINOR}
applyPatches src-g++ g++${MAJOR_MINOR}

pushd gcc-${MAJOR_MINOR}
ln -s config-i386v.h config.h
ln -s tm-i386v.h tm.h
ln -s i386.md md
ln -s output-i386.c aux-output.c
sed -i "s|^bindir =.*|bindir = /opt/compiler-explorer/gcc-${VERSION}/bin|g" Makefile
sed -i "s|^libdir =.*|libdir = /opt/compiler-explorer/gcc-${VERSION}/lib|g" Makefile

make -j$(nproc)
popd

mkdir g++

pushd g++
ln -s ../src-g++/* .
ln -s ../gcc-${MAJOR_MINOR}/*.[chy] . || true
ln -s ../gcc-${MAJOR_MINOR}/*.def . || true
ln -s ../gcc-${MAJOR_MINOR}/*.md . || true
ln -s ../gcc-${MAJOR_MINOR}/move-if-change . || true
ln -s ../gcc-${MAJOR_MINOR}/config-i386v.h config.h || true
ln -s ../gcc-${MAJOR_MINOR}/tm-i386v.h tm.h || true
ln -s ../gcc-${MAJOR_MINOR}/i386.md md || true
ln -s ../gcc-${MAJOR_MINOR}/output-i386.c aux-output.c || true
popd

pushd g++
sed -i "s|^prefix =.*|prefix = /opt/compiler-explorer/g++-${VERSION}|g" Makefile

make -j$(nproc)
make -j$(nproc) install
popd

export XZ_DEFAULTS="-T 0"
tar Jcf ${OUTPUT} --transform "s,^./,./g++-${VERSION}/," -C ${STAGING_DIR} .

if [[ -n "${S3OUTPUT}" ]]; then
    aws s3 cp --storage-class REDUCED_REDUNDANCY "${OUTPUT}" "${S3OUTPUT}"
fi
