#!/usr/bin/env bash
# Package installation script - supports Debian/Ubuntu and Fedora

set -euo pipefail

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
)

# Flatpak apps to install
FLATPAK_APPS=(
    "com.brave.Browser"
    "md.obsidian.Obsidian"
    "org.localsend.localsend_app"
    "org.audacityteam.Audacity"
)

install_debian() {
    print_header "Installing packages via apt..."
    sudo apt update
    sudo apt install -y "${COMMON_PACKAGES[@]}" build-essential flatpak

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
            sudo rpm-ostree install -y --allow-inactive --idempotent "${COMMON_PACKAGES[@]}"
            print_warning "System packages will be available after reboot"
            ;;
        dnf5)
            sudo dnf5 install -y "${COMMON_PACKAGES[@]}" @development-tools flatpak
            ;;
        dnf)
            sudo dnf install -y "${COMMON_PACKAGES[@]}" @development-tools flatpak
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
    sudo pacman -Syu --noconfirm "${COMMON_PACKAGES[@]}" base-devel flatpak

    if ! flatpak remotes | grep -q flathub; then
        print_header "Adding Flathub repository..."
        sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
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

install_flatpaks

print_success "Package installation complete"
