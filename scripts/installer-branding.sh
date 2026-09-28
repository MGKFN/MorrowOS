#!/usr/bin/env bash
# MorrowOS — make the disk installer say MorrowOS instead of Kubuntu.
#
#   usage:  installer-branding.sh <squashfs-root> <version>
#   exit 0: Calamares is branded and pointed at the MorrowOS branding
#   exit 1: nothing usable was changed; the stock installer ships
#
# ── the deliberate limit of this script ─────────────────────────────────────
# It does NOT write a settings.conf of its own. Kubuntu's module sequence is
# tested against this exact base -- which modules run, in which order, with
# which options -- and replacing it wholesale is how a remaster ends up with
# an installer that reaches 100% and produces an unbootable disk. The only
# edit made here is the single `branding:` line.
#
# Everything else is additive: a new branding directory, and the launcher's
# Name/Icon. If any of it fails, the stock Kubuntu installer still works --
# it just says Kubuntu.
set -u

ROOT="${1:?usage: installer-branding.sh <squashfs-root> <version>}"
VERSION="${2:-1.0}"

SETTINGS="$ROOT/etc/calamares/settings.conf"
BRANDDIR="$ROOT/etc/calamares/branding/morrowos"

say()  { echo "    $*"; }
fail() { echo "!!  installer branding NOT applied: $*"; exit 1; }

# ── 0. is there an installer to brand? ─────────────────────────────────────
if [ ! -f "$SETTINGS" ]; then
    say "no /etc/calamares/settings.conf — trying to install calamares"
    chroot "$ROOT" apt-get install -y calamares calamares-settings-ubuntu \
        >/dev/null 2>&1 || chroot "$ROOT" apt-get install -y calamares >/dev/null 2>&1 || true
fi
[ -f "$SETTINGS" ] || fail "calamares is not installed and could not be added"
say "found $(chroot "$ROOT" sh -c 'calamares --version 2>/dev/null | head -1' || echo calamares)"

# ── 1. the check that actually matters ─────────────────────────────────────
# unpackfs is what copies the live filesystem onto the target disk. If its
# source path is wrong the install runs to completion and produces nothing.
# This is read-only: we report, we do not "fix" a path we cannot test here.
UNPACK="$ROOT/etc/calamares/modules/unpackfs.conf"
if [ -f "$UNPACK" ]; then
    SRC_LINE="$(grep -E '^\s*-?\s*source:' "$UNPACK" | head -1 | sed 's/^\s*//')"
    say "unpackfs $SRC_LINE"
    SQUASH="$(printf '%s' "$SRC_LINE" | sed 's/.*source:\s*//; s/["'\'']//g')"
    case "$SQUASH" in
        *filesystem.squashfs) say "unpackfs source looks right" ;;
        *) echo "!!  unpackfs source is '$SQUASH', which does not look like the"
           echo "    live squashfs. Installs may complete and produce nothing."
           echo "    Branding will continue; check this before trusting an install." ;;
    esac
else
    echo "!!  no unpackfs.conf — this base may not use Calamares for installs."
fi

# ── 2. branding files ──────────────────────────────────────────────────────
SRCDIR="$(cd "$(dirname "$0")/.." && pwd)/etc/calamares/branding/morrowos"
[ -d "$SRCDIR" ] || fail "branding source directory missing: $SRCDIR"

rm -rf "$BRANDDIR"
mkdir -p "$(dirname "$BRANDDIR")"
cp -r "$SRCDIR" "$BRANDDIR" || fail "could not copy branding into the image"

# Stamp the real version so the installer cannot advertise a stale one.
sed -i "s/@VERSION@/$VERSION/g" "$BRANDDIR/branding.desc"
if grep -q '@VERSION@' "$BRANDDIR/branding.desc"; then
    fail "version substitution did not take"
fi
say "branding installed, version stamped as $VERSION"

for f in branding.desc logo.png welcome.png show.qml; do
    [ -f "$BRANDDIR/$f" ] || fail "branding/$f is missing after copy"
done
SLIDES="$(ls "$BRANDDIR"/slide-*.png 2>/dev/null | wc -l)"
[ "$SLIDES" -ge 1 ] || fail "no slideshow frames were installed"
say "branding files: 4 core + $SLIDES slide(s)"

# ── 3. point settings.conf at it (the one edit) ────────────────────────────
cp -a "$SETTINGS" "$SETTINGS.morrowos-backup" || fail "could not back up settings.conf"

if grep -qE '^\s*branding:' "$SETTINGS"; then
    sed -i -E 's|^([[:space:]]*)branding:.*|\1branding: morrowos|' "$SETTINGS"
else
    printf '\nbranding: morrowos\n' >> "$SETTINGS"
fi

ACTIVE="$(grep -E '^\s*branding:' "$SETTINGS" | head -1 | sed 's/.*branding:[[:space:]]*//' | tr -d '[:space:]')"
if [ "$ACTIVE" != "morrowos" ]; then
    mv -f "$SETTINGS.morrowos-backup" "$SETTINGS"
    fail "settings.conf still says branding '$ACTIVE' — reverted"
fi
rm -f "$SETTINGS.morrowos-backup"
say "settings.conf branding -> morrowos"

# ── 4. the launcher the user actually clicks ───────────────────────────────
# The file name has moved around between releases (calamares.desktop,
# install-debian.desktop, kubuntu-*.desktop), so patch whichever .desktop
# actually launches calamares rather than guessing a name.
PATCHED=0
for f in "$ROOT"/usr/share/applications/*.desktop; do
    [ -f "$f" ] || continue
    grep -qiE '^Exec=.*calamares' "$f" || continue
    sed -i \
        -e 's|^Name=.*|Name=Install MorrowOS|' \
        -e 's|^GenericName=.*|GenericName=System Installer|' \
        -e 's|^Comment=.*|Comment=Install MorrowOS to this computer|' \
        -e 's|^Icon=.*|Icon=morrowos-logo|' \
        "$f"
    say "launcher branded: $(basename "$f")"
    PATCHED=$((PATCHED + 1))
done
[ "$PATCHED" -gt 0 ] || echo "!!  no .desktop launches calamares — the installer may only be startable from a terminal."

echo "    installer branding: APPLIED"
exit 0
