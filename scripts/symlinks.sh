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

# Zsh
link_file "$DOTFILES_DIR/shell/zsh/.zshrc" "$HOME/.zshrc"

# Bash
link_file "$DOTFILES_DIR/shell/bash/.bashrc" "$HOME/.bashrc"
if [ -f "$DOTFILES_DIR/shell/bash/.bash_aliases" ]; then
    link_file "$DOTFILES_DIR/shell/bash/.bash_aliases" "$HOME/.bash_aliases"
fi

# Alacritty
link_file "$DOTFILES_DIR/config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

# Starship
link_file "$DOTFILES_DIR/config/starship.toml" "$HOME/.config/starship.toml"

# Sway
link_file "$DOTFILES_DIR/config/sway/config" "$HOME/.config/sway/config"
link_file "$DOTFILES_DIR/config/sway/startup.sh" "$HOME/.config/sway/startup.sh"
# Drop-ins, picked up by the config.d include at the bottom of config
if command -v sway &> /dev/null; then
    link_file "$DOTFILES_DIR/config/sway/config.d/android-emulator.conf" "$HOME/.config/sway/config.d/android-emulator.conf"
fi

# Waybar
link_file "$DOTFILES_DIR/config/waybar/config.jsonc" "$HOME/.config/waybar/config.jsonc"
link_file "$DOTFILES_DIR/config/waybar/style.css" "$HOME/.config/waybar/style.css"

# Git
link_file "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"

# SDDM custom theme (immutable Fedora compatible - uses /etc/ instead of /usr/share/)
SDDM_THEME_SRC="/usr/share/sddm/themes/03-sway-fedora"
SDDM_THEME_DST="/etc/sddm/themes/custom-sway"

if [ -d "$SDDM_THEME_SRC" ] && [ -f "$DOTFILES_DIR/wallpapers/moon.jpg" ]; then
    print_header "Installing custom SDDM theme..."
    sudo mkdir -p "$SDDM_THEME_DST"

    # Symlink original theme assets (QML, images, metadata)
    for f in Main.qml metadata.desktop angle-down.png rectangle.png LICENSE README; do
        [ -f "$SDDM_THEME_SRC/$f" ] && sudo ln -sf "$SDDM_THEME_SRC/$f" "$SDDM_THEME_DST/$f"
    done

    # Copy our wallpaper and theme.conf into the custom theme
    sudo cp "$DOTFILES_DIR/wallpapers/moon.jpg" "$SDDM_THEME_DST/moon.jpg"
    sudo cp "$DOTFILES_DIR/config/sddm/theme.conf" "$SDDM_THEME_DST/theme.conf"

    # Tell SDDM to use our custom theme
    sudo mkdir -p /etc/sddm.conf.d
    sudo cp "$DOTFILES_DIR/config/sddm/sddm-theme.conf" /etc/sddm.conf.d/10-theme.conf

    print_success "Installed custom SDDM theme to $SDDM_THEME_DST"
fi

print_success "Symlinks created"
