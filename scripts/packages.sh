#!/usr/bin/env bash
# Package installation script - supports Debian/Ubuntu and Fedora

set -euo pipefail

# Shared helpers + detection. Sourced from install.sh (already loaded, no-op) or
# run standalone via `make`.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Base packages needed on all distros
COMMON_PACKAGES=(
    zsh
    git
    curl
    wget
    gpg
    unzip
    gcc
    make
    htop
    tree
    tmux
    pass
    neovim
    podman-compose
)

# Packages whose names differ by distro, or that not every distro carries.
# Neovim's Python provider is python3-neovim on Fedora, python3-pynvim on
# Debian and python-pynvim on Arch. Tailscale is in Fedora's and Arch's own
# repos but needs pkgs.tailscale.com on Debian, so it is omitted there.
DEBIAN_EXTRA=(python3-pynvim)
FEDORA_EXTRA=(python3-neovim tailscale)
ARCH_EXTRA=(python-pynvim tailscale)

# Sway session extras. Referenced by config.d/laptop.conf (brightness keys,
# idle-lock) and by the volume bindings, so install them wherever sway runs.
# Sway session extras. Everything our configs actually invoke, because none of
# it can be assumed present: on Fedora Sway Atomic these ship in the base image,
# but on a GNOME install with sway added by hand none of them exist.
#   foot        - terminal launched by config/sway/startup.sh
#   rofi        - $menu launcher bound in config/sway/config
#   waybar      - the bar, launched by config.d/90-bar.conf
#   pavucontrol - waybar's pulseaudio on-click handler
#   wireplumber - provides wpctl, used by the volume keys in laptop.conf
# swaymsg and swaynag come from sway itself, which must already be installed
# for this list to be used at all.
SWAY_PACKAGES=(
    foot
    rofi
    waybar
    pavucontrol
    brightnessctl
    swayidle
    swaylock
    wireplumber
)

# Flatpak apps to install
FLATPAK_APPS=(
    "app.zen_browser.zen"
    "md.obsidian.Obsidian"
    "org.audacityteam.Audacity"
    "org.raspberrypi.rpi-imager"
    "com.obsproject.Studio"
)

# Final install list: base packages, the sway extras when sway is present, and
# the per-distro names.
INSTALL_PACKAGES=("${COMMON_PACKAGES[@]}")
if command -v sway &> /dev/null; then
    INSTALL_PACKAGES+=("${SWAY_PACKAGES[@]}")
    # Our sway config's `include` line calls /usr/libexec/sway/layered-include,
    # which is owned by sway-config-fedora — and `sway` does not depend on it,
    # not even a Recommends. Without it the include fails and NOTHING in
    # config.d loads: no bar, no laptop.conf. It ships in the Fedora Sway spin,
    # so this only bites when sway is added by hand to another spin.
    [ "${DISTRO:-}" = "fedora" ] && INSTALL_PACKAGES+=(sway-config-fedora)
fi
case "${DISTRO:-unknown}" in
    debian) INSTALL_PACKAGES+=("${DEBIAN_EXTRA[@]}") ;;
    fedora) INSTALL_PACKAGES+=("${FEDORA_EXTRA[@]}") ;;
    arch)   INSTALL_PACKAGES+=("${ARCH_EXTRA[@]}")   ;;
esac

# Run the package manager over a list, tolerating individual failures.
#
# dnf, apt and pacman all fail the *entire* transaction when one name is
# unknown for the distro or arch. Under `set -e` that aborted the whole run and
# left nothing installed — one unavailable package could silently cost you
# every other one. Try the batch first (fast path), and only on failure retry
# one at a time so a single bad name cannot block the rest.
PM_CMD=()
pm_install() {
    local pkgs=("$@")
    [ ${#pkgs[@]} -eq 0 ] && return 0

    if "${PM_CMD[@]}" "${pkgs[@]}"; then
        return 0
    fi

    print_warning "Batch install failed — retrying package by package"
    local failed=() p
    for p in "${pkgs[@]}"; do
        "${PM_CMD[@]}" "$p" || failed+=("$p")
    done
    if [ ${#failed[@]} -gt 0 ]; then
        print_warning "Could not install: ${failed[*]}"
    fi
    return 0
}

install_debian() {
    print_header "Installing packages via apt..."
    sudo apt update
    PM_CMD=(sudo apt install -y)
    pm_install "${INSTALL_PACKAGES[@]}" build-essential flatpak

    # Add Flathub if not present
    if ! flatpak remotes | grep -q flathub; then
        print_header "Adding Flathub repository..."
        sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
}

install_fedora() {
    local pkg_mgr
    pkg_mgr=$(detect_fedora_pkg_mgr)
    print_header "Installing packages via $pkg_mgr..."

    case "$pkg_mgr" in
        rpm-ostree)
            # rpm-ostree doesn't support groups like @development-tools
            # flatpak is pre-installed on immutable Fedora
            PM_CMD=(sudo rpm-ostree install -y --allow-inactive --idempotent)
            pm_install "${INSTALL_PACKAGES[@]}"
            print_warning "System packages will be available after reboot"
            ;;
        dnf5)
            PM_CMD=(sudo dnf5 install -y)
            pm_install "${INSTALL_PACKAGES[@]}"
            pm_install @development-tools flatpak
            ;;
        dnf)
            PM_CMD=(sudo dnf install -y)
            pm_install "${INSTALL_PACKAGES[@]}"
            pm_install @development-tools flatpak
            ;;
        *)
            print_error "No supported package manager found"
            return 1
            ;;
    esac

    # Flathub should be available by default on Fedora, but ensure it's there
    if ! flatpak remotes | grep -q flathub; then
        print_header "Adding Flathub repository..."
        sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
}

install_arch() {
    print_header "Installing packages via pacman..."
    sudo pacman -Sy --noconfirm
    PM_CMD=(sudo pacman -S --noconfirm --needed)
    pm_install "${INSTALL_PACKAGES[@]}" base-devel flatpak

    if ! flatpak remotes | grep -q flathub; then
        print_header "Adding Flathub repository..."
        sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
}

# Tailscale ships tailscaled.service but leaves it disabled. Enable it if the
# unit is actually present — on rpm-ostree the package only materialises after a
# reboot, so this is a no-op until then. Logging in stays manual: `tailscale up`
# opens a browser for auth and shouldn't run unattended.
setup_tailscale() {
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
        return 0
    fi
    if ! systemctl cat tailscaled.service &> /dev/null; then
        print_warning "tailscaled.service not found — reboot first on atomic hosts, then: make packages"
        return 0
    fi

    if systemctl is-enabled --quiet tailscaled 2>/dev/null; then
        print_success "tailscaled already enabled"
    else
        print_header "Enabling tailscaled..."
        sudo systemctl enable --now tailscaled || {
            print_warning "Could not enable tailscaled"
            return 0
        }
    fi

    if tailscale status &> /dev/null; then
        print_success "Tailscale connected"
    else
        print_warning "Tailscale not logged in — run: sudo tailscale up"
    fi
}

install_flatpaks() {
    # Skip if flatpak not available or not functional (e.g., in containers)
    if ! command -v flatpak &> /dev/null; then
        print_warning "Flatpak not available, skipping app installation"
        return 0
    fi

    # Test if flatpak is functional (fails in Docker due to namespace restrictions)
    if ! flatpak --version &> /dev/null; then
        print_warning "Flatpak not functional (container?), skipping app installation"
        return 0
    fi

    print_header "Installing Flatpak applications..."
    for app in "${FLATPAK_APPS[@]}"; do
        if ! flatpak list 2>/dev/null | grep -q "$app"; then
            echo "Installing $app..."
            flatpak install -y flathub "$app" 2>&1 || print_warning "Failed to install $app"
        else
            print_success "$app already installed"
        fi
    done
}

# Main
case "${DISTRO:-unknown}" in
    debian)
        install_debian
        ;;
    fedora)
        install_fedora
        ;;
    arch)
        install_arch
        ;;
    *)
        print_error "Unsupported distro: $DISTRO"
        print_warning "Please install packages manually: ${COMMON_PACKAGES[*]}"
        ;;
esac

setup_tailscale
install_flatpaks

print_success "Package installation complete"
