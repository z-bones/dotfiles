#!/usr/bin/env bash
# Symlink management - links dotfiles configs to home directory

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

# Create a symlink, backing up existing files
link_file() {
    local src="$1"
    local dst="$2"

    # Create parent directory if needed
    mkdir -p "$(dirname "$dst")"

    if [ -L "$dst" ]; then
        # Already a symlink, remove it
        rm "$dst"
    elif [ -f "$dst" ] || [ -d "$dst" ]; then
        # Existing file/dir, back it up
        print_warning "Backing up existing $dst to ${dst}.backup"
        mv "$dst" "${dst}.backup"
    fi

    ln -s "$src" "$dst"
    print_success "Linked $dst"
}

print_header "Creating config symlinks..."

# Fish shell
link_file "$DOTFILES_DIR/shell/fish/config.fish" "$HOME/.config/fish/config.fish"
link_file "$DOTFILES_DIR/shell/fish/fish_plugins" "$HOME/.config/fish/fish_plugins"

# Link fish conf.d files if they exist
if [ -d "$DOTFILES_DIR/shell/fish/conf.d" ]; then
    mkdir -p "$HOME/.config/fish/conf.d"
    for f in "$DOTFILES_DIR/shell/fish/conf.d"/*; do
        if [ -f "$f" ]; then
            link_file "$f" "$HOME/.config/fish/conf.d/$(basename "$f")"
        fi
    done
fi

# Bash
link_file "$DOTFILES_DIR/shell/bash/.bashrc" "$HOME/.bashrc"
if [ -f "$DOTFILES_DIR/shell/bash/.bash_aliases" ]; then
    link_file "$DOTFILES_DIR/shell/bash/.bash_aliases" "$HOME/.bash_aliases"
fi

# Alacritty
link_file "$DOTFILES_DIR/config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

# Starship
link_file "$DOTFILES_DIR/config/starship.toml" "$HOME/.config/starship.toml"

# Git
link_file "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"

print_success "Symlinks created"
