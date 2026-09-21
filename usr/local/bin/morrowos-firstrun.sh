#!/bin/bash
# MorrowOS first-run desktop setup.
#
# WHY THIS EXISTS
# The wallpaper selection lives in plasma-org.kde.plasma.desktop-appletsrc.
# Hand-writing that file is forbidden (see rule 4 in build.sh) -- a partial
# one makes plasmashell render an empty desktop, which cost a full debugging
# round in v1.0. So instead of shipping a config file, we ask Plasma to do it
# through its own supported CLI once the shell is actually running.
#
# Runs from ~/.config/autostart, once per user, guarded by a stamp file.
# Every step is best-effort: a failure here must never stop the session.

set -u

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/morrowos-firstrun.log"
STAMP="${XDG_CACHE_HOME:-$HOME/.cache}/morrowos-firstrun.done"
WALLPAPER="/usr/share/wallpapers/MorrowOS/contents/images/1920x1080.png"
SCHEME="MorrowDawn"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Already done for this user.
[ -e "$STAMP" ] && exit 0

{
    echo "=== $(date -Is) MorrowOS first-run ==="

    # plasma-apply-* talk to a running plasmashell over D-Bus. At autostart
    # time the shell may not have registered yet, so wait for it rather than
    # firing into the void. Bounded so a failed shell can't hang the login.
    for _ in $(seq 1 45); do
        pgrep -x plasmashell >/dev/null 2>&1 && break
        sleep 1
    done
    if pgrep -x plasmashell >/dev/null 2>&1; then
        echo "plasmashell is up"
        # It registers on the bus slightly after the process appears.
        sleep 3
    else
        echo "WARNING: plasmashell not seen after 45s — applying anyway"
    fi

    if [ -r "$WALLPAPER" ]; then
        if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
            echo "applying wallpaper: $WALLPAPER"
            plasma-apply-wallpaperimage "$WALLPAPER" 2>&1 || \
                echo "WARNING: plasma-apply-wallpaperimage failed ($?)"
        else
            echo "WARNING: plasma-apply-wallpaperimage not installed"
        fi
    else
        echo "WARNING: wallpaper not readable at $WALLPAPER"
    fi

    if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
        echo "applying colour scheme: $SCHEME"
        plasma-apply-colorscheme "$SCHEME" 2>&1 || \
            echo "NOTE: colour scheme already set, or apply failed ($?)"
    fi

    echo "=== done ==="
} >>"$LOG" 2>&1

# Stamp regardless of individual step outcomes: this is cosmetic setup and
# retrying it at every login would be worse than leaving it alone.
touch "$STAMP" 2>/dev/null || true
exit 0
