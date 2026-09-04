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
- **Neovim** - Editor, with the Python provider (`python3-neovim`)
- **Tailscale** - Mesh VPN. The service is enabled automatically; log in
  separately with `sudo tailscale up`.
- **podman-compose** - Compose for podman, pairs with the `DOCKER_HOST`
  podman socket set in the shell configs
- **croc** - Encrypted peer-to-peer file transfer. Installed from upstream
  releases into `~/.local/bin`, *not* from the distro package: Fedora ships
  9.6.4 and croc requires clients >=9.6.16 to interoperate, so the packaged
  build cannot talk to a current croc on another machine.

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
- Zen Browser
- Obsidian
- Audacity
- Raspberry Pi Imager
- OBS Studio

### Manual Install
- [DaVinci Resolve](https://www.blackmagicdesign.com/products/davinciresolve)

## Structure

```
dotfiles/
├── install.sh              # Main bootstrap script
├── scripts/
│   ├── lib.sh              # Shared helpers + distro/arch detection
│   ├── packages.sh         # System packages + Flatpaks
│   ├── tools.sh            # Dev tools (nvm, rust, docker, etc.)
│   ├── symlinks.sh         # Config symlinks
│   ├── android.sh          # Android toolbox (JDK, SDK, emulator)
│   └── secrets.sh          # GPG encrypt/decrypt
├── shell/
│   ├── zsh/                # Zsh config (default shell)
│   └── bash/               # Bash config
├── config/
│   ├── alacritty/          # Terminal config
│   ├── sway/
│   │   ├── config          # Sway WM config
│   │   ├── startup.sh      # Session startup layout
│   │   ├── polkit-agent.sh # Probes for the host's polkit agent
│   │   └── config.d/       # Drop-ins — 10-lock, 20-keys-media, 30-rules,
│   │                       # 40-autostart (all hosts), laptop.conf (gated)
│   ├── waybar/             # Status bar config + styles
│   │                       # modules-right{,.ppd}.jsonc — host-gated drop-ins
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
- Fedora / RHEL / Rocky / Alma — both traditional (`dnf`/`dnf5`) and atomic (`rpm-ostree`)
- Arch / Manjaro / EndeavourOS

## Supported Architectures

`x86_64` and `aarch64` (e.g. Fedora Asahi Remix on Apple Silicon). `scripts/lib.sh`
detects the arch and picks the right download for each vendor's naming scheme.

Tools with no upstream Linux `aarch64` build are skipped with a warning rather
than failing the run:

| Tool | aarch64 |
|---|---|
| AWS CLI, Cursor, Supabase, Temurin JDK, SSM plugin | native build used |
| Android emulator image | `arm64-v8a` instead of `x86_64` |
| LM Studio | skipped — no Linux ARM build |
| OBS Studio (Flatpak) | skipped — x86_64-only on Flathub |

Zen Browser, Obsidian, Audacity and Raspberry Pi Imager all publish `aarch64`
Flatpaks, so the desktop apps come across intact.

## Sway Drop-ins

The main config includes `/etc/sway/config.d` and `~/.config/sway/config.d` with
sway's own glob include, and deliberately does **not** include
`/usr/share/sway/config.d`. That directory only has contents when
`sway-config-fedora` is installed, and reading it means every binding has two
possible owners — the distro's copy and ours.

The cost is that on a Fedora Sway spin those drop-ins were doing real work
nothing else does. They are ported into our own numbered drop-ins, so both hosts
get them whether or not the distro ever shipped them:

| Drop-in | Replaces | Provides |
| --- | --- | --- |
| `10-lock.conf` | `90-swayidle.conf` | `$lock`, swayidle, `loginctl lock-session` |
| `20-keys-media.conf` | `60-bindings-{volume,media}.conf` | Volume keys (wpctl), playback keys (playerctl) |
| `30-rules.conf` | `50-rules-*.conf` | Browser idle-inhibit, floating dialogs |
| `40-autostart.conf` | `95-*.conf` | Polkit agent, XDG autostart, user dirs |

The numeric prefixes are load order, not decoration. The include is a glob and
sway loads matches sorted, so `10-lock.conf` defines `$lock` before
`laptop.conf`'s lid binding uses it.

Every `exec` in `40-autostart.conf` is guarded, because the host it runs on may
never have had the package the distro drop-in assumed. The polkit agent is the
awkward one — it is `lxqt-policykit-agent` on the Sway spin and the KDE agent on
Plasma — so `config/sway/polkit-agent.sh` probes a candidate list instead of
installing one and hardcoding it.

## Laptop vs Desktop

`config/sway/config.d/laptop.conf` holds touchpad, lid-switch, screen-brightness
and keyboard-backlight settings. `symlinks.sh` links it only when the host has a
battery, so one branch serves both machines. Screen locking and the volume and
media keys are **not** in it — a desktop wants both, and two drop-ins declaring
`exec swayidle` would start two daemons. Waybar's `backlight` and `battery`
modules are always declared — Waybar disables a module whose hardware is absent.

The battery test is `has_battery()` in `lib.sh`, which scans
`/sys/class/power_supply/*/type` for `Battery` rather than globbing for `BAT*`,
and then skips anything whose `scope` is `Device`. Both halves are needed, and
they fail in opposite directions. `BAT0` is an ACPI convention: Apple Silicon
names its battery `macsmc-battery`, so the glob silently skipped `laptop.conf`
on the MacBook. But a bare type check is worse — a Logitech mouse reports
`hidpp_battery_0` with type `Battery`, so the desktop was detected as a laptop,
and because those batteries come and go as the device sleeps, the answer changed
between runs of the same script. `scope` is what separates a battery that powers
the machine from one that powers a peripheral.

`power-profiles-daemon` needs different handling: Waybar does *not* self-disable
it, and logs a hard error on every start where the daemon is missing. So the
whole `modules-right` list lives in a drop-in with two variants —
`config/waybar/modules-right.jsonc` (baseline) and `modules-right.ppd.jsonc`
(adds the module) — and `symlinks.sh` links whichever fits to
`~/.config/waybar/modules-right.jsonc`, keyed on `powerprofilesctl` being on
PATH. Packages install before symlinks, so that check sees the final state.

The list has to live in the drop-in rather than in `config.jsonc`: Waybar takes
the *first* definition of a duplicate key and the including file wins, so a
`modules-right` in `config.jsonc` could never be overridden by an include.
Keep the two variants in sync when adding or reordering modules.

## Make Commands

```bash
make install    # Full installation
make packages   # Install packages only
make tools      # Install dev tools only
make symlinks   # Create symlinks only
make android    # Set up the Android dev toolbox
make encrypt    # Encrypt secrets
make decrypt    # Decrypt secrets
make update     # Pull latest and re-symlink
```

## Customization

### Adding VS Code Extensions

Edit `config/vscode/extensions.txt` and add extension IDs (one per line).

### Modifying Flatpak Apps

Edit the `FLATPAK_APPS` array in `scripts/packages.sh`.

### Android Development

`make android` builds a Fedora toolbox container with the full Android toolchain —
Temurin JDK 17, the SDK command-line tools, an API 36 x86_64 system image, and a
Pixel 8 AVD. It is idempotent, so re-running it only fills in what's missing.

The host stays clean: it's an rpm-ostree system, so layering a JDK and the
emulator's Qt/WebEngine dependencies would mean a reboot per change. The container
shares `$HOME`, `/dev` (including `/dev/kvm`), the Wayland sockets, and the host
network namespace, so a Metro bundler on `:8081` is reachable from either side.
Anything under `$HOME` — JDK, SDK, AVDs — survives `toolbox rm`.

Two things that are easy to get wrong:

- **JDK 17 is not optional and not in the Fedora repos.** Fedora 43 ships 21/25/26,
  but React Native's Gradle plugin requests a 17 toolchain and there's no Foojay
  resolver to auto-provision one, so Gradle fails outright. The script installs
  Temurin 17, matching CI.
- **Never validate the emulator headlessly.** `-no-window` boots fine without the
  X libraries the windowed UI needs, so a `-no-window` smoke test will pass while
  the real emulator is still broken.

Sway tiles the emulator's windows by default, which lays its toolbars out on top of
the device screen — a 644x50 strip lands mid-viewport and reads as a black bar.
`config/sway/config.d/android-emulator.conf` handles that: device window tiled,
toolbars hidden in the scratchpad. Do not change that rule to `kill` — the side
toolbar is load-bearing and killing it shuts the emulator down.

iOS cannot be built on Linux at all; Xcode is macOS-only.
