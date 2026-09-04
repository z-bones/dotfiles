#!/usr/bin/env bash
# Start the host's polkit authentication agent, whichever one it has.
#
# Sway starts no agent of its own. Without one, anything that asks polkit for
# authorisation gets no prompt and simply fails: mounting a disk in a file
# manager, GNOME Disks, a flatpak system install, virt-manager. The failure is
# silent and looks like a permissions bug in the app.
#
# The distro drop-in this replaces (/usr/share/sway/config.d/95-autostart-
# policykit-agent.conf) hardcoded lxqt-policykit-agent, which only exists
# because sway-config-fedora pulls in lxqt-policykit. That is wrong on a Plasma
# host, where the KDE agent is the one installed. So probe instead of assume.
#
# A script rather than an inline `exec` in the drop-in because the candidate
# list is long and sway passes exec lines through `sh -c`, where the quoting
# needed to survive both parsers is worse than a file. This one can be run and
# tested directly.

set -u

# Ordered by preference: the one matching the host's desktop first, since it is
# the one whose theming and dialog will look native.
candidates=(
    /usr/libexec/lxqt-policykit-agent
    /usr/libexec/polkit-kde-authentication-agent-1
    /usr/libexec/polkit-gnome-authentication-agent-1
    /usr/lib/polkit-kde-authentication-agent-1
    /usr/lib/polkit-gnome-authentication-agent-1
    /usr/libexec/polkit-mate-authentication-agent-1
    /usr/bin/lxpolkit
)

# Take the first agent that exists, unless one is already running — a second
# agent would race the first for the polkit registration and one would lose.
# `exec_always` on a sway reload is the case that makes this matter.
#
# The running check is anchored on the full path with `pgrep -f`, not a loose
# pattern like `pgrep -f polkit`. Unanchored, that matches any process whose
# command line merely mentions polkit — including the shell running this script,
# which then reports an agent that does not exist and starts nothing at all.
for agent in "${candidates[@]}"; do
    [ -x "$agent" ] || continue

    if pgrep -u "$USER" -f "^$agent( |\$)" > /dev/null 2>&1; then
        exit 0
    fi

    exec "$agent"
done

echo "polkit-agent.sh: no polkit authentication agent found" >&2
exit 1
