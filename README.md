# Dotfiles

Personal dotfiles for a quick Linux workstation setup.

## Quick Start

```bash
git clone https://github.com/z-bones/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

## What's Included

### Shell
- **Fish** - Primary shell with Starship prompt
- **Bash** - Fallback with similar config

### Terminal
- **Alacritty** - GPU-accelerated terminal with custom color scheme

### Development Tools
- **nvm** - Node version manager + Node.js LTS
- **Rust** - via rustup + Cargo
- **Starship** - Cross-shell prompt
- **Fisher** - Fish plugin manager
- **GitHub CLI** - `gh` command for GitHub operations
- **Docker** - Container runtime + Compose plugin
- **Supabase CLI** - Supabase local development and management
- **AWS CLI v2** - Amazon Web Services command line interface
- **Cursor** - AI-powered code editor (AppImage)

### Global NPM Packages
- yarn
- @anthropic-ai/claude-code
- vercel

### VS Code / Cursor Extensions
- anthropic.claude-code - Claude Code AI assistant
- ms-python.python / debugpy / pylance - Python support
- ms-vscode.cpptools - C/C++ support
- ms-vscode-remote.remote-containers - Dev Containers
- ms-azuretools.vscode-containers - Docker integration
- platformio.platformio-ide - Embedded development
- ms-vscode.atom-keybindings - Atom-style keybindings

### Theme
- **[SynthWave '84 Dark](https://github.com/z-bones/synthwave-dark)** - Custom dark variant for VS Code/Cursor

### Applications (Flatpak)
- Brave Browser
- Obsidian
- LocalSend
- Audacity

### Manual Install
- [DaVinci Resolve](https://www.blackmagicdesign.com/products/davinciresolve)

## Structure

```
dotfiles/
├── install.sh              # Main bootstrap script
├── scripts/
│   ├── packages.sh         # System packages + Flatpaks
│   ├── tools.sh            # Dev tools (nvm, rust, docker, etc.)
│   ├── symlinks.sh         # Config symlinks
│   └── secrets.sh          # GPG encrypt/decrypt
├── shell/
│   ├── fish/               # Fish config
│   └── bash/               # Bash config
├── config/
│   ├── alacritty/          # Terminal config
│   ├── vscode/
│   │   └── extensions.txt  # VS Code/Cursor extensions list
│   └── starship.toml       # Prompt config
├── git/
│   └── .gitconfig          # Git config
├── secrets/
│   └── secrets.tar.gpg     # Encrypted secrets
└── Makefile                # Helper commands
```

## Secrets Management

Secrets (SSH keys, GPG keys, API tokens) are encrypted with GPG.

### Encrypt (before pushing)

```bash
make encrypt
# or
./scripts/secrets.sh encrypt
```

You'll be prompted for a passphrase. **Remember it!**

### Decrypt (on new machine)

```bash
make decrypt
# or
./scripts/secrets.sh decrypt
```

## Supported Distros

- Ubuntu / Debian / Pop!_OS / Linux Mint
- Fedora / RHEL / Rocky / Alma
- Arch / Manjaro / EndeavourOS

## Make Commands

```bash
make install    # Full installation
make packages   # Install packages only
make tools      # Install dev tools only
make symlinks   # Create symlinks only
make encrypt    # Encrypt secrets
make decrypt    # Decrypt secrets
make update     # Pull latest and re-symlink
```

## Customization

### Adding VS Code Extensions

Edit `config/vscode/extensions.txt` and add extension IDs (one per line).

### Modifying Flatpak Apps

Edit the `FLATPAK_APPS` array in `scripts/packages.sh`.
