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

# Detect distro family.
#
# Matching $ID exactly is too brittle: Fedora Asahi Remix reports an ID that is
# not a bare "fedora", which resolved to "unknown" and made packages.sh skip
# every install — including gcc, which then broke anything needing a compiler.
#
# Check $ID first, then fall back to each entry in $ID_LIKE, so downstream
# remixes and derivatives resolve to the family they are built on. Globs catch
# hyphenated IDs like "fedora-asahi-remix".
detect_distro() {
    [ -f /etc/os-release ] || { echo "unknown"; return; }
    . /etc/os-release

    local id
    for id in ${ID:-} ${ID_LIKE:-}; do
        case "$id" in
            ubuntu*|debian*|pop*|linuxmint*|raspbian*|elementary*)
                echo "debian"; return ;;
            fedora*|rhel*|centos*|rocky*|alma*|nobara*)
                echo "fedora"; return ;;
            arch*|manjaro*|endeavouros*|cachyos*|garuda*)
                echo "arch";   return ;;
        esac
    done

    echo "unknown"
}

# Detect CPU architecture, normalised to the spellings upstream projects use.
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *)             echo "unknown" ;;
    esac
}

# Is this host a laptop? Answered by asking whether any power supply is a
# battery.
#
# Do NOT glob for /sys/class/power_supply/BAT* — "BAT0" is an ACPI naming
# convention, not a kernel guarantee. Apple Silicon exposes the battery through
# the SMC driver as "macsmc-battery", so a BAT* glob reports "no battery" on a
# MacBook and silently skips laptop.conf, leaving the brightness keys, lid
# switch, idle lock and touchpad settings all dead. Same class of bug as the
# $ID matching above: a portable check written against one vendor's spelling.
#
# Reading */type and matching "Battery" is naming-independent — it is the
# documented power_supply class ABI, and it also excludes the AC adapter and
# the USB-C PD controllers, which sit in the same directory.
#
# But type alone is not enough, and the failure runs the other way. A wireless
# peripheral reports its own charge through the same class: a Logitech mouse
# shows up as "hidpp_battery_0" with type "Battery", so a desktop with a
# Logitech receiver was detected as a laptop and got laptop.conf — caps remapped
# to ctrl, touchpad settings, a lid binding. Worse, those batteries appear and
# vanish as the device sleeps and wakes, so the answer changed between runs of
# the same script.
#
# `scope` is the discriminator: "Device" means the battery powers that
# peripheral, "System" means it powers the machine. It is optional in the ABI,
# so a missing scope counts as a system battery — that is the conservative
# reading, and it is what the Apple SMC battery does.
has_battery() {
    local type_file scope_file
    for type_file in /sys/class/power_supply/*/type; do
        [ -r "$type_file" ] || continue
        [ "$(cat "$type_file")" = "Battery" ] || continue

        scope_file="${type_file%/type}/scope"
        [ -r "$scope_file" ] && [ "$(cat "$scope_file")" = "Device" ] && continue

        return 0
    done
    return 1
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
