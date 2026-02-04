#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DOTFILES_DIR="$HOME/.dotfiles"
REPO_URL="https://github.com/z-bones/dotfiles.git"

print_header() {
    echo -e "\n${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Detect distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint)
                echo "debian"
                ;;
            fedora|rhel|centos|rocky|alma)
                echo "fedora"
                ;;
            arch|manjaro|endeavouros)
                echo "arch"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

# Detect Fedora package manager (rpm-ostree for immutable, dnf5/dnf for traditional)
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

DISTRO=$(detect_distro)

print_header "Dotfiles Bootstrap"
echo "Detected distro family: $DISTRO"

# Bootstrap: install git and curl if missing
bootstrap_deps() {
    local missing=()
    for cmd in git curl; do
        command -v $cmd &> /dev/null || missing+=("$cmd")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    print_header "Installing bootstrap dependencies: ${missing[*]}"
    case "$DISTRO" in
        debian)
            sudo apt update
            sudo apt install -y "${missing[@]}"
            ;;
        fedora)
            case "$(detect_fedora_pkg_mgr)" in
                rpm-ostree)
                    sudo rpm-ostree install -y --allow-inactive "${missing[@]}"
                    print_warning "Reboot required for changes to take effect"
                    ;;
                dnf5)
                    sudo dnf5 install -y "${missing[@]}"
                    ;;
                dnf)
                    sudo dnf install -y "${missing[@]}"
                    ;;
                *)
                    print_error "No supported package manager found (dnf, dnf5, or rpm-ostree)"
                    exit 1
                    ;;
            esac
            ;;
        arch)
            sudo pacman -Sy --noconfirm "${missing[@]}"
            ;;
        *)
            print_error "Unknown distro. Please install manually: ${missing[*]}"
            exit 1
            ;;
    esac
}

bootstrap_deps

# Determine dotfiles location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If running from the dotfiles repo itself, use that location
if [ -f "$SCRIPT_DIR/Makefile" ] && [ -d "$SCRIPT_DIR/scripts" ]; then
    DOTFILES_DIR="$SCRIPT_DIR"
    print_success "Running from local dotfiles: $DOTFILES_DIR"
elif [ -d "$DOTFILES_DIR" ]; then
    print_header "Updating dotfiles..."
    cd "$DOTFILES_DIR"
    git pull --ff-only || print_warning "Could not update (offline or not a git repo)"
else
    print_header "Cloning dotfiles..."
    git clone "$REPO_URL" "$DOTFILES_DIR"
    cd "$DOTFILES_DIR"
fi

# Run install scripts
print_header "Installing packages..."
source "$DOTFILES_DIR/scripts/packages.sh"

print_header "Installing development tools..."
source "$DOTFILES_DIR/scripts/tools.sh"

print_header "Creating symlinks..."
source "$DOTFILES_DIR/scripts/symlinks.sh"

# Secrets (optional, interactive)
# Check USB media for secrets file
find_usb_secrets() {
    local usb_paths=(
        "/media/$USER"
        "/run/media/$USER"
        "/mnt"
    )
    for base in "${usb_paths[@]}"; do
        if [ -d "$base" ]; then
            for drive in "$base"/*; do
                if [ -f "$drive/secrets.tar.gpg" ]; then
                    echo "$drive/secrets.tar.gpg"
                    return 0
                fi
            done
        fi
    done
    return 1
}

USB_SECRETS=$(find_usb_secrets || true)
if [ -n "$USB_SECRETS" ]; then
    print_success "Found secrets on USB: $USB_SECRETS"
    mkdir -p "$DOTFILES_DIR/secrets"
    cp "$USB_SECRETS" "$DOTFILES_DIR/secrets/secrets.tar.gpg"
fi

if [ -f "$DOTFILES_DIR/secrets/secrets.tar.gpg" ]; then
    echo ""
    read -p "Decrypt and install secrets? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_header "Decrypting secrets..."
        source "$DOTFILES_DIR/scripts/secrets.sh" decrypt
    fi
fi

# Set zsh as default shell
if command -v zsh &> /dev/null; then
    ZSH_PATH=$(which zsh)
    if [ "$SHELL" != "$ZSH_PATH" ]; then
        print_header "Setting zsh as default shell..."
        if ! grep -q "$ZSH_PATH" /etc/shells; then
            echo "$ZSH_PATH" | sudo tee -a /etc/shells
        fi
        chsh -s "$ZSH_PATH"
        print_success "Default shell changed to zsh (restart terminal to apply)"
    fi
fi

# Summary
echo ""
print_header "Installation complete!"
echo ""
print_success "Configs installed"
print_success "Development tools ready"
echo ""
print_warning "Manual steps remaining:"
echo "  1. Download DaVinci Resolve from https://www.blackmagicdesign.com/products/davinciresolve"
echo "  2. Restart your terminal or run: exec zsh"
echo ""
