#!/usr/bin/env bash
# Development tools installation

set -euo pipefail

# Shared helpers + detection. Sourced from install.sh (already loaded, no-op) or
# run standalone via `make`.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# NVM - Node Version Manager
install_nvm() {
    if [ -d "$HOME/.nvm" ]; then
        print_success "nvm already installed"
    else
        print_header "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi

    # Load nvm for this session (disable strict mode - nvm.sh isn't compatible)
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        set +u
        \. "$NVM_DIR/nvm.sh"
        set -u
    fi

    # Install Node.js if not present
    if ! command -v node &> /dev/null; then
        print_header "Installing Node.js LTS..."
        set +u
        nvm install --lts
        nvm use --lts
        set -u
    else
        print_success "Node.js already installed"
    fi

    # Install global npm packages (always ensure they're present)
    if command -v npm &> /dev/null; then
        print_header "Installing global npm packages..."
        npm install -g yarn @anthropic-ai/claude-code vercel aws-cdk 2>/dev/null || print_warning "Some npm packages failed to install"
    fi
}

# Rust via rustup
install_rust() {
    if command -v rustc &> /dev/null; then
        print_success "Rust already installed"
    else
        print_header "Installing Rust via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
}

# Starship prompt
install_starship() {
    if command -v starship &> /dev/null; then
        print_success "Starship already installed"
    else
        print_header "Installing Starship prompt..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
}

# JetBrainsMono Nerd Font
install_fonts() {
    local font_dir="$HOME/.local/share/fonts"
    local font_name="JetBrainsMono"

    if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
        print_success "JetBrainsMono Nerd Font already installed"
    else
        print_header "Installing JetBrainsMono Nerd Font..."
        mkdir -p "$font_dir"

        local tmp_dir
        tmp_dir=$(mktemp -d)
        cd "$tmp_dir"

        if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/${font_name}.zip" -o "${font_name}.zip"; then
            unzip -q "${font_name}.zip" -d "$font_dir"
            fc-cache -f
            print_success "JetBrainsMono Nerd Font installed"
        else
            print_warning "Failed to download JetBrainsMono Nerd Font"
        fi

        cd - > /dev/null
        rm -rf "$tmp_dir"
    fi
}

# Alacritty terminal.
#
# Prefer the distro package: Fedora, Debian and Arch all ship alacritty, and a
# source build costs several minutes and a full C toolchain for no benefit.
# Only fall back to cargo when no package is available, and only when a linker
# is actually present — `cargo install` fails with "linker `cc` not found"
# otherwise, which on rpm-ostree is guaranteed until the host reboots.
install_alacritty() {
    # Skip in containers (GUI app, requires OpenGL)
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
        print_warning "Running in container, skipping Alacritty installation"
        return 0
    fi

    if command -v alacritty &> /dev/null; then
        print_success "Alacritty already installed"
        return 0
    fi

    print_header "Installing Alacritty..."

    # 1. Distro package
    case "${DISTRO:-unknown}" in
        debian) sudo apt install -y alacritty && return 0 ;;
        arch)   sudo pacman -S --noconfirm alacritty && return 0 ;;
        fedora)
            case "$(detect_fedora_pkg_mgr)" in
                rpm-ostree)
                    if sudo rpm-ostree install -y --allow-inactive --idempotent alacritty; then
                        print_warning "Alacritty available after reboot"
                        return 0
                    fi
                    ;;
                dnf5) sudo dnf5 install -y alacritty && return 0 ;;
                dnf)  sudo dnf install -y alacritty && return 0 ;;
            esac
            ;;
    esac

    print_warning "No Alacritty package available, falling back to a source build"

    # 2. Source build — needs a working C toolchain
    if ! command -v cc &> /dev/null; then
        print_warning "No C linker (cc) found — skipping Alacritty source build."
        print_warning "Install gcc first (and reboot if this is an rpm-ostree host), then: make tools"
        return 0
    fi
    if ! command -v cargo &> /dev/null; then
        print_warning "cargo not found, skipping Alacritty"
        return 0
    fi

    # Build dependencies. gcc/pkg-config included: the cargo path needs a
    # linker and pkg-config to locate the system libraries.
    local alacritty_deps=(gcc pkgconf-pkg-config cmake freetype-devel fontconfig-devel
                          libxcb-devel libxkbcommon-devel scdoc)
    case "${DISTRO:-unknown}" in
        debian)
            sudo apt install -y build-essential cmake pkg-config libfreetype6-dev \
                libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev python3 scdoc \
                || print_warning "Some Alacritty deps failed to install"
            ;;
        fedora)
            case "$(detect_fedora_pkg_mgr)" in
                rpm-ostree)
                    sudo rpm-ostree install -y --allow-inactive --idempotent "${alacritty_deps[@]}" \
                        || print_warning "Some Alacritty deps failed to install"
                    print_warning "Deps require a reboot before the build will work"
                    return 0
                    ;;
                dnf5) sudo dnf5 install -y "${alacritty_deps[@]}" || print_warning "Some Alacritty deps failed" ;;
                dnf)  sudo dnf install -y "${alacritty_deps[@]}"  || print_warning "Some Alacritty deps failed" ;;
            esac
            ;;
        arch)
            sudo pacman -S --noconfirm base-devel cmake freetype2 fontconfig pkg-config make \
                libxcb libxkbcommon python scdoc || print_warning "Some Alacritty deps failed"
            ;;
    esac

    if ! cargo install alacritty; then
        print_warning "Alacritty build failed, continuing"
        return 0
    fi

    # Desktop entry for the cargo-installed binary (the distro package ships
    # its own, so this only applies to the source-build path).
    if [ -f "$HOME/.cargo/bin/alacritty" ]; then
        mkdir -p ~/.local/share/applications
        cat > ~/.local/share/applications/alacritty.desktop << EOF
[Desktop Entry]
Type=Application
Name=Alacritty
GenericName=Terminal
Comment=A fast, cross-platform, OpenGL terminal emulator
Exec=$HOME/.cargo/bin/alacritty
Icon=alacritty
Terminal=false
Categories=System;TerminalEmulator;
EOF
    fi
}

# GitHub CLI
install_gh() {
    if command -v gh &> /dev/null; then
        print_success "GitHub CLI already installed"
    else
        print_header "Installing GitHub CLI..."
        case "${DISTRO:-unknown}" in
            debian)
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt update
                sudo apt install -y gh
                ;;
            fedora)
                case "$(detect_fedora_pkg_mgr)" in
                    rpm-ostree)
                        sudo rpm-ostree install -y --allow-inactive --idempotent gh
                        ;;
                    dnf5)
                        sudo dnf5 install -y gh
                        ;;
                    dnf)
                        sudo dnf install -y gh
                        ;;
                esac
                ;;
            arch)
                sudo pacman -S --noconfirm github-cli
                ;;
        esac
    fi
}

# Docker
install_docker() {
    # Skip in containers (Docker-in-Docker requires special setup)
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
        print_warning "Running in container, skipping Docker installation"
        return 0
    fi

    if command -v docker &> /dev/null; then
        print_success "Docker already installed"
    else
        print_header "Installing Docker..."
        case "${DISTRO:-unknown}" in
            debian)
                # Add Docker's official GPG key and repository
                sudo apt install -y ca-certificates
                sudo install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                sudo chmod a+r /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt update
                sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                ;;
            fedora)
                case "$(detect_fedora_pkg_mgr)" in
                    rpm-ostree)
                        print_warning "Skipping Docker on immutable Fedora - use podman instead (pre-installed)"
                        return 0
                        ;;
                    dnf5)
                        sudo dnf5 install -y dnf5-plugins
                        sudo dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
                        sudo dnf5 install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                        ;;
                    dnf)
                        sudo dnf install -y dnf-plugins-core
                        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                        ;;
                esac
                ;;
            arch)
                sudo pacman -S --noconfirm docker docker-compose
                ;;
        esac

        # Add user to docker group
        sudo usermod -aG docker "$USER"
        sudo systemctl enable docker
        sudo systemctl start docker
        print_warning "Log out and back in for docker group membership to take effect"
    fi
}

# Supabase CLI
install_supabase() {
    if command -v supabase &> /dev/null; then
        print_success "Supabase CLI already installed"
    else
        print_header "Installing Supabase CLI..."
        # Download from GitHub releases (npm global no longer supported)
        local version
        version=$(curl -fsSL https://api.github.com/repos/supabase/cli/releases/latest | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
        version="${version#v}"  # Remove 'v' prefix if present

        if [ -z "$version" ]; then
            print_warning "Could not detect Supabase version, skipping"
            return 0
        fi

        local tmp_dir
        tmp_dir=$(mktemp -d)
        cd "$tmp_dir"

        case "${DISTRO:-unknown}" in
            debian)
                if curl -fsSL "https://github.com/supabase/cli/releases/download/v${version}/supabase_${version}_linux_${ARCH_DEB}.deb" -o supabase.deb; then
                    sudo dpkg -i supabase.deb || print_warning "Failed to install Supabase"
                else
                    print_warning "Failed to download Supabase CLI"
                fi
                ;;
            fedora)
                if curl -fsSL "https://github.com/supabase/cli/releases/download/v${version}/supabase_${version}_linux_${ARCH_DEB}.rpm" -o supabase.rpm; then
                    case "$(detect_fedora_pkg_mgr)" in
                        rpm-ostree)
                            sudo rpm-ostree install -y --allow-inactive "$(pwd)/supabase.rpm" || print_warning "Failed to install Supabase"
                            ;;
                        *)
                            sudo rpm -i supabase.rpm || print_warning "Failed to install Supabase"
                            ;;
                    esac
                else
                    print_warning "Failed to download Supabase CLI"
                fi
                ;;
            arch)
                if curl -fsSL "https://github.com/supabase/cli/releases/download/v${version}/supabase_${version}_linux_${ARCH_DEB}.pkg.tar.zst" -o supabase.pkg.tar.zst; then
                    sudo pacman -U --noconfirm supabase.pkg.tar.zst || print_warning "Failed to install Supabase"
                else
                    print_warning "Failed to download Supabase CLI"
                fi
                ;;
            *)
                print_warning "Unknown distro, skipping Supabase CLI"
                ;;
        esac

        cd - > /dev/null
        rm -rf "$tmp_dir"
    fi
}

# AWS CLI v2
install_aws() {
    if command -v aws &> /dev/null; then
        print_success "AWS CLI already installed"
    else
        print_header "Installing AWS CLI v2..."
        if [ "${ARCH:-unknown}" = "unknown" ]; then
            print_warning "Unknown architecture, skipping AWS CLI"
            return 0
        fi
        local tmp_dir
        tmp_dir=$(mktemp -d)
        cd "$tmp_dir"
        # Guarded: a failed download or install must not abort the whole run
        # (this script is sourced under `set -e`).
        if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "awscliv2.zip" \
            && unzip -q awscliv2.zip; then
            sudo ./aws/install || print_warning "Failed to install AWS CLI"
        else
            print_warning "Failed to download AWS CLI for $ARCH"
        fi
        cd - > /dev/null
        rm -rf "$tmp_dir"
    fi
}

# Cursor IDE (AppImage)
install_cursor() {
    # Skip in containers (AppImages require FUSE)
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
        print_warning "Running in container, skipping Cursor installation"
        return 0
    fi

    local cursor_dir="$HOME/.local/bin"
    local cursor_path="$cursor_dir/cursor.AppImage"

    if [ -f "$cursor_path" ]; then
        print_success "Cursor already installed"
        # Ensure symlink exists (may be missing from older installs)
        if [ ! -L "$cursor_dir/cursor" ]; then
            ln -sf "$cursor_path" "$cursor_dir/cursor"
        fi
    else
        print_header "Installing Cursor IDE..."
        mkdir -p "$cursor_dir"

        # Get latest AppImage URL from Cursor's download API
        local download_url
        download_url=$(curl -fsSL "https://www.cursor.com/api/download?platform=linux-${ARCH_ALT}&releaseTrack=stable" | grep -o '"downloadUrl":"[^"]*"' | cut -d'"' -f4)

        if [ -z "$download_url" ]; then
            print_warning "Failed to fetch Cursor download URL for linux-${ARCH_ALT}, skipping"
            return 0
        fi

        # Download latest Cursor AppImage
        if ! curl -fSL "$download_url" -o "$cursor_path"; then
            print_warning "Failed to download Cursor, skipping"
            rm -f "$cursor_path"
            return 0
        fi
        chmod +x "$cursor_path"

        # Create symlink so 'cursor' command works (for extension installation, etc.)
        ln -sf "$cursor_path" "$cursor_dir/cursor"

        # Create desktop entry
        mkdir -p ~/.local/share/applications
        cat > ~/.local/share/applications/cursor.desktop << EOF
[Desktop Entry]
Type=Application
Name=Cursor
GenericName=Code Editor
Comment=AI-powered code editor
Exec=$cursor_path %F
Icon=cursor
Terminal=false
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
StartupWMClass=Cursor
EOF

        print_success "Cursor installed to $cursor_path"
    fi
}

# SynthWave '84 Dark theme for VS Code/Cursor
install_synthwave_theme() {
    local ext_id="z-bones.synthwave-dark"
    local repo_url="https://github.com/z-bones/synthwave-dark.git"

    # Check if already installed (with version suffix)
    if ls -d "$HOME/.vscode/extensions/${ext_id}-"* &>/dev/null 2>&1 || \
       ls -d "$HOME/.cursor/extensions/${ext_id}-"* &>/dev/null 2>&1; then
        print_success "SynthWave '84 Dark theme already installed"
        return 0
    fi

    # Remove old installs without version suffix
    rm -rf "$HOME/.vscode/extensions/$ext_id" "$HOME/.cursor/extensions/$ext_id" 2>/dev/null

    print_header "Installing SynthWave '84 Dark theme..."

    local tmp_dir
    tmp_dir=$(mktemp -d)
    if git clone --depth 1 "$repo_url" "$tmp_dir/theme" 2>/dev/null; then
        local version
        version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$tmp_dir/theme/package.json" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "1.0.0")
        [ -z "$version" ] && version="1.0.0"

        # Install for VS Code
        if [ -d "$HOME/.vscode/extensions" ]; then
            cp -r "$tmp_dir/theme" "$HOME/.vscode/extensions/${ext_id}-${version}"
        fi

        # Install for Cursor
        mkdir -p "$HOME/.cursor/extensions"
        cp -r "$tmp_dir/theme" "$HOME/.cursor/extensions/${ext_id}-${version}"

        print_success "SynthWave '84 Dark theme installed (${version})"
    else
        print_warning "Failed to clone SynthWave theme"
    fi
    rm -rf "$tmp_dir"
}

# Download and install a VS Code extension directly from marketplace
# Usage: install_extension_direct <publisher.extension> <target_dir>
install_extension_direct() {
    local ext_id="$1"
    local ext_dir="$2"
    local publisher="${ext_id%%.*}"
    local extension="${ext_id#*.}"

    # Skip if already installed (check for any version)
    if ls -d "$ext_dir/${ext_id}-"* &>/dev/null 2>&1; then
        return 0
    fi

    # Download from VS Code Marketplace
    local download_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${extension}/latest/vspackage"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    echo "  Downloading $ext_id..."
    if curl -fSL --compressed --retry 2 "$download_url" -o "$tmp_dir/extension.vsix" 2>/dev/null; then
        # VSIX may be gzipped, check and decompress if needed
        if command -v file &>/dev/null && file "$tmp_dir/extension.vsix" 2>/dev/null | grep -q gzip; then
            mv "$tmp_dir/extension.vsix" "$tmp_dir/extension.vsix.gz"
            gunzip "$tmp_dir/extension.vsix.gz" 2>/dev/null || true
        fi
        # VSIX is just a zip file
        if unzip -q "$tmp_dir/extension.vsix" -d "$tmp_dir/extracted" 2>/dev/null && [ -d "$tmp_dir/extracted/extension" ]; then
            # Extract version from package.json for proper directory naming
            local version
            version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$tmp_dir/extracted/extension/package.json" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "0.0.0")
            if [ -z "$version" ]; then
                version="0.0.0"
            fi
            local target_path="$ext_dir/${ext_id}-${version}"
            mkdir -p "$target_path"
            cp -r "$tmp_dir/extracted/extension/"* "$target_path/"
            echo "  Installed ${ext_id}-${version}"
        else
            print_warning "Failed to extract $ext_id (file type: $(file "$tmp_dir/extension.vsix" 2>/dev/null || echo 'unknown'))"
        fi
    else
        print_warning "Failed to download $ext_id"
    fi

    rm -rf "$tmp_dir"
}

# VS Code / Cursor extensions
install_vscode_extensions() {
    local extensions_file="$DOTFILES_DIR/config/vscode/extensions.txt"

    if [ ! -f "$extensions_file" ]; then
        print_warning "Extensions file not found: $extensions_file"
        return 1
    fi

    # Install for VS Code using CLI (works reliably)
    if command -v code &> /dev/null; then
        print_header "Installing VS Code extensions..."
        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "${line// }" ]] && continue
            if ! code --list-extensions | grep -qi "^${line}$"; then
                echo "Installing $line..."
                code --install-extension "$line" --force || print_warning "Failed to install $line"
            fi
        done < "$extensions_file"
        print_success "VS Code extensions installed"
    fi

    # Install for Cursor by downloading directly (CLI doesn't work well with AppImage)
    local cursor_ext_dir="$HOME/.cursor/extensions"
    if [ -f "$HOME/.local/bin/cursor.AppImage" ] || [ -d "$HOME/.cursor" ]; then
        print_header "Installing Cursor extensions..."
        mkdir -p "$cursor_ext_dir"
        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "${line// }" ]] && continue
            install_extension_direct "$line" "$cursor_ext_dir"
        done < "$extensions_file"
        print_success "Cursor extensions installed"
    fi
}

# AWS Toolbox (SSM plugin for ECS exec on immutable Fedora)
setup_aws_toolbox() {
    # Only relevant on immutable Fedora where SSM plugin RPM can't install to host
    if [ "$(detect_fedora_pkg_mgr)" != "rpm-ostree" ]; then
        # On mutable systems, install SSM plugin directly
        if command -v session-manager-plugin &> /dev/null; then
            print_success "SSM Session Manager plugin already installed"
        else
            print_header "Installing SSM Session Manager plugin..."
            local tmp_dir
            tmp_dir=$(mktemp -d)
            curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "$tmp_dir/ssm-plugin.rpm"
            case "${DISTRO:-unknown}" in
                debian)
                    curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "$tmp_dir/ssm-plugin.deb"
                    sudo dpkg -i "$tmp_dir/ssm-plugin.deb" || print_warning "Failed to install SSM plugin"
                    ;;
                fedora)
                    sudo dnf install -y "$tmp_dir/ssm-plugin.rpm" 2>/dev/null || \
                    sudo dnf5 install -y "$tmp_dir/ssm-plugin.rpm" 2>/dev/null || \
                    print_warning "Failed to install SSM plugin"
                    ;;
                arch)
                    print_warning "SSM plugin not available as pacman package — install from AUR: aws-session-manager-plugin"
                    ;;
            esac
            rm -rf "$tmp_dir"
        fi
        return 0
    fi

    if ! command -v toolbox &> /dev/null; then
        print_warning "toolbox not found, skipping AWS toolbox setup"
        return 0
    fi

    # Check if toolbox already exists
    if toolbox list 2>/dev/null | grep -q "dev-tools"; then
        print_success "AWS toolbox already exists"
    else
        print_header "Creating AWS toolbox with SSM plugin..."
        toolbox create dev-tools -y 2>/dev/null || true

        # SSM plugin uses its own arch spelling: linux_64bit / linux_arm64
        local ssm_arch="linux_64bit"
        [ "$ARCH" = "aarch64" ] && ssm_arch="linux_arm64"

        # Install AWS CLI and SSM plugin inside the toolbox. Double-quoted so
        # $ARCH/$ssm_arch expand on the host before the container runs this.
        toolbox run -c dev-tools bash -c "
            cd /tmp
            curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip' -o awscliv2.zip
            unzip -q awscliv2.zip
            sudo ./aws/install
            rm -rf aws awscliv2.zip
            curl -fsSL 'https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${ssm_arch}/session-manager-plugin.rpm' -o ssm-plugin.rpm
            sudo dnf install -y ssm-plugin.rpm
            rm ssm-plugin.rpm
        " || print_warning "AWS toolbox setup failed"
    fi

    # Create a wrapper script so you can run `aws-ecs-exec` from the host
    local wrapper="$HOME/.local/bin/aws-ecs-exec"
    mkdir -p "$HOME/.local/bin"
    cat > "$wrapper" << 'WRAPPER'
#!/usr/bin/env bash
# Wrapper to run `aws ecs execute-command` via the dev-tools toolbox
# Usage: aws-ecs-exec --cluster <cluster> --task <task> --container <name> --command <cmd>
exec toolbox run -c dev-tools aws ecs execute-command --interactive "$@"
WRAPPER
    chmod +x "$wrapper"
    print_success "AWS toolbox ready — use 'aws-ecs-exec' or 'toolbox enter dev-tools' then run aws commands"
}

# Proton Authenticator (2FA)
install_proton_authenticator() {
    if rpm -q proton-authenticator &>/dev/null; then
        print_success "Proton Authenticator already installed"
    else
        print_header "Installing Proton Authenticator..."
        local tmp_dir
        tmp_dir=$(mktemp -d)
        cd "$tmp_dir"

        if curl -fsSL "https://proton.me/download/authenticator/linux/ProtonAuthenticator.rpm" -o ProtonAuthenticator.rpm; then
            case "${DISTRO:-unknown}" in
                fedora)
                    case "$(detect_fedora_pkg_mgr)" in
                        rpm-ostree)
                            sudo rpm-ostree install -y --allow-inactive "$(pwd)/ProtonAuthenticator.rpm" || print_warning "Failed to install Proton Authenticator"
                            ;;
                        dnf5)
                            sudo dnf5 install -y ProtonAuthenticator.rpm || print_warning "Failed to install Proton Authenticator"
                            ;;
                        dnf)
                            sudo dnf install -y ProtonAuthenticator.rpm || print_warning "Failed to install Proton Authenticator"
                            ;;
                    esac
                    ;;
                *)
                    print_warning "Proton Authenticator RPM only supported on Fedora/RHEL"
                    ;;
            esac
        else
            print_warning "Failed to download Proton Authenticator"
        fi

        cd - > /dev/null
        rm -rf "$tmp_dir"
    fi
}

# croc — encrypted peer-to-peer file transfer.
#
# Deliberately NOT the distro package. Fedora 43 ships croc 9.6.4, and upstream
# states clients must be >=9.6.16 to interoperate, so the repo build cannot talk
# to a current croc on another machine. Install the latest upstream release into
# ~/.local/bin so every machine ends up on the same version.
install_croc() {
    if command -v croc &> /dev/null; then
        print_success "croc already installed ($(croc --version 2>/dev/null | head -1))"
        return 0
    fi

    local croc_arch
    case "${ARCH:-unknown}" in
        x86_64)  croc_arch="Linux-64bit" ;;
        aarch64) croc_arch="Linux-ARM64" ;;
        *)       print_warning "No croc build for ${ARCH:-unknown}, skipping"; return 0 ;;
    esac

    print_header "Installing croc..."
    local version
    version=$(curl -fsSL https://api.github.com/repos/schollz/croc/releases/latest \
        | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
    version="${version#v}"
    if [ -z "$version" ]; then
        print_warning "Could not detect croc version, skipping"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    if curl -fsSL "https://github.com/schollz/croc/releases/download/v${version}/croc_v${version}_${croc_arch}.tar.gz" \
        -o "$tmp_dir/croc.tar.gz" && tar -xzf "$tmp_dir/croc.tar.gz" -C "$tmp_dir" croc; then
        mkdir -p "$HOME/.local/bin"
        install -m 0755 "$tmp_dir/croc" "$HOME/.local/bin/croc"
        print_success "croc $version installed to ~/.local/bin"
    else
        print_warning "Failed to install croc"
    fi
    rm -rf "$tmp_dir"
}

# LM Studio — x86_64 only; upstream ships no Linux aarch64 build
install_lmstudio() {
    if [ "${ARCH:-unknown}" != "x86_64" ]; then
        print_warning "LM Studio has no Linux $ARCH build, skipping"
        return 0
    fi

    if [ -d "$HOME/.lmstudio" ]; then
        print_success "LM Studio already installed"
    else
        print_header "Installing LM Studio..."
        curl -fsSL https://lmstudio.ai/install.sh | bash || print_warning "LM Studio install failed"
    fi
}

# Main
#
# Each installer runs independently. This script is sourced under `set -e`, so
# without the guard a single failure aborts every step after it — a failed
# Alacritty build used to take gh, docker, supabase, aws, Cursor and the VS
# Code extensions down with it. Failures are collected and reported instead.
INSTALLERS=(
    install_nvm
    install_rust
    install_starship
    install_fonts
    install_alacritty
    install_gh
    install_docker
    install_supabase
    install_aws
    setup_aws_toolbox
    install_proton_authenticator
    install_croc
    install_cursor
    install_lmstudio
    install_synthwave_theme
    install_vscode_extensions
)

FAILED=()
for step in "${INSTALLERS[@]}"; do
    if ! "$step"; then
        print_error "$step failed"
        FAILED+=("$step")
    fi
done

if [ ${#FAILED[@]} -eq 0 ]; then
    print_success "Development tools installation complete"
else
    print_warning "Completed with ${#FAILED[@]} failed step(s): ${FAILED[*]}"
    print_warning "Re-run just this stage with: make tools"
fi
