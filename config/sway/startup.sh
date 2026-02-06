#!/usr/bin/env bash
# Sway startup script - launches apps and arranges workspace layouts

# Wait for sway to be ready
sleep 1

# Workspace 1: 3 foot terminals
# Layout: 1 full-height left, 2 stacked vertically on right
swaymsg 'workspace 1'

foot &
sleep 0.5

# Second terminal splits horizontally (default)
foot &
sleep 0.5

# Focus the right terminal and split vertically for the third
swaymsg 'focus right; splitv'
foot &
sleep 0.5

# Workspace 2: Cursor
swaymsg 'workspace 2'
/home/zee/.local/bin/cursor &

# Workspace 3: Brave
swaymsg 'workspace 3'
flatpak run com.brave.Browser &

# Switch to workspace 1 on startup
swaymsg 'workspace 1'
