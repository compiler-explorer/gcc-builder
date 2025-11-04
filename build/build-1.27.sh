#!/bin/bash

set -ex

ROOT=$(pwd)
VERSION=$1
if [[ "$VERSION" != "1.27" ]]; then
    echo "Wrong version"
    exit 1
fi

FULLNAME=gcc-${VERSION}
OUTPUT=${ROOT}/${FULLNAME}.tar.xz
S3OUTPUT=""
if echo "$2" | grep s3://; then
    S3OUTPUT=$2
else
    if [[ -d "${2}" ]]; then
        OUTPUT=$2/${FULLNAME}.tar.xz
    else
        OUTPUT=${2-$OUTPUT}
    fi
fi
echo "ce-build-output:${OUTPUT}"

STAGING_DIR=/opt/compiler-explorer/gcc-${VERSION}

MAJOR=1
MAJOR_MINOR=1.27

GCC_URL=https://gcc.gnu.org/pub/gcc/old-releases/gcc-${MAJOR}/gcc-${MAJOR_MINOR}.tar.bz2
GPLUSPLUS_URL=https://gcc.gnu.org/pub/gcc/old-releases/gcc-${MAJOR}/g++-${MAJOR_MINOR}.0.tar.bz2

# “unload the tapes”
curl -L ${GCC_URL} | tar jxf -
curl -L ${GPLUSPLUS_URL} | tar jxf -

applyPatchesAndConfig() {
    local PATCH_DIR=${ROOT}/patches/$1
    local PATCH=""
    if [[ -d ${PATCH_DIR} ]]; then
        echo "Applying patches from ${PATCH_DIR}"
        pushd $2
        for PATCH in ${PATCH_DIR}/*; do
            echo "...${PATCH}"
            patch -p1 <${PATCH}
        done
        popd
    fi

    local CONFIG_DIR=${ROOT}/config/$1
    local CONFIG_FILE=""
    if [[ -d ${CONFIG_DIR} ]]; then
        echo "Applying config from ${CONFIG_DIR}"
        for CONFIG_FILE in ${CONFIG_DIR}/*; do
            echo "...${CONFIG_FILE}"
            . ${CONFIG_FILE}
        done
    fi
}

applyPatchesAndConfig gcc${MAJOR_MINOR} gcc-${MAJOR_MINOR}
applyPatchesAndConfig g++${MAJOR_MINOR} src-g++

pushd gcc-${MAJOR_MINOR}
ln -s config-i386v.h config.h
ln -s tm-i386v.h tm.h
ln -s i386.md md
ln -s output-i386.c aux-output.c
sed -i "s|^bindir =.*|bindir = /opt/compiler-explorer/gcc-${VERSION}/bin|g" Makefile
sed -i "s|^libdir =.*|libdir = /opt/compiler-explorer/gcc-${VERSION}/lib|g" Makefile

make -j$(nproc)
make -j$(nproc) stage1
make -j$(nproc) CC=stage1/gcc CFLAGS="-Bstage1/ -Iinclude"
make -j$(nproc) install
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

sed -i "s|^prefix =.*|prefix = /opt/compiler-explorer/gcc-${VERSION}|g" Makefile

make -j$(nproc)
make -j$(nproc) install
popd

export XZ_DEFAULTS="-T 0"
tar Jcf "${OUTPUT}" --transform "s,^./,./${FULLNAME}/," -C "${STAGING_DIR}" .

if [[ -n "${S3OUTPUT}" ]]; then
    aws s3 cp --storage-class REDUCED_REDUNDANCY "${OUTPUT}" "${S3OUTPUT}"
fi

echo "ce-build-status:OK"
