#!/bin/bash

set -ex

# The Rust frontend needs cargo now (until it can build its rust deps, at some
# point, someday, eventually)
. "$HOME/.cargo/env"
command -v cargo

ROOT=$(pwd)
VERSION=$1
LANGUAGES=c,c++,fortran,ada,objc,obj-c++
PLUGINS=
BINUTILS_GITURL=https://sourceware.org/git/binutils-gdb.git
BINUTILS_VERSION=2.44
BINUTILS_REVISION=$BINUTILS_VERSION
CONFIG=""

# Defaults used for nearly every builds for recent GCC.
BOOTSTRAP_CONFIG="--disable-bootstrap"
INSTALL_TARGET=install-strip
MULTILIB_ENABLED="--enable-multilib"
WITH_ABI="--with-abi=m64"

ORIG_VERSION="${VERSION}"
VERSION=${VERSION#"assertions-"}

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
elif echo "${VERSION}" | grep 'contracts-nonattr'; then
    VERSION=contracts-nonattr-trunk-$(date +%Y%m%d)
    URL=https://github.com/villevoutilainen/gcc.git
    BRANCH=contracts-nonattr
    MAJOR=13
    MAJOR_MINOR=13-trunk
    LANGUAGES=c,c++
elif echo "${VERSION}" | grep 'lambda-p2034'; then
    VERSION=lambda-p2034-trunk-$(date +%Y%m%d)
    URL=https://github.com/villevoutilainen/gcc.git
    BRANCH=lambda-p2034
    MAJOR=15
    MAJOR_MINOR=15-trunk
    LANGUAGES=c,c++
elif echo "${VERSION}" | grep 'p1144-trunk'; then
    VERSION=p1144-trunk-$(date +%Y%m%d)
    URL=https://github.com/Quuxplusone/gcc.git
    BRANCH=trivially-relocatable
    MAJOR=13
    MAJOR_MINOR=13-trunk
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
    URL=https://github.com/iains/gcc-cxx-coroutines
    BRANCH=c++-coroutines
    MAJOR=15
    MAJOR_MINOR=15-trunk
    LANGUAGES=c,c++
elif echo "${VERSION}" | grep 'static-analysis-trunk'; then
    VERSION=static-analysis-trunk-$(date +%Y%m%d)
    URL=git://gcc.gnu.org/git/gcc.git
    BRANCH=devel/analyzer
    MAJOR=10
    MAJOR_MINOR=10-trunk
    LANGUAGES=c,c++
    PLUGINS=analyzer
elif echo "${VERSION}" | grep 'algol68-master'; then
    VERSION=ga68-master-$(date +%Y%m%d)
    URL=https://forge.sourceware.org/jemarch/a68-gcc.git
    BRANCH=a68
    MAJOR=15
    MAJOR_MINOR=15-trunk
    # Only algol68, this is intentional.
    LANGUAGES=algol68
elif echo "${VERSION}" | grep 'gccrs-master'; then
    VERSION=gccrs-master-$(date +%Y%m%d)
    URL=https://github.com/Rust-GCC/gccrs.git
    BRANCH=master
    MAJOR=13
    MAJOR_MINOR=13-trunk
    # Only rust, this is intentional.
    LANGUAGES=rust
    # This is needed because we are using some unstable features only available from
    # nightly compiler... or using the RUSTC_BOOTSTRAP escape hatch.
    export RUSTC_BOOTSTRAP=1
elif echo "${VERSION}" | grep 'cobol-master'; then
    VERSION=cobol-master-$(date +%Y%m%d)
    PATCH_VERSION=cobol-master
    URL=https://gitlab.cobolworx.com/COBOLworx/gcc-cobol.git
    BRANCH="master+cobol"
    MAJOR=13
    MAJOR_MINOR=13-trunk
    # Currently fails to build 32-bit multilibs
    MULTILIB_ENABLED=" --disable-multilib"
    ## implicit dep on C++ as libgcobol uses libstdc++.
    LANGUAGES=cobol,c++
elif echo "${VERSION}" | grep 'trunk'; then
    URL=git://gcc.gnu.org/git/gcc.git
    BRANCH=master
    MAJOR=15
    MAJOR_MINOR=15-trunk
    LANGUAGES="${LANGUAGES},go,d,rust,m2,cobol"
    CONFIG+=" --enable-libstdcxx-backtrace=yes"
    VERSION=trunk-$(date +%Y%m%d)
elif echo "${VERSION}" | grep 'renovated'; then
    SUB_VERSION=$(echo "${VERSION}" | cut -d'-' -f2)
    URL="https://github.com/jwakely/gcc"
    BRANCH="renovated/gcc-${SUB_VERSION}"
    MAJOR=$(echo "${SUB_VERSION}" | cut -d'.' -f1)
    MAJOR_MINOR=renovated-$(echo "${SUB_VERSION}" | cut -d'.' -f1-2)
    INSTALL_TARGET=install
    LANGUAGES="objc,c,c++"

    # we need to bootstrap, as recent compiler will choke on some C++ code.
    BOOTSTRAP_CONFIG=" "

    if [[ "${MAJOR}" -le 4 ]]; then
        WITH_ABI=" "
        MULTILIB_ENABLED=" --disable-multilib"
    fi

    MAJOR="renovated-${MAJOR}"
else
    MAJOR=$(echo "${VERSION}" | grep -oE '^[0-9]+')
    MAJOR_MINOR=$(echo "${VERSION}" | grep -oE '^[0-9]+\.[0-9]+')
    MINOR=$(echo "${MAJOR_MINOR}" | cut -d. -f2)
    URL=git://gcc.gnu.org/git/gcc.git
    BRANCH=releases/gcc-${VERSION}
    if [[ "${MAJOR}" -gt 4 ]] || [[ "${MAJOR}" -eq 4 && "${MINOR}" -ge 7 ]]; then LANGUAGES=${LANGUAGES},go; fi
    if [[ "${MAJOR}" -ge 9 ]]; then LANGUAGES=${LANGUAGES},d; fi

    # Need this explicit flag for enabling <backtrace> support.
    # See https://github.com/compiler-explorer/compiler-explorer/issues/6103
    if [[ "${MAJOR}" -ge 12 ]]; then CONFIG+=" --enable-libstdcxx-backtrace=yes"; fi

    # Languages introduced in 13
    if [[ "${MAJOR}" -ge 13 ]]; then LANGUAGES=${LANGUAGES},m2; fi

    # Languages introduced in 14
    if [[ "${MAJOR}" -ge 14 ]]; then LANGUAGES=${LANGUAGES},rust; fi

    # Languages introduced in 15
    if [[ "${MAJOR}" -ge 15 ]]; then LANGUAGES=${LANGUAGES},cobol; fi

fi

## If version is prefixed by "assertions-", do the extra steps we want for the
## assertions- builds.
if [[ "${ORIG_VERSION}" == assertions-* ]]; then
    VERSION="assertions-${VERSION}"
    CONFIG+=" --enable-checking=yes,rtl,extra"
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

CONFIG+=" --build=x86_64-linux-gnu"
CONFIG+=" --host=x86_64-linux-gnu"
CONFIG+=" --target=x86_64-linux-gnu"
CONFIG+=" ${BOOTSTRAP_CONFIG}"
CONFIG+=" --enable-multiarch"
CONFIG+=" ${WITH_ABI}"
CONFIG+=" --with-multilib-list=m32,m64,mx32"
CONFIG+=" ${MULTILIB_ENABLED}"
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
applyPatchesAndConfig "gcc${PATCH_VERSION:-$VERSION}"

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
