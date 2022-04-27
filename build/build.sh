#!/bin/bash

set -ex

ROOT=$(pwd)
VERSION=$1
LANGUAGES=c,c++,fortran,ada
PLUGINS=
BINUTILS_GITURL=https://sourceware.org/git/binutils-gdb.git
BINUTILS_VERSION=2.38
BINUTILS_REVISION=$BINUTILS_VERSION
if echo "${VERSION}" | grep 'embed-trunk'; then
    VERSION=embed-trunk-$(date +%Y%m%d)
    URL=https://github.com/ThePhD/gcc.git
    BRANCH=feature/embed
    MAJOR=10
    MAJOR_MINOR=10-trunk
    LANGUAGES=c,c++
elif echo "${VERSION}" | grep 'lock3-contracts-trunk'; then
    VERSION=lock3-contracts-trunk-$(date +%Y%m%d)
    URL=https://github.com/lock3/gcc.git
    BRANCH=contracts
    MAJOR=10
    MAJOR_MINOR=10-trunk
    LANGUAGES=c,c++
elif echo "${VERSION}" | grep 'lock3-contract-labels-trunk'; then
    VERSION=lock3-contract-labels-trunk-$(date +%Y%m%d)
    URL=https://github.com/lock3/gcc.git
    BRANCH=contract-labels
    MAJOR=10
    MAJOR_MINOR=10-trunk
    LANGUAGES=c,c++
elif echo "${VERSION}" | grep 'cxx-modules-trunk'; then
    VERSION=cxx-modules-trunk-$(date +%Y%m%d)
    URL=git://gcc.gnu.org/git/gcc.git
    BRANCH=devel/c++-modules
    MAJOR=10
    MAJOR_MINOR=10-trunk
    LANGUAGES=c,c++
elif echo "${VERSION}" | grep 'cxx-coroutines-trunk'; then
    VERSION=cxx-coroutines-trunk-$(date +%Y%m%d)
    URL=git://gcc.gnu.org/git/gcc.git
    BRANCH=devel/c++-coroutines
    MAJOR=10
    MAJOR_MINOR=10-trunk
    LANGUAGES=c,c++
elif echo "${VERSION}" | grep 'static-analysis-trunk'; then
    VERSION=static-analysis-trunk-$(date +%Y%m%d)
    URL=git://gcc.gnu.org/git/gcc.git
    BRANCH=devel/analyzer
    MAJOR=10
    MAJOR_MINOR=10-trunk
    LANGUAGES=c,c++
    PLUGINS=analyzer
elif echo "${VERSION}" | grep 'gccrs-master'; then
    VERSION=gccrs-master-$(date +%Y%m%d)
    URL=https://github.com/Rust-GCC/gccrs.git
    BRANCH=master
    MAJOR=11
    MAJOR_MINOR=11-trunk
    LANGUAGES=rust
elif echo "${VERSION}" | grep 'trunk'; then
    VERSION=trunk-$(date +%Y%m%d)
    URL=git://gcc.gnu.org/git/gcc.git
    BRANCH=master
    MAJOR=12
    MAJOR_MINOR=12-trunk
    LANGUAGES=${LANGUAGES},d
else
    MAJOR=$(echo "${VERSION}" | grep -oE '^[0-9]+')
    MAJOR_MINOR=$(echo "${VERSION}" | grep -oE '^[0-9]+\.[0-9]+')
    MINOR=$(echo "${MAJOR_MINOR}" | cut -d. -f2)
    URL=git://gcc.gnu.org/git/gcc.git
    BRANCH=releases/gcc-${VERSION}
    if [[ "${MAJOR}" -gt 4 ]] || [[ "${MAJOR}" -eq 4 && "${MINOR}" -ge 7 ]]; then LANGUAGES=${LANGUAGES},go; fi
    if [[ "${MAJOR}" -ge 9 ]]; then LANGUAGES=${LANGUAGES},d; fi
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

BINUTILS_NEEDS_GMP=
if [[ "${BINUTILS_VERSION}" == "trunk" ]]; then
    BINUTILS_REVISION="$(git ls-remote --heads ${BINUTILS_GITURL} refs/heads/master | cut -f 1)"
    BINUTILS_NEEDS_GMP=yes
fi

GCC_REVISION=$(git ls-remote --heads ${URL} "refs/heads/${BRANCH}" | cut -f 1)
REVISION="gcc-${GCC_REVISION}-binutils-${BINUTILS_REVISION}"
LAST_REVISION="${3}"

PKGVERSION="Compiler-Explorer-Build-${REVISION}"

echo "ce-build-revision:${REVISION}"
echo "ce-build-output:${OUTPUT}"

if [[ "${REVISION}" == "${LAST_REVISION}" ]]; then
    echo "ce-build-status:SKIPPED"
    exit
fi

# Workaround for Ubuntu builds
export LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
STAGING_DIR=$(pwd)/staging
INSTALL_TARGET=install-strip
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

rm -rf "gcc-${VERSION}"
git clone -q --depth 1 --single-branch -b "${BRANCH}" "${URL}" "gcc-${VERSION}"

echo "Downloading prerequisites"
pushd "gcc-${VERSION}"
if [[ -f ./contrib/download_prerequisites ]]; then
    ./contrib/download_prerequisites
else
    # Older GCCs lacked it, so this is one stolen from GCC 4.6.1
    ../download_prerequisites
fi
popd

applyPatchesAndConfig() {
    local PATCH_DIR=${ROOT}/patches/$1
    local PATCH=""
    if [[ -d ${PATCH_DIR} ]]; then
        echo "Applying patches from ${PATCH_DIR}"
        pushd "gcc-${VERSION}"
        for PATCH in "${PATCH_DIR}"/*; do
            patch -p1 <"${PATCH}"
        done
        popd
    fi

    local CONFIG_DIR=${ROOT}/config/$1
    local CONFIG_FILE=""
    if [[ -d ${CONFIG_DIR} ]]; then
        echo "Applying config from ${CONFIG_DIR}"
        for CONFIG_FILE in "${CONFIG_DIR}"/*; do
            # shellcheck disable=SC1090
            . "${CONFIG_FILE}"
        done
    fi
}

CONFIG=""
CONFIG+=" --build=x86_64-linux-gnu"
CONFIG+=" --host=x86_64-linux-gnu"
CONFIG+=" --target=x86_64-linux-gnu"
CONFIG+=" --disable-bootstrap"
CONFIG+=" --enable-multiarch"
CONFIG+=" --with-abi=m64"
CONFIG+=" --with-multilib-list=m32,m64,mx32"
CONFIG+=" --enable-multilib"
CONFIG+=" --enable-clocale=gnu"
CONFIG+=" --enable-languages=${LANGUAGES}"
CONFIG+=" --enable-ld=yes"
CONFIG+=" --enable-gold=yes"
CONFIG+=" --enable-libstdcxx-debug"
CONFIG+=" --enable-libstdcxx-time=yes"
CONFIG+=" --enable-linker-build-id"
CONFIG+=" --enable-lto"
CONFIG+=" --enable-plugins"
CONFIG+=" --enable-threads=posix"
CONFIG+=" --with-pkgversion=\"${PKGVERSION}\""
# The static analyzer branch adds a --enable-plugins configuration option
if [[ -n "${PLUGINS}" ]]; then
    CONFIG+=" --enable-plugins=${PLUGINS}"
fi

applyPatchesAndConfig "gcc${MAJOR}"
applyPatchesAndConfig "gcc${MAJOR_MINOR}"
applyPatchesAndConfig "gcc${VERSION}"

echo "Will configure with ${CONFIG}"

if [[ -z "${BINUTILS_VERSION}" ]]; then
    echo "Using host binutils $(ld -v)"
else
    BINUTILS_DIR=binutils-${BINUTILS_VERSION}
    rm -rf ${BINUTILS_DIR}

    if [[ "${BINUTILS_VERSION}" == "trunk" ]]; then
        git clone --depth=1 ${BINUTILS_GITURL} ${BINUTILS_DIR}
    else
        echo "Fetching binutils ${BINUTILS_VERSION}"
        if [[ ! -e binutils-${BINUTILS_VERSION}.tar.bz2 ]]; then
            curl -L -O http://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.bz2
        fi
        tar jxf binutils-${BINUTILS_VERSION}.tar.bz2
    fi
    mkdir ${BINUTILS_DIR}/objdir
    pushd ${BINUTILS_DIR}/objdir

    EXTRA_CONFIG_ARGS=
    GMP_DIR=../../gcc-${VERSION}/gmp
    if [[ -n "${BINUTILS_NEEDS_GMP}" ]]; then
        echo "Building GMP for binutils"
        pushd "${GMP_DIR}"
        # shellcheck disable=SC2086
        ./configure --prefix="${STAGING_DIR}" ${CONFIG}
        make -j"$(nproc)" install
        make distclean
        popd
        EXTRA_CONFIG_ARGS=--with-gmp="${STAGING_DIR}"
    fi

    # shellcheck disable=SC2086
    ../configure --prefix="${STAGING_DIR}" ${CONFIG} ${EXTRA_CONFIG_ARGS}
    make "-j$(nproc)"
    make ${INSTALL_TARGET}
    popd
fi

mkdir -p objdir
pushd objdir
# shellcheck disable=SC2086
"../gcc-${VERSION}/configure" --prefix="${STAGING_DIR}" ${CONFIG}
make "-j$(nproc)"
make ${INSTALL_TARGET}
popd

export XZ_DEFAULTS="-T 0"
tar Jcf "${OUTPUT}" --transform "s,^./,./gcc-${VERSION}/," -C "${STAGING_DIR}" .

if [[ -n "${S3OUTPUT}" ]]; then
    aws s3 cp --storage-class REDUCED_REDUNDANCY "${OUTPUT}" "${S3OUTPUT}"
fi

echo "ce-build-status:OK"
