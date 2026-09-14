#!/bin/bash
# MorrowStore launcher
export GTK_A11Y=none

# GTK4/libadwaita renders through GSK, which wants a working GL context.
# In VMs without 3D acceleration (VMware SVGA/vmwgfx, VirtualBox default,
# compositing off) GL init can fail silently and the window stays blank
# with nothing in the log. Force the software (cairo) renderer unless the
# caller has already picked one. Real hardware with working 3D accel can
# override this by exporting GSK_RENDERER before launch.
export GSK_RENDERER="${GSK_RENDERER:-cairo}"

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/morrowstore.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null
{
    echo "=== $(date -Is) launch (GSK_RENDERER=$GSK_RENDERER) ==="
    exec python3 /usr/lib/morrowstore/main.py "$@"
} 2>&1 | tee -a "$LOG"
