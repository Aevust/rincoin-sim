#!/bin/bash
# Build script for Rincoin release binaries
# This script:
# - Clones from git and checks out the specified version tag
# - Creates source code packages (tar.gz and zip)
# - Builds Linux binaries (Ubuntu 20.04 base for max compatibility)
# - Builds Windows binaries (Win10 x64+)
# - Generates checksums and release documentation
# 
# Usage: ./contrib/build_release.sh <git-tag> [git-url] [--clean]
# Example: ./contrib/build_release.sh v1.0.1
# Example: ./contrib/build_release.sh v1.0.1 https://github.com/Rin-coin/rincoin.git --clean

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
CLEAN_BUILD=false
if [ -z "$1" ]; then
    echo -e "${RED}Error: Version tag is required${NC}"
    echo "Usage: $0 <git-tag> [git-url] [--clean]"
    echo "Example: $0 v1.0.1"
    echo "Example: $0 v1.0.1 https://github.com/Rin-coin/rincoin.git --clean"
    exit 1
fi

GIT_TAG="${1}"
shift

# Parse optional arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        *)
            if [ -z "$GIT_URL" ]; then
                GIT_URL="$1"
            fi
            shift
            ;;
    esac
done

GIT_URL="${GIT_URL:-https://github.com/Rin-coin/rincoin.git}"
VERSION="${GIT_TAG#v}"  # Remove 'v' prefix if present

# Build directories
TEMP_DIR="/tmp/rincoin-build-$$"
SOURCE_DIR="${TEMP_DIR}/rincoin"
BUILD_DIR="${PROJECT_ROOT}/release-builds/${VERSION}"
BDB_PREFIX="${PROJECT_ROOT}/db4"

# Cache directories for depends system (speeds up rebuilds)
CACHE_DIR="${PROJECT_ROOT}/.build-cache"
DEPENDS_SOURCES_CACHE="${CACHE_DIR}/depends-sources"
DEPENDS_BUILT_CACHE="${CACHE_DIR}/depends-built"

# Build on Ubuntu 20.04 for compatibility with 20.04, 22.04, and 24.04
BUILD_UBUNTU_VERSION="20.04"
BUILD_UBUNTU_CODENAME="focal"

# Architectures to build
CROSS_HOSTS=("x86_64-linux-gnu" "x86_64-w64-mingw32")
CROSS_NAMES=("x86_64" "win64")
CROSS_PLATFORMS=("linux" "windows")

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Rincoin Release Build Script${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "${BLUE}Git Tag:${NC} ${GIT_TAG}"
echo -e "${BLUE}Version:${NC} ${VERSION}"
echo -e "${BLUE}Git URL:${NC} ${GIT_URL}"
echo -e "${BLUE}Clean Build:${NC} ${CLEAN_BUILD}"
echo -e "${BLUE}Cache Dir:${NC} ${CACHE_DIR}"
echo -e "${YELLOW}Building on Ubuntu ${BUILD_UBUNTU_VERSION}${NC}"
echo -e "${YELLOW}Binary will be compatible with Ubuntu 20.04+, Debian 11+, RHEL 8+${NC}"
echo ""

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        print_info "Cleaning up temporary directory..."
        rm -rf "$TEMP_DIR"
    fi
}

# Clean cache if requested
clean_cache() {
    if [ "$CLEAN_BUILD" = "true" ]; then
        print_info "Clean build requested - removing build cache..."
        if [ -d "$CACHE_DIR" ]; then
            rm -rf "$CACHE_DIR"
            print_info "Build cache removed: ${CACHE_DIR}"
        fi
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Clone repository and checkout version
clone_and_checkout() {
    print_info "======================================"
    print_info "Cloning Repository"
    print_info "======================================"
    
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    print_info "Cloning from: ${GIT_URL}"
    git clone --depth 1 --branch "$GIT_TAG" "$GIT_URL" "$SOURCE_DIR" || {
        print_error "Failed to clone repository or checkout tag ${GIT_TAG}"
        print_error "Make sure the tag exists: git tag | grep ${GIT_TAG}"
        exit 1
    }
    
    cd "$SOURCE_DIR"
    local commit_hash=$(git rev-parse HEAD)
    local commit_date=$(git log -1 --format=%cd --date=short)
    
    print_info "Checked out tag: ${GIT_TAG}"
    print_info "Commit: ${commit_hash}"
    print_info "Date: ${commit_date}"
}

# Create source packages
create_source_packages() {
    print_info "======================================"
    print_info "Creating Source Packages"
    print_info "======================================"
    
    cd "$TEMP_DIR"
    local source_name="rincoin-${VERSION}"
    
    # Create a clean copy without .git
    print_info "Preparing source directory..."
    cp -r "$SOURCE_DIR" "${source_name}"
    rm -rf "${source_name}/.git"
    
    # Create tar.gz
    print_info "Creating ${source_name}.tar.gz..."
    tar czf "${source_name}.tar.gz" "${source_name}/"
    
    # Create zip
    print_info "Creating ${source_name}.zip..."
    zip -r -q "${source_name}.zip" "${source_name}/"
    
    # Move to build directory
    mkdir -p "${BUILD_DIR}/source"
    mv "${source_name}.tar.gz" "${BUILD_DIR}/source/"
    mv "${source_name}.zip" "${BUILD_DIR}/source/"
    
    # Cleanup temp source copy
    rm -rf "${source_name}"
    
    print_info "Source packages created:"
    ls -lh "${BUILD_DIR}/source/"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check for required commands
    local required_commands=("docker" "git" "tar" "gzip" "zip")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if db4 is installed
    if [ ! -d "$BDB_PREFIX" ]; then
        print_error "Berkeley DB 4.8 not found at $BDB_PREFIX"
        print_info "Please run: ./contrib/install_db4.sh \$(pwd)"
        exit 1
    fi
    
    print_info "All prerequisites met!"
}

# Create build directory structure
setup_build_dirs() {
    print_info "Setting up build directories..."
    mkdir -p "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}/binaries/linux"
    mkdir -p "${BUILD_DIR}/binaries/windows"
    mkdir -p "${BUILD_DIR}/tarballs"
    mkdir -p "${BUILD_DIR}/source"
    
    # Setup cache directories
    mkdir -p "${DEPENDS_SOURCES_CACHE}"
    mkdir -p "${DEPENDS_BUILT_CACHE}"
    
    if [ -d "${DEPENDS_SOURCES_CACHE}" ] && [ "$(ls -A ${DEPENDS_SOURCES_CACHE})" ]; then
        print_info "Using cached dependency downloads from: ${DEPENDS_SOURCES_CACHE}"
    fi
    
    if [ -d "${DEPENDS_BUILT_CACHE}" ] && [ "$(ls -A ${DEPENDS_BUILT_CACHE})" ]; then
        print_info "Using cached built dependencies from: ${DEPENDS_BUILT_CACHE}"
    fi
    
    print_info "Build directories created at: ${BUILD_DIR}"
}

# Build Linux binaries
build_linux_binaries() {
    print_info "======================================"
    print_info "Building Linux Binaries"
    print_info "======================================"
    
    local dockerfile="${BUILD_DIR}/Dockerfile.linux"
    local image_name="rincoin-builder:linux"
    
    # Check if we should rebuild the image
    if [ "$CLEAN_BUILD" = "true" ]; then
        print_info "Clean build requested - removing existing Docker image..."
        docker rmi "$image_name" 2>/dev/null || true
    fi
    
    # Check if image already exists
    if docker image inspect "$image_name" >/dev/null 2>&1; then
        print_info "Using existing Docker image: $image_name"
        print_info "(Use --clean flag to rebuild)"
    else
        print_info "Building new Docker image..."
    
    cat > "$dockerfile" << 'DOCKERFILE_END'
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y \
    build-essential \
    libtool \
    autotools-dev \
    automake \
    pkg-config \
    bsdmainutils \
    python3 \
    libssl-dev \
    libevent-dev \
    libboost-system-dev \
    libboost-filesystem-dev \
    libboost-test-dev \
    libboost-thread-dev \
    libfmt-dev \
    libminiupnpc-dev \
    libzmq3-dev \
    libsqlite3-dev \
    libqt5gui5 \
    libqt5core5a \
    libqt5dbus5 \
    qttools5-dev \
    qttools5-dev-tools \
    libqrencode-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
DOCKERFILE_END

        docker build -t "$image_name" -f "$dockerfile" "${BUILD_DIR}" || {
            print_error "Failed to build Linux Docker image"
            return 1
        }
    fi
    
    print_info "Compiling Rincoin for Linux..."
    
    docker run --rm \
        -v "${SOURCE_DIR}:/source:ro" \
        -v "${BDB_PREFIX}:/db4:ro" \
        -v "${BUILD_DIR}:/output" \
        -v "${DEPENDS_SOURCES_CACHE}:/depends_sources_cache" \
        -v "${DEPENDS_BUILT_CACHE}:/depends_built_cache" \
        -e "VERSION=${VERSION}" \
        "$image_name" \
        bash -c '
            set -e
            cp -r /source /build/rincoin
            cd /build/rincoin
            
            ./autogen.sh
            
            ./configure \
                BDB_LIBS="-L/db4/lib -ldb_cxx-4.8" \
                BDB_CFLAGS="-I/db4/include" \
                --prefix=/usr/local \
                --disable-tests \
                --disable-bench \
                --enable-reduce-exports \
                LDFLAGS="-static-libstdc++" \
                --with-incompatible-bdb=no
            
            make -j$(nproc)
            strip src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet src/qt/rincoin-qt || true
            
            # Copy binaries
            cp src/rincoind /output/binaries/linux/
            cp src/rincoin-cli /output/binaries/linux/
            cp src/rincoin-tx /output/binaries/linux/
            cp src/rincoin-wallet /output/binaries/linux/
            cp src/qt/rincoin-qt /output/binaries/linux/
            
            # Create tarball
            mkdir -p /tmp/rincoin-'"${VERSION}"'/bin
            cp src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet src/qt/rincoin-qt /tmp/rincoin-'"${VERSION}"'/bin/
            cd /tmp
            tar czf /output/tarballs/rincoin-'"${VERSION}"'-x86_64-linux-gnu.tar.gz rincoin-'"${VERSION}"'/
        ' || {
        print_error "Linux build failed"
        return 1
    }
    
    print_info "Linux binaries built successfully!"
}

# Build Windows binaries
build_windows_binaries() {
    print_info "======================================"
    print_info "Building Windows Binaries (Win10 x64+)"
    print_info "======================================"
    
    local dockerfile="${BUILD_DIR}/Dockerfile.windows"
    local image_name="rincoin-builder:windows"
    
    # Check if we should rebuild the image
    if [ "$CLEAN_BUILD" = "true" ]; then
        print_info "Clean build requested - removing existing Docker image..."
        docker rmi "$image_name" 2>/dev/null || true
    fi
    
    # Check if image already exists
    if docker image inspect "$image_name" >/dev/null 2>&1; then
        print_info "Using existing Docker image: $image_name"
        print_info "(Use --clean flag to rebuild)"
    else
        print_info "Building new Docker image..."
    
    cat > "$dockerfile" << 'DOCKERFILE_END'
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y \
    build-essential \
    libtool \
    autotools-dev \
    automake \
    pkg-config \
    bsdmainutils \
    python3 \
    curl \
    git \
    cmake \
    g++-mingw-w64-x86-64 \
    gcc-mingw-w64-x86-64 \
    binutils-mingw-w64-x86-64 \
    mingw-w64-tools \
    nsis \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Use posix variant for threading support
RUN update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix && \
    update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

WORKDIR /build
DOCKERFILE_END

        docker build -t "$image_name" -f "$dockerfile" "${BUILD_DIR}" || {
            print_error "Failed to build Windows Docker image"
            return 1
        }
    fi
    
    print_info "Compiling Rincoin for Windows..."
    print_info "Building dependencies first (this may take 30-60 minutes)..."
    
    docker run --rm \
        -v "${SOURCE_DIR}:/source:ro" \
        -v "${BUILD_DIR}:/output" \
        -v "${DEPENDS_SOURCES_CACHE}:/depends_sources_cache" \
        -v "${DEPENDS_BUILT_CACHE}:/depends_built_cache" \
        -e "VERSION=${VERSION}" \
        "$image_name" \
        bash -c '
            set -e
            cp -r /source /build/rincoin
            cd /build/rincoin
            
            # Setup symlinks to cache directories for depends system
            # This allows depends to reuse downloaded sources and built packages
            mkdir -p depends/sources depends/built
            
            # Link cache directories (if they have content, use them)
            if [ -d "/depends_sources_cache" ]; then
                # Copy cached sources to local depends
                cp -r /depends_sources_cache/* depends/sources/ 2>/dev/null || true
            fi
            
            if [ -d "/depends_built_cache" ]; then
                # Copy cached built packages to local depends
                cp -r /depends_built_cache/* depends/built/ 2>/dev/null || true
            fi
            
            # Build dependencies for Windows
            cd depends
            make -j$(nproc) HOST=x86_64-w64-mingw32
            
            # Copy back to cache for next build
            cp -r sources/* /depends_sources_cache/ 2>/dev/null || true
            cp -r built/* /depends_built_cache/ 2>/dev/null || true
            
            cd ..
            
            ./autogen.sh
            
            CONFIG_SITE=$PWD/depends/x86_64-w64-mingw32/share/config.site ./configure \
                --prefix=/ \
                --disable-tests \
                --disable-bench \
                --enable-reduce-exports \
                --disable-gui-tests
            
            make -j$(nproc)
            
            # Strip Windows binaries
            x86_64-w64-mingw32-strip src/rincoind.exe src/rincoin-cli.exe src/rincoin-tx.exe src/rincoin-wallet.exe src/qt/rincoin-qt.exe || true
            
            # Copy binaries
            mkdir -p /output/binaries/windows
            cp src/rincoind.exe /output/binaries/windows/
            cp src/rincoin-cli.exe /output/binaries/windows/
            cp src/rincoin-tx.exe /output/binaries/windows/
            cp src/rincoin-wallet.exe /output/binaries/windows/
            cp src/qt/rincoin-qt.exe /output/binaries/windows/
            
            # Create zip archive
            mkdir -p /tmp/rincoin-'"${VERSION}"'
            cp src/*.exe /tmp/rincoin-'"${VERSION}"'/ 2>/dev/null || true
            cp src/qt/rincoin-qt.exe /tmp/rincoin-'"${VERSION}"'/ 2>/dev/null || true
            cd /tmp
            zip -r /output/tarballs/rincoin-'"${VERSION}"'-win64.zip rincoin-'"${VERSION}"'/
        ' || {
        print_error "Windows build failed"
        return 1
    }
    
    print_info "Windows binaries built successfully!"
}

# Create checksums file
create_checksums() {
    print_info "======================================"
    print_info "Creating Checksums"
    print_info "======================================"
    
    cd "${BUILD_DIR}"
    
    # Checksums for source packages
    cd source
    sha256sum * > SHA256SUMS.txt 2>/dev/null || true
    print_info "Source checksums:"
    cat SHA256SUMS.txt
    
    # Checksums for tarballs/archives
    cd ../tarballs
    sha256sum * > SHA256SUMS.txt 2>/dev/null || true
    print_info "Archive checksums:"
    cat SHA256SUMS.txt
    
    # Checksums for individual binaries
    cd ../binaries/linux
    sha256sum * > SHA256SUMS.txt 2>/dev/null || true
    
    cd ../windows
    sha256sum * > SHA256SUMS.txt 2>/dev/null || true
    
    print_info "All checksums created!"
}

# Create release notes
create_release_info() {
    print_info "======================================"
    print_info "Creating Release Documentation"
    print_info "======================================"
    
    local git_commit=$(cd "$SOURCE_DIR" && git rev-parse HEAD 2>/dev/null || echo "N/A")
    local git_date=$(cd "$SOURCE_DIR" && git log -1 --format=%cd --date=short 2>/dev/null || echo "N/A")
    
    cat > "${BUILD_DIR}/README.txt" << EOF
================================================================================
Rincoin ${VERSION} Release Binaries
================================================================================

Build Information:
------------------
Build Date:      $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Git Tag:         ${GIT_TAG}
Git Commit:      ${git_commit}
Git Date:        ${git_date}
Build Platform:  Ubuntu ${BUILD_UBUNTU_VERSION} (${BUILD_UBUNTU_CODENAME})

Supported Platforms:
--------------------
LINUX (x86_64):
  - Ubuntu 20.04 LTS, 22.04 LTS, 24.04 LTS
  - Debian 11 (Bullseye), 12 (Bookworm)
  - RHEL/Rocky/Alma Linux 8, 9
  - Fedora 35+
  - Most modern Linux distributions with glibc 2.31+

WINDOWS (x64):
  - Windows 10 (64-bit)
  - Windows 11 (64-bit)
  - Windows Server 2016+

Release Contents:
-----------------

SOURCE CODE (source/):
  - rincoin-${VERSION}.tar.gz    : Source code archive (tar.gz)
  - rincoin-${VERSION}.zip        : Source code archive (zip)
  - SHA256SUMS.txt                : Source checksums

BINARY ARCHIVES (tarballs/):
  - rincoin-${VERSION}-x86_64-linux-gnu.tar.gz : Linux binaries
  - rincoin-${VERSION}-win64.zip               : Windows binaries
  - SHA256SUMS.txt                             : Archive checksums

INDIVIDUAL BINARIES (binaries/):
  Linux (binaries/linux/):
    - rincoind          : Rincoin daemon (server)
    - rincoin-cli       : Command-line RPC client
    - rincoin-tx        : Transaction utility
    - rincoin-wallet    : Wallet utility
    - rincoin-qt        : GUI wallet (Qt)
    - SHA256SUMS.txt    : Binary checksums
  
  Windows (binaries/windows/):
    - rincoind.exe      : Rincoin daemon (server)
    - rincoin-cli.exe   : Command-line RPC client
    - rincoin-tx.exe    : Transaction utility
    - rincoin-wallet.exe: Wallet utility
    - rincoin-qt.exe    : GUI wallet (Qt)
    - SHA256SUMS.txt    : Binary checksums

Verification:
-------------
Verify the integrity of downloaded files using SHA256 checksums:

  For source:
    cd source/
    sha256sum -c SHA256SUMS.txt

  For archives:
    cd tarballs/
    sha256sum -c SHA256SUMS.txt

  For individual binaries:
    cd binaries/linux/    # or binaries/windows/
    sha256sum -c SHA256SUMS.txt

Installation - Linux:
---------------------

Option 1: From Binary Archive
  tar xzf rincoin-${VERSION}-x86_64-linux-gnu.tar.gz
  sudo cp rincoin-${VERSION}/bin/* /usr/local/bin/

Option 2: Direct Binary Usage
  chmod +x binaries/linux/*
  sudo cp binaries/linux/* /usr/local/bin/

Option 3: Build from Source
  tar xzf source/rincoin-${VERSION}.tar.gz
  cd rincoin-${VERSION}
  ./autogen.sh
  ./configure
  make -j\$(nproc)
  sudo make install

Installation - Windows:
-----------------------

Option 1: From Archive
  1. Extract rincoin-${VERSION}-win64.zip
  2. Run rincoin-qt.exe for GUI wallet
  3. Or run rincoind.exe for daemon mode

Option 2: Direct Usage
  1. Copy binaries from binaries/windows/ to desired location
  2. Run rincoin-qt.exe for GUI wallet

Usage:
------

LINUX:
  Start daemon:     rincoind -daemon
  Check status:     rincoin-cli getblockchaininfo
  Stop daemon:      rincoin-cli stop
  GUI wallet:       rincoin-qt

WINDOWS:
  GUI wallet:       Double-click rincoin-qt.exe
  Daemon mode:      rincoind.exe -daemon (from command prompt)
  RPC client:       rincoin-cli.exe getblockchaininfo

Configuration:
--------------
Create configuration file:

LINUX:   ~/.rincoin/rincoin.conf
WINDOWS: %APPDATA%\\Rincoin\\rincoin.conf

Example configuration:
  server=1
  daemon=1
  rpcuser=your_username
  rpcpassword=your_secure_password
  rpcallowip=127.0.0.1

Network Ports:
--------------
  P2P:  9555
  RPC:  9556

More Information:
-----------------
  Website:  https://www.rincoin.net/
  Discord:  https://discord.gg/Ap7TUXYRBf
  GitHub:   https://github.com/Rin-coin/rincoin

================================================================================
EOF
    
    print_info "Release documentation saved to: ${BUILD_DIR}/README.txt"
}

# Main execution
main() {
    check_prerequisites
    clean_cache
    clone_and_checkout
    setup_build_dirs
    create_source_packages
    build_linux_binaries
    build_windows_binaries
    create_checksums
    create_release_info
    
    echo ""
    print_info "======================================"
    print_info "BUILD COMPLETE!"
    print_info "======================================"
    print_info "All release artifacts are in:"
    print_info "  ${BUILD_DIR}"
    echo ""
    print_info "Contents:"
    print_info "  - source/             : Source code archives"
    print_info "  - binaries/linux/     : Linux binaries"
    print_info "  - binaries/windows/   : Windows binaries"
    print_info "  - tarballs/           : Distribution archives"
    print_info "  - README.txt          : Release documentation"
    echo ""
    print_info "Next steps:"
    print_info "  1. Test binaries on target platforms"
    print_info "  2. Verify checksums"
    print_info "  3. Review README.txt"
    print_info "  4. Upload to GitHub releases or distribution server"
    echo ""
    print_info "Testing commands:"
    print_info "  Linux:   ${BUILD_DIR}/binaries/linux/rincoind --version"
    print_info "  Windows: Test ${BUILD_DIR}/binaries/windows/rincoind.exe on Windows"
}

# Run main function
main
