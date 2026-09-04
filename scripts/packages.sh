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
#
# ffmpeg is the CD tooling's hard dependency (see CD_PACKAGES). On Fedora the
# package to ask for is ffmpeg-free — the Fedora build, in the main repo. Plain
# `ffmpeg` there is the RPM Fusion build and pulls in a third-party repo we do
# not otherwise need; ffmpeg-free carries libmp3lame, which is the only encoder
# any of this needs. Debian and Arch just call it ffmpeg.
#
# normalize is `normalize-audio` on Debian.
DEBIAN_EXTRA=(python3-pynvim ffmpeg normalize-audio)
FEDORA_EXTRA=(python3-neovim tailscale ffmpeg-free normalize)
ARCH_EXTRA=(python-pynvim tailscale ffmpeg normalize)

# CD authoring and audio CLI tools, behind the bin/cd-* commands.
#
# Hard dependencies of those scripts — without these they refuse to run:
#   cdrskin  - the default burn engine (cd-burn, cd-mp3), and the media
#              preflight that tells a blank disc from a full one
#   cdrdao   - the gapless and CD-TEXT engine, driven by a generated .toc
#   xorriso  - builds the ISO 9660/Joliet image for cd-mp3 data discs
#   ffmpeg   - every decode, resample and peak scan in cd-prep (see above for
#              the package name, which is the one thing that differs by distro)
#
# Hand tools for the jobs the scripts do not cover — splitting a single album
# rip by its cue sheet, checking or re-gaining a file before staging it:
#   sox      - conversion, trimming and analysis from the shell
#   flac     - encode/decode and `flac -t` integrity checks on rips
#   shntool  - splits one long WAV/FLAC into tracks (shnsplit)
#   cuetools - reads and writes the cue sheets shnsplit splits on
#   normalize - batch peak/RMS gain across an album before cd-prep sees it
#
# Installed on every host, not gated on sway or a desktop: the point of having
# them here is that the workflow is identical on both machines.
CD_PACKAGES=(
    cdrskin
    cdrdao
    xorriso
    sox
    flac
    shntool
    cuetools
)

# Sway session extras. Everything our configs actually invoke, because none of
# it can be assumed present: on Fedora Sway Atomic these ship in the base image,
# but on a Plasma or GNOME install with sway added by hand none of them exist.
#
# This list got longer when the sway config stopped including
# /usr/share/sway/config.d. Those distro drop-ins came with their package
# dependencies; our replacements in config.d have to name them here instead.
#   foot          - terminal launched by config/sway/startup.sh
#   rofi          - $menu launcher bound in config/sway/config
#   waybar        - the bar, declared in config/sway/config
#   pavucontrol   - waybar's pulseaudio on-click handler
#   brightnessctl - screen and keyboard backlight keys in config.d/laptop.conf
#   swayidle      - the idle lock in config.d/10-lock.conf
#   swaylock      - what swayidle and the lid binding actually run
#   wireplumber   - provides wpctl, the volume keys in config.d/20-keys-media.conf
#   playerctl     - the media keys in config.d/20-keys-media.conf
#   grimshot      - the screenshot bindings in config/sway/config
#   xdg-user-dirs - provides xdg-user-dirs-update, run by config.d/40-autostart.conf
# swaymsg and swaynag come from sway itself, which must already be installed
# for this list to be used at all.
#
# grimshot is the one name here that is not universal — it is its own package on
# Fedora but lives in sway-contrib elsewhere. pm_install retries package by
# package on failure, so a miss costs a warning, not the rest of the list.
#
# No polkit agent is listed. Which one is right depends on the desktop the host
# already has (lxqt on the Sway spin, kde on Plasma) and installing the wrong
# one drags in half of another desktop; config/sway/polkit-agent.sh probes for
# whichever is present instead.
SWAY_PACKAGES=(
    foot
    rofi
    waybar
    pavucontrol
    brightnessctl
    swayidle
    swaylock
    wireplumber
    playerctl
    grimshot
    xdg-user-dirs
)

# Flatpak apps to install
FLATPAK_APPS=(
    "app.zen_browser.zen"
    "md.obsidian.Obsidian"
    "org.audacityteam.Audacity"
    "org.raspberrypi.rpi-imager"
    "com.obsproject.Studio"
)

# Final install list: base packages, the CD tooling, the sway extras when sway
# is present, and the per-distro names.
INSTALL_PACKAGES=("${COMMON_PACKAGES[@]}" "${CD_PACKAGES[@]}")
if command -v sway &> /dev/null; then
    INSTALL_PACKAGES+=("${SWAY_PACKAGES[@]}")
    # sway-config-fedora is deliberately NOT installed.
    #
    # It was added here to supply /usr/libexec/sway/layered-include, which the
    # old `include` line in config/sway/config depended on — without it the
    # include failed and nothing in config.d loaded. That include has since been
    # replaced with sway's native glob include, so the helper is no longer
    # needed by anything we ship.
    #
    # Installing it now would be actively harmful: it also drops
    # 60-bindings-brightness.conf, 60-bindings-volume.conf and 90-swayidle.conf
    # into /usr/share/sway/config.d, duplicating bindings config.d/laptop.conf
    # already owns and starting a second swayidle.
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
