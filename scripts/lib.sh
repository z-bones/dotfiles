#!/usr/bin/env bash
# Shared helpers: output formatting plus distro/arch/package-manager detection.
#
# install.sh sources this once and exports the results. The individual scripts
# source it too, so `make packages` / `make tools` / `make symlinks` work
# standalone instead of depending on install.sh's shell scope.
#
# Guarded against double-sourcing.
[ -n "${DOTFILES_LIB_LOADED:-}" ] && return 0
DOTFILES_LIB_LOADED=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header()  { echo -e "\n${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }

# Detect distro family
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint)   echo "debian" ;;
            fedora|rhel|centos|rocky|alma) echo "fedora" ;;
            arch|manjaro|endeavouros)      echo "arch"   ;;
            *)                             echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

# Detect CPU architecture, normalised to the spellings upstream projects use.
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *)             echo "unknown" ;;
    esac
}

# Detect Fedora package manager (rpm-ostree for immutable, dnf5/dnf otherwise)
detect_fedora_pkg_mgr() {
    if command -v rpm-ostree &> /dev/null && rpm-ostree status &> /dev/null; then
        echo "rpm-ostree"
    elif command -v dnf5 &> /dev/null; then
        echo "dnf5"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    else
        echo "unknown"
    fi
}

# Populate the globals the scripts read. Cheap enough to always run.
DISTRO="${DISTRO:-$(detect_distro)}"
ARCH="${ARCH:-$(detect_arch)}"

# Vendor-specific spellings of $ARCH, so callers don't re-derive them:
# AWS wants "aarch64"; Cursor/Adoptium want "arm64"/"x64"; Debian and
# Supabase want "arm64"/"amd64".
if [ "$ARCH" = "aarch64" ]; then
    ARCH_ALT="arm64"
    ARCH_DEB="arm64"
else
    ARCH_ALT="x64"
    ARCH_DEB="amd64"
fi

export DISTRO ARCH ARCH_ALT ARCH_DEB
