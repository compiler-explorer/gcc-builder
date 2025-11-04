# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository builds Docker images used to compile various GCC versions for [Compiler Explorer](https://godbolt.org/). The build system supports:
- Standard GCC releases (4.x through trunk)
- Experimental/proposal branches (contracts, coroutines, modules, etc.)
- Cross-compilers (AVR, CEGCC)
- Historical versions (GCC 1.27 + G++ 1.27)

## Build Commands

### Testing Locally

```bash
# Build the Docker image
docker build -t gccbuilder .

# Run a build inside the container
docker run gccbuilder ./build.sh trunk

# Interactive debugging
docker run -t -i gccbuilder bash
./build.sh trunk
```

### Build Script Invocation

All build scripts follow this pattern:
```bash
./build.sh VERSION [OUTPUTPATH] [LAST_REVISION]
./build-1.27.sh VERSION [OUTPUTPATH]
./build-avr.sh VERSION [OUTPUTPATH]
./build-ce.sh VERSION [OUTPUTPATH]
```

**OUTPUTPATH** can be:
- **A directory**: Creates `{dir}/gcc-{VERSION}.tar.xz` (or appropriate prefix)
- **A file path**: Creates the exact file specified
- **An S3 URL** (`s3://...`): Creates local temp file and uploads to S3
- **Omitted**: Defaults to `${ROOT}/gcc-{VERSION}.tar.xz`

**Directory detection is critical**: The scripts check `[[ -d "${2}" ]]` to determine if OUTPUTPATH is a directory. Without this check, passing `/build` would fail with "Cannot open: Is a directory".

### Build Output

Successful builds emit:
```
ce-build-revision:gcc-{GCC_SHA}-binutils-{BINUTILS_SHA}
ce-build-output:/path/to/output.tar.xz
ce-build-status:OK
```

If revision matches LAST_REVISION:
```
ce-build-status:SKIPPED
```

## Architecture

### Build Scripts

**build/build.sh** - Main build script
- Handles 200+ VERSION patterns (trunk, experimental branches, release versions)
- Supports special version prefixes: `assertions-`, `embed-trunk`, `lock3-contracts-trunk`, etc.
- Downloads GCC source from git (various repos/branches based on VERSION)
- Downloads prerequisites (GMP, MPFR, MPC, ISL) via `contrib/download_prerequisites`
- Optionally builds binutils from source (configurable per version)
- Applies patches and config overrides (see below)
- Builds with extensive configure flags for multilib, languages, plugins
- Creates compressed tarball with `tar Jcf` (xz compression)
- Optionally uploads to S3

**build/build-1.27.sh** - Historic GCC 1.27 + G++ 1.27 builder
- Builds GCC 1.27 and G++ 1.27.0 separately
- Links G++ sources with GCC sources (symlink approach)
- Uses hardcoded staging directory: `/opt/compiler-explorer/gcc-1.27`
- Special patches in `patches/gcc1.27/` and `patches/g++1.27/`

**build/build-avr.sh** - AVR cross-compiler builder
- Builds binutils, GCC, and avr-libc in sequence
- Cross-compilation target: `avr`
- Uses staging directory for install prefix

**build/build-ce.sh** - CEGCC (Windows cross-compiler) builder
- Clones GCC, w32api, mingwrt, and binutils from MaxKellermann's GitHub repos
- Uses branch pattern: `ce-{VERSION}`
- Runs `cegcc-build.sh` wrapper script

### Patch and Config System

The `applyPatchesAndConfig()` function applies version-specific customizations:

**Patches** (`build/patches/`):
- Applied with `patch -p1` from GCC source root
- Hierarchy: `patches/{dir}/` where `{dir}` can be:
  - `gcc{MAJOR}` (e.g., `gcc4`)
  - `gcc{MAJOR_MINOR}` (e.g., `gcc4.7`)
  - `gcc{VERSION}` (e.g., `gcc1.27`)
- Common patches: `cfns.patch`, `unwind.patch`, `msgfmt_lib.patch`, `symbol-versioning.patch`

**Config files** (`build/config/`):
- Bash scripts sourced to modify build variables
- Modify `CONFIG`, `CC`, `CXX`, `INSTALL_TARGET`, `BINUTILS_VERSION`, etc.
- Examples:
  - `disable_multilib` - Removes `--enable-multilib` from CONFIG
  - `gnu89` - Sets `CC='gcc -fgnu89-inline'`
  - `binutils_2_28` - Sets `BINUTILS_VERSION=2.28`
  - `host_binutils` - Uses system binutils instead of building
  - `install_without_strip` - Changes `INSTALL_TARGET=install`

**Application order**:
```bash
applyPatchesAndConfig "gcc${MAJOR}"           # e.g., gcc4
applyPatchesAndConfig "gcc${MAJOR_MINOR}"     # e.g., gcc4.7
applyPatchesAndConfig "gcc${PATCH_VERSION:-$VERSION}"  # e.g., gcc4.7.4
```

### Docker Environment

**Dockerfile**:
- Base: Ubuntu 22.04
- Key dependencies: build-essential, binutils, texinfo, libelf-dev, git, subversion
- AWS CLI v2 (for optional S3 uploads)
- Rust toolchain (required for GCC Rust frontend)
- Working directory: `/opt/compiler-explorer/gcc-build`
- Copies entire `build/` directory into container

**Important**: Build directory must be in `/opt/compiler-explorer/*` to avoid EPERM issues with older GCC versions that search the build prefix at runtime.

## Build System Details

### Staging and Output

1. **Staging directory**: `$(pwd)/staging`
   - Temporary install location (`--prefix`)
   - Cleaned before each build
   - Contains final compiler installation

2. **Output archive**: Created with:
   ```bash
   tar Jcf "${OUTPUT}" --transform "s,^./,./${FULLNAME}/," -C "${STAGING_DIR}" .
   ```
   - `Jcf` = xz compression, create file
   - `--transform` = Prepends `gcc-{VERSION}/` to all paths in archive
   - Archive root becomes `gcc-{VERSION}/bin`, `gcc-{VERSION}/lib`, etc.

### Version String Patterns

The build system recognizes many special VERSION patterns:
- `trunk` - Latest GCC master branch
- `{major}.{minor}.{patch}` - Release versions (e.g., `11.2.0`)
- `{major}.{minor}` - Latest point release (e.g., `11.2`)
- `{major}-snapshot` - Snapshot builds
- `embed-trunk` - ThePhD's embed proposal branch
- `lock3-contracts-trunk` - Lock3's contracts branch
- `contracts-nonattr` - Ville Voutilainen's contracts branch
- `lambda-p2034` - P2034 lambda proposal
- `p1144-trunk` - Quuxplusone's trivially relocatable proposal
- `cxx-modules-trunk` - C++ modules development branch
- `cxx-coroutines-trunk` - Coroutines branch
- `static-analysis-trunk` - Static analyzer branch
- `gccrs-master` - GCC Rust frontend
- `algol68-master` - Algol68 frontend
- `assertions-{version}` - Adds `--enable-checking=yes,rtl,extra`

### Revision Tracking

Builds track GCC and binutils git SHA:
```bash
GCC_REVISION=$(git ls-remote --heads ${URL} "refs/heads/${BRANCH}" | cut -f 1)
BINUTILS_REVISION=$(git ls-remote --heads ${BINUTILS_GITURL} refs/heads/master | cut -f 1)
REVISION="gcc-${GCC_REVISION}-binutils-${BINUTILS_REVISION}"
```

If `REVISION == LAST_REVISION`, build is skipped (outputs `SKIPPED` status).

## Key Conventions

### Build Script Parameters

All build scripts must:
1. Accept VERSION as `$1`
2. Accept optional OUTPUTPATH as `$2`
3. Detect if `$2` is a directory using `[[ -d "${2}" ]]`
4. Create `FULLNAME` variable for archive naming
5. Use proper quoting: `"${OUTPUT}"`, `"${STAGING_DIR}"`, `"$2"`
6. Emit status output: `ce-build-revision:`, `ce-build-output:`, `ce-build-status:`

### Tar Transform Pattern

Always use `--transform "s,^./,./${FULLNAME}/,"` to ensure archive contents are in a top-level directory named after the compiler version.

### S3 Support (Optional)

While builds now primarily output to directories, S3 upload support remains:
```bash
if [[ -n "${S3OUTPUT}" ]]; then
    aws s3 cp --storage-class REDUCED_REDUNDANCY "${OUTPUT}" "${S3OUTPUT}"
fi
```

## CI/CD

GitHub Actions workflow (`.github/workflows/build.yml`):
- Triggers on push to `main` or manual dispatch
- Builds Docker image with BuildKit
- Pushes to Docker Hub: `compilerexplorer/gcc-builder:latest`
- Uses layer caching for faster rebuilds

No automated GCC builds in CI - the Docker image is the deliverable. Actual GCC compilation happens separately using this image.
