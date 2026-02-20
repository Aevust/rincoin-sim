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
CLEAN_IMAGES=false
LOCAL_BUILD=false
if [ -z "$1" ]; then
    echo -e "${RED}Error: Version tag or --local is required${NC}"
    echo "Usage: $0 <git-tag|--local> [git-url] [--clean] [--clean-all]"
    echo "Example: $0 v1.0.1"
    echo "Example: $0 v1.0.1 https://github.com/Rin-coin/rincoin.git --clean"
    echo "Example: $0 --local --clean-all"
    exit 1
fi

# Check for --local flag
if [ "$1" == "--local" ]; then
    LOCAL_BUILD=true
    GIT_TAG="local"
    shift
else
    GIT_TAG="${1}"
    shift
fi

# Parse optional arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --clean-all)
            CLEAN_BUILD=true
            CLEAN_IMAGES=true
            shift
            ;;
        --local)
            LOCAL_BUILD=true
            GIT_TAG="local"
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
if [ "$LOCAL_BUILD" = "true" ]; then
    VERSION="local"
else
    VERSION="${GIT_TAG#v}"  # Remove 'v' prefix if present
fi

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
if [ "$LOCAL_BUILD" = "true" ]; then
    echo -e "${BLUE}Build Mode:${NC} Local (current directory)"
    echo -e "${BLUE}Version:${NC} ${VERSION}"
else
    echo -e "${BLUE}Git Tag:${NC} ${GIT_TAG}"
    echo -e "${BLUE}Version:${NC} ${VERSION}"
    echo -e "${BLUE}Git URL:${NC} ${GIT_URL}"
fi
echo -e "${BLUE}Clean Caches:${NC} ${CLEAN_BUILD}"
echo -e "${BLUE}Clean Images:${NC} ${CLEAN_IMAGES}"
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
    local exit_code=$?
    if [ -d "$TEMP_DIR" ]; then
        if [ $exit_code -eq 0 ]; then
            print_info "Cleaning up temporary directory..."
            rm -rf "$TEMP_DIR"
        else
            print_error "Build failed. Temporary directory preserved for debugging: $TEMP_DIR"
        fi
    fi
}

# Clean cache if requested
clean_cache() {
    if [ "$CLEAN_BUILD" = "true" ]; then
        print_info "Cleaning build caches..."
        if [ -d "$CACHE_DIR" ]; then
            rm -rf "$CACHE_DIR"
            print_info "Build cache removed: ${CACHE_DIR}"
        fi
    fi
    
    if [ "$CLEAN_IMAGES" = "true" ]; then
        print_info "Cleaning Docker images..."
        docker rmi rincoin-builder:linux-ubuntu20 2>/dev/null || true
        docker rmi rincoin-builder:linux-ubuntu24 2>/dev/null || true
        docker rmi rincoin-builder:windows 2>/dev/null || true
        print_info "Docker images removed"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Clone repository and checkout version (or copy local)
clone_and_checkout() {
    print_info "======================================"
    if [ "$LOCAL_BUILD" = "true" ]; then
        print_info "Copying Local Source"
    else
        print_info "Cloning Repository"
    fi
    print_info "======================================"
    
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    if [ "$LOCAL_BUILD" = "true" ]; then
        print_info "Copying from: ${PROJECT_ROOT}"
        
        # Use git-aware copy for efficiency (only tracked files, respects .gitignore)
        cd "${PROJECT_ROOT}"
        if [ -d ".git" ] && command -v rsync &> /dev/null; then
            print_info "Using git-aware smart copy (tracked files only)..."
            mkdir -p "${SOURCE_DIR}"
            
            # Get all tracked files (respects .gitignore automatically)
            # Use --ignore-missing-args to skip deleted files that are still in git index
            git ls-files -z | rsync -a --ignore-missing-args --files-from=- --from0 "${PROJECT_ROOT}/" "${SOURCE_DIR}/"
            
            # Also copy untracked files that are not ignored (e.g., new files)
            git ls-files --others --exclude-standard -z | rsync -a --ignore-missing-args --files-from=- --from0 "${PROJECT_ROOT}/" "${SOURCE_DIR}/" 2>/dev/null || true
            
            # Copy .git directory for version info
            if [ -d "${PROJECT_ROOT}/.git" ]; then
                cp -r "${PROJECT_ROOT}/.git" "${SOURCE_DIR}/.git"
            fi
            
            print_info "Smart copy completed (source files only, ignoring build artifacts)"
        else
            # Fallback to full copy if git or rsync not available
            print_info "Using full directory copy..."
            cp -r "${PROJECT_ROOT}" "${SOURCE_DIR}"
            
            # Clean up build artifacts and cache from copied source
            print_info "Removing build artifacts..."
            rm -rf "${SOURCE_DIR}/release-builds"
            rm -rf "${SOURCE_DIR}/.build-cache"
            rm -rf "${SOURCE_DIR}/depends/built"
            rm -rf "${SOURCE_DIR}/depends/work"
            
            # Clean Qt-generated files to avoid MOC version conflicts
            find "${SOURCE_DIR}/src/qt" -name "moc_*.cpp" -delete 2>/dev/null || true
            find "${SOURCE_DIR}/src/qt" -name "*.moc" -delete 2>/dev/null || true
            find "${SOURCE_DIR}/src/qt" -name "qrc_*.cpp" -delete 2>/dev/null || true
            find "${SOURCE_DIR}/src/qt" -name "ui_*.h" -delete 2>/dev/null || true
            find "${SOURCE_DIR}/src/qt/forms" -name "ui_*.h" -delete 2>/dev/null || true
            
            # Clean all compiled object files and libraries
            find "${SOURCE_DIR}" -name "*.o" -delete 2>/dev/null || true
            find "${SOURCE_DIR}" -name "*.a" -delete 2>/dev/null || true
            find "${SOURCE_DIR}" -name "*.la" -delete 2>/dev/null || true
            find "${SOURCE_DIR}" -name "*.lo" -delete 2>/dev/null || true
            find "${SOURCE_DIR}" -name "*.so" -delete 2>/dev/null || true
            find "${SOURCE_DIR}" -name "*.dylib" -delete 2>/dev/null || true
            
            # Clean autotools-generated files
            rm -f "${SOURCE_DIR}/Makefile" 2>/dev/null || true
            rm -f "${SOURCE_DIR}/src/Makefile" 2>/dev/null || true
            rm -f "${SOURCE_DIR}/config.status" 2>/dev/null || true
            rm -rf "${SOURCE_DIR}/src/.deps" 2>/dev/null || true
            rm -rf "${SOURCE_DIR}/src/.libs" 2>/dev/null || true
        fi
        
        cd "$SOURCE_DIR"
        if [ -d ".git" ]; then
            local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
            local commit_date=$(git log -1 --format=%cd --date=short 2>/dev/null || echo "unknown")
            print_info "Source: local working directory"
            print_info "Commit: ${commit_hash}"
            print_info "Date: ${commit_date}"
        else
            print_info "Source: local working directory (no git info)"
        fi
    else
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
    fi
}

# Create source packages
create_source_packages() {
    if [ "$LOCAL_BUILD" = "true" ]; then
        print_info "================================================"
        print_info "Skipping source package creation for local build"
        print_info "================================================"
        return
    fi

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
        print_error "Docker is not running or a group is missing. Please start Docker first and make sure you are in the docker group."
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
    mkdir -p "${BUILD_DIR}/binaries/linux-ubuntu20"
    mkdir -p "${BUILD_DIR}/binaries/linux-ubuntu24"
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

# Build Linux binaries (Ubuntu 20.04 - Maximum Compatibility)
build_linux_ubuntu20_binaries() {
    print_info "======================================"
    print_info "Building Linux Binaries (Ubuntu 20.04)"
    print_info "Maximum Compatibility: Ubuntu 18.04+"
    print_info "======================================"
    
    local dockerfile="${BUILD_DIR}/Dockerfile.linux-ubuntu20"
    local image_name="rincoin-builder:linux-ubuntu20"
    
    # Check if image already exists
    if docker image inspect "$image_name" >/dev/null 2>&1; then
        print_info "Using existing Docker image: $image_name"
        print_info "(Use --clean-all flag to rebuild Docker images)"
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
    cmake \
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
    curl \
    wget \
    ca-certificates \
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
            
            # Setup depends cache directories
            mkdir -p depends/sources depends/built
            
            # Link cache directories (if they have content, use them)
            if [ -d "/depends_sources_cache" ]; then
                cp -r /depends_sources_cache/* depends/sources/ 2>/dev/null || true
            fi
            
            if [ -d "/depends_built_cache" ]; then
                cp -r /depends_built_cache/* depends/built/ 2>/dev/null || true
            fi
            
            # Build dependencies for Linux (this creates static builds)
            cd depends
            make -j$(nproc) HOST=x86_64-pc-linux-gnu
            
            # Copy back to cache for next build
            cp -r sources/* /depends_sources_cache/ 2>/dev/null || true
            cp -r built/* /depends_built_cache/ 2>/dev/null || true
            
            cd ..
            
            ./autogen.sh
            
            # Use depends-built libraries (all static)
            CONFIG_SITE=$PWD/depends/x86_64-pc-linux-gnu/share/config.site ./configure \
                BDB_LIBS="-L/db4/lib -ldb_cxx-4.8" \
                BDB_CFLAGS="-I/db4/include" \
                --prefix=/ \
                --disable-tests \
                --disable-bench \
                --enable-reduce-exports \
                --with-incompatible-bdb=no
            
            make -j$(nproc)
            strip src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet src/qt/rincoin-qt || true
            
            echo "=== Linux binary sizes after stripping ==="
            ls -lh src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet src/qt/rincoin-qt
            
            echo "=== Checking Linux binary dependencies ==="
            ldd src/rincoind || echo "Static binary (no dependencies)"
            
            # Copy binaries
            cp src/rincoind /output/binaries/linux-ubuntu20/
            cp src/rincoin-cli /output/binaries/linux-ubuntu20/
            cp src/rincoin-tx /output/binaries/linux-ubuntu20/
            cp src/rincoin-wallet /output/binaries/linux-ubuntu20/
            cp src/qt/rincoin-qt /output/binaries/linux-ubuntu20/
            
            # Create tarball
            mkdir -p /tmp/rincoin-'"${VERSION}"'/bin
            cp src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet src/qt/rincoin-qt /tmp/rincoin-'"${VERSION}"'/bin/
            cd /tmp
            tar czf /output/tarballs/rincoin-'"${VERSION}"'-x86_64-linux-gnu.tar.gz rincoin-'"${VERSION}"'/
        ' || {
        print_error "Linux Ubuntu 20.04 build failed"
        
        # Copy config.log for debugging
        if [ -f "${SOURCE_DIR}/config.log" ]; then
            print_info "Copying config.log to ${BUILD_DIR}/config.log.linux-ubuntu20"
            cp "${SOURCE_DIR}/config.log" "${BUILD_DIR}/config.log.linux-ubuntu20"
            print_info "Check ${BUILD_DIR}/config.log.linux-ubuntu20 for details"
        fi
        
        return 1
    }
    
    print_info "Linux Ubuntu 20.04 binaries built successfully!"
}

# Build Linux binaries (Ubuntu 24.04 - Modern Performance)
build_linux_ubuntu24_binaries() {
    print_info "======================================"
    print_info "Building Linux Binaries (Ubuntu 24.04)"
    print_info "Modern Performance: Ubuntu 24.04+"
    print_info "======================================"
    
    local dockerfile="${BUILD_DIR}/Dockerfile.linux-ubuntu24"
    local image_name="rincoin-builder:linux-ubuntu24"
    
    # Check if image already exists
    if docker image inspect "$image_name" >/dev/null 2>&1; then
        print_info "Using existing Docker image: $image_name"
        print_info "(Use --clean-all flag to rebuild Docker images)"
    else
        print_info "Building new Docker image..."
    
    cat > "$dockerfile" << 'DOCKERFILE_END'
FROM ubuntu:24.04

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
    cmake \
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
    curl \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
DOCKERFILE_END

        docker build -t "$image_name" -f "$dockerfile" "${BUILD_DIR}" || {
            print_error "Failed to build Linux Ubuntu 24.04 Docker image"
            return 1
        }
    fi
    
    print_info "Compiling Rincoin for Linux (Ubuntu 24.04)..."
    
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
            
            # Setup depends cache directories
            mkdir -p depends/sources depends/built
            
            # Link cache directories (if they have content, use them)
            if [ -d "/depends_sources_cache" ]; then
                cp -r /depends_sources_cache/* depends/sources/ 2>/dev/null || true
            fi
            
            if [ -d "/depends_built_cache" ]; then
                cp -r /depends_built_cache/* depends/built/ 2>/dev/null || true
            fi
            
            # Build dependencies for Linux (this creates static builds)
            cd depends
            make -j$(nproc) HOST=x86_64-pc-linux-gnu
            
            # Copy back to cache for next build
            cp -r sources/* /depends_sources_cache/ 2>/dev/null || true
            cp -r built/* /depends_built_cache/ 2>/dev/null || true
            
            cd ..
            
            ./autogen.sh
            
            # Use depends-built libraries (all static)
            CONFIG_SITE=$PWD/depends/x86_64-pc-linux-gnu/share/config.site ./configure \
                BDB_LIBS="-L/db4/lib -ldb_cxx-4.8" \
                BDB_CFLAGS="-I/db4/include" \
                --prefix=/ \
                --disable-tests \
                --disable-bench \
                --enable-reduce-exports \
                --with-incompatible-bdb=no
            
            make -j$(nproc)
            strip src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet src/qt/rincoin-qt || true
            
            echo "=== Linux binary sizes after stripping ==="
            ls -lh src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet src/qt/rincoin-qt
            
            echo "=== Checking Linux binary dependencies ==="
            ldd src/rincoind || echo "Static binary (no dependencies)"
            
            # Copy binaries
            cp src/rincoind /output/binaries/linux-ubuntu24/
            cp src/rincoin-cli /output/binaries/linux-ubuntu24/
            cp src/rincoin-tx /output/binaries/linux-ubuntu24/
            cp src/rincoin-wallet /output/binaries/linux-ubuntu24/
            cp src/qt/rincoin-qt /output/binaries/linux-ubuntu24/
            
            # Create tarball
            mkdir -p /tmp/rincoin-'"${VERSION}"'/bin
            cp src/rincoind src/rincoin-cli src/rincoin-tx src/rincoin-wallet src/qt/rincoin-qt /tmp/rincoin-'"${VERSION}"'/bin/
            cd /tmp
            tar czf /output/tarballs/rincoin-'"${VERSION}"'-x86_64-linux-gnu-ubuntu24.tar.gz rincoin-'"${VERSION}"'/
        ' || {
        print_error "Linux Ubuntu 24.04 build failed"
        
        # Copy config.log for debugging
        if [ -f "${SOURCE_DIR}/config.log" ]; then
            print_info "Copying config.log to ${BUILD_DIR}/config.log.linux-ubuntu24"
            cp "${SOURCE_DIR}/config.log" "${BUILD_DIR}/config.log.linux-ubuntu24"
            print_info "Check ${BUILD_DIR}/config.log.linux-ubuntu24 for details"
        fi
        
        return 1
    }
    
    print_info "Linux Ubuntu 24.04 binaries built successfully!"
}

# Build Windows binaries (on Ubuntu 24.04 for faster builds)
build_windows_binaries() {
    print_info "======================================"
    print_info "Building Windows Binaries (Win10 x64+)"
    print_info "Cross-compiled on Ubuntu 24.04"
    print_info "======================================"
    
    local dockerfile="${BUILD_DIR}/Dockerfile.windows"
    local image_name="rincoin-builder:windows"
    
    # Check if image already exists
    if docker image inspect "$image_name" >/dev/null 2>&1; then
        print_info "Using existing Docker image: $image_name"
        print_info "(Use --clean-all flag to rebuild Docker images)"
    else
        print_info "Building new Docker image..."
    
    cat > "$dockerfile" << 'DOCKERFILE_END'
FROM ubuntu:24.04

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
    wget \
    ca-certificates \
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
            
            # Strip Windows binaries and show sizes
            echo "=== Stripping Windows binaries ==="
            x86_64-w64-mingw32-strip --strip-all src/rincoind.exe src/rincoin-cli.exe src/rincoin-tx.exe src/rincoin-wallet.exe src/qt/rincoin-qt.exe || true
            
            echo "=== Windows binary sizes after stripping ==="
            ls -lh src/rincoind.exe src/rincoin-cli.exe src/rincoin-tx.exe src/rincoin-wallet.exe src/qt/rincoin-qt.exe
            
            echo "=== Checking Windows binary dependencies ==="
            x86_64-w64-mingw32-objdump -x src/rincoind.exe | grep "DLL Name:" || echo "No DLL dependencies found (fully static)"
            
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
        
        # Copy config.log for debugging
        if [ -f "${SOURCE_DIR}/config.log" ]; then
            print_info "Copying config.log to ${BUILD_DIR}/config.log.windows"
            cp "${SOURCE_DIR}/config.log" "${BUILD_DIR}/config.log.windows"
            print_info "Check ${BUILD_DIR}/config.log.windows for details"
        fi
        
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
    cd ../binaries/linux-ubuntu20
    sha256sum * > SHA256SUMS.txt 2>/dev/null || true
    
    cd ../linux-ubuntu24
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
    build_linux_ubuntu20_binaries
    build_linux_ubuntu24_binaries
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
    print_info "  - source/                 : Source code archives"
    print_info "  - binaries/linux-ubuntu20/: Linux binaries (Ubuntu 18.04+, max compatibility)"
    print_info "  - binaries/linux-ubuntu24/: Linux binaries (Ubuntu 24.04+, modern performance)"
    print_info "  - binaries/windows/       : Windows binaries (Windows 10+)"
    print_info "  - tarballs/               : Distribution archives"
    print_info "  - README.txt              : Release documentation"
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
