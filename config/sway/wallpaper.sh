#!/usr/bin/env bash
# Set the desktop background, with fallbacks.
#
# The config used a bare `output * bg $HOME/.dotfiles/wallpapers/fire.jpg fill`.
# Sway does expand $HOME, but if the file is missing for any reason the
# directive fails and sway is left with no background and no recovery. This
# resolves the path from the script's own location (so it works regardless of
# where the repo is checked out), then degrades to a distro wallpaper and
# finally to a solid colour.

set -uo pipefail

FALLBACK_COLOR="#1a1b26"

# This script is symlinked into ~/.config/sway/, so follow the link to find the
# repo it actually lives in: <repo>/config/sway/wallpaper.sh -> <repo>
self="$(readlink -f "${BASH_SOURCE[0]}")"
repo="$(cd "$(dirname "$self")/../.." 2>/dev/null && pwd)" || repo=""

candidates=()
[ -n "$repo" ] && candidates+=("$repo/wallpapers/fire.jpg")
candidates+=(
    "${DOTFILES_DIR:-$HOME/.dotfiles}/wallpapers/fire.jpg"
    "$HOME/.dotfiles/wallpapers/fire.jpg"
    /usr/share/backgrounds/default-dark.jxl
    /usr/share/backgrounds/default.jxl
)

# Any distro wallpaper as a last resort before the solid colour.
while IFS= read -r f; do
    candidates+=("$f")
done < <(find /usr/share/backgrounds -maxdepth 3 -type f \
    \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jxl' \) 2>/dev/null | sort | head -5)

for f in "${candidates[@]}"; do
    if [ -f "$f" ]; then
        if swaymsg "output * bg \"$f\" fill" > /dev/null 2>&1; then
            echo "wallpaper: $f"
            exit 0
        fi
    fi
done

echo "wallpaper: no image found, using solid $FALLBACK_COLOR" >&2
swaymsg "output * bg $FALLBACK_COLOR solid_color" > /dev/null 2>&1
