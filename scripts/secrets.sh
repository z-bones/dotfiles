#!/usr/bin/env bash
# Secrets management - encrypt/decrypt sensitive files with GPG

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
SECRETS_DIR="$DOTFILES_DIR/secrets"
SECRETS_ARCHIVE="$SECRETS_DIR/secrets.tar.gpg"
TEMP_TAR="/tmp/secrets.tar.$$"

# Files/directories to include in secrets
SECRETS_SOURCES=(
    "$HOME/.ssh"
    "$HOME/.gnupg"
)

# Optional files (only include if they exist)
OPTIONAL_SECRETS=(
    "$HOME/.env"
    "$HOME/.netrc"
    "$HOME/.npmrc"
    "$HOME/.vercel"                       # macOS
    "$HOME/.local/share/com.vercel.cli"   # Linux (XDG)
    "$HOME/.supabase"
    "$HOME/.aws"
    "$HOME/.config/gh"
    "$HOME/.claude"
)

encrypt_secrets() {
    print_header "Encrypting secrets..."

    # Build list of files to archive
    local files_to_archive=()

    for src in "${SECRETS_SOURCES[@]}"; do
        if [ -e "$src" ]; then
            files_to_archive+=("$src")
        else
            print_warning "Skipping $src (not found)"
        fi
    done

    for src in "${OPTIONAL_SECRETS[@]}"; do
        if [ -e "$src" ]; then
            files_to_archive+=("$src")
            print_success "Including optional: $src"
        fi
    done

    if [ ${#files_to_archive[@]} -eq 0 ]; then
        print_error "No secrets found to encrypt"
        exit 1
    fi

    # Create archive (exclude sockets, runtime artifacts, and ephemeral data)
    echo "Creating archive..."
    tar -cvf "$TEMP_TAR" -C "$HOME" \
        --ignore-failed-read \
        --exclude='S.gpg-agent*' \
        --exclude='*.lock' \
        --exclude='*.sock' \
        --exclude='.gnupg/crls.d' \
        --exclude='.claude/debug' \
        --exclude='.claude/statsig' \
        --exclude='.claude/telemetry' \
        --exclude='.claude/todos' \
        --exclude='.claude/shell-snapshots' \
        --exclude='.claude/session-env' \
        --exclude='.claude/file-history' \
        --exclude='.claude/ide' \
        --exclude='.claude/cache' \
        $(for f in "${files_to_archive[@]}"; do echo "${f#$HOME/}"; done)

    # Encrypt with GPG (symmetric)
    echo ""
    echo "Encrypting with GPG..."
    echo "You will be prompted to enter a passphrase."
    echo "REMEMBER THIS PASSPHRASE - you'll need it to decrypt on new machines!"
    echo ""

    gpg --symmetric --cipher-algo AES256 -o "$SECRETS_ARCHIVE" "$TEMP_TAR"

    # Clean up
    rm -f "$TEMP_TAR"

    print_success "Secrets encrypted to $SECRETS_ARCHIVE"
    echo ""
    echo "File size: $(du -h "$SECRETS_ARCHIVE" | cut -f1)"
    echo ""
    print_warning "You can now commit secrets.tar.gpg to your repo"
}

decrypt_secrets() {
    print_header "Decrypting secrets..."

    if [ ! -f "$SECRETS_ARCHIVE" ]; then
        print_error "Secrets archive not found: $SECRETS_ARCHIVE"
        exit 1
    fi

    echo "You will be prompted for your GPG passphrase."
    echo ""

    # Decrypt and extract
    gpg --decrypt "$SECRETS_ARCHIVE" | tar -xvf - -C "$HOME"

    # Fix SSH permissions
    if [ -d "$HOME/.ssh" ]; then
        chmod 700 "$HOME/.ssh"
        chmod 600 "$HOME/.ssh"/* 2>/dev/null || true
        chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null || true
        print_success "SSH permissions fixed"
    fi

    # Fix GPG permissions
    if [ -d "$HOME/.gnupg" ]; then
        chmod 700 "$HOME/.gnupg"
        chmod 600 "$HOME/.gnupg"/* 2>/dev/null || true
        print_success "GPG permissions fixed"
    fi

    print_success "Secrets decrypted and installed"
}

# Main
case "${1:-}" in
    encrypt)
        encrypt_secrets
        ;;
    decrypt)
        decrypt_secrets
        ;;
    *)
        echo "Usage: $0 {encrypt|decrypt}"
        echo ""
        echo "  encrypt - Create encrypted archive from ~/.ssh, ~/.gnupg, etc."
        echo "  decrypt - Decrypt and restore secrets to home directory"
        exit 1
        ;;
esac
