#!/usr/bin/env bash
# MorrowOS — put the Dawn boot splash into the initrd.
#
#   usage:  boot-splash.sh <squashfs-root> <iso-stage>
#   exit 0: $STAGE/casper/initrd now carries the MorrowOS splash
#   exit 1: nothing was changed; the base initrd is intact and must ship as-is
#
# ── why this file exists ────────────────────────────────────────────────────
# Plymouth loads its theme from inside the INITRD, not from the installed
# filesystem. Through v1.2 build.sh installed the theme into the squashfs and
# ran plymouth-set-default-theme, but never rebuilt or replaced the initrd --
# and the xorriso -map list had no initrd entry either. So the theme shipped,
# was never in the initrd, and every boot showed the stock Kubuntu splash.
# That is the whole of the "boot splash probably blocked" gap.
#
# ── how this does NOT break rule 1 ──────────────────────────────────────────
# Rule 1 forbids extracting the shipped initrd and REPACKING it. That is the
# operation that destroys casper's scripts: they live in a zstd segment and a
# naive round-trip loses them, giving the BusyBox panic
#   "/cow format specified as 'overlay' and no support found".
#
# This script never repacks anything. It asks initramfs-tools to GENERATE a
# new initrd from scratch inside the chroot, which is how Ubuntu builds its
# own live initrds: casper's hooks run and lay its scripts down properly
# rather than a copy being round-tripped. The shipped initrd is only ever
# read.
#
# ── the safety contract ─────────────────────────────────────────────────────
# This is the one change in the build that can produce an unbootable ISO, so
# nothing is swapped in until it has been proven:
#   * the pristine initrd is copied aside before anything runs
#   * the new one is extracted read-only and checked for casper's scripts,
#     the overlay/squashfs/loop modules whose absence causes the exact panic
#     above, plymouthd, and the MorrowOS theme itself
#   * any failure restores the pristine initrd and exits 1
# A failed splash costs you a stock splash. It never costs you a boot.
set -u

ROOT="${1:?usage: boot-splash.sh <squashfs-root> <iso-stage>}"
STAGE="${2:?usage: boot-splash.sh <squashfs-root> <iso-stage>}"

ORIG="$STAGE/casper/initrd"
PRISTINE="$STAGE/casper/initrd.pristine"
VERIFY_DIR="/tmp/morrow-initrd-verify"

say()  { echo "    $*"; }
fail() {
    echo "!!  boot splash NOT applied: $*"
    if [ -f "$PRISTINE" ]; then
        mv -f "$PRISTINE" "$ORIG"
        say "pristine initrd restored — the ISO will boot with the stock splash"
    fi
    rm -rf "${ROOT:?}$VERIFY_DIR"
    exit 1
}

[ -f "$ORIG" ] || fail "no initrd at casper/initrd in the ISO tree"

# ── 0. preconditions ───────────────────────────────────────────────────────
# casper's initramfs hooks are what make this a LIVE initrd. Without the
# package installed, update-initramfs happily produces a perfectly valid
# initrd that cannot boot a live ISO at all.
chroot "$ROOT" sh -c 'test -x /usr/share/initramfs-tools/hooks/casper' 2>/dev/null \
    || chroot "$ROOT" dpkg -s casper >/dev/null 2>&1 \
    || fail "casper is not installed in the chroot"

chroot "$ROOT" sh -c 'command -v update-initramfs >/dev/null' \
    || fail "initramfs-tools is not installed in the chroot"

KVER="$(chroot "$ROOT" sh -c 'ls -1 /lib/modules 2>/dev/null' | sort -V | tail -1)"
[ -n "$KVER" ] || fail "no kernel modules directory in the chroot"
NKVER="$(chroot "$ROOT" sh -c 'ls -1 /lib/modules 2>/dev/null' | wc -l)"
[ "$NKVER" = "1" ] || say "note: $NKVER kernels present, using the newest ($KVER)"
say "kernel: $KVER"

ORIG_SIZE="$(stat -c%s "$ORIG")"
say "base initrd: $(numfmt --to=iec "$ORIG_SIZE" 2>/dev/null || echo "$ORIG_SIZE B")"
cp -a "$ORIG" "$PRISTINE" || fail "could not back up the base initrd"

# ── 1. make the theme the default ──────────────────────────────────────────
# The plymouth initramfs hook copies in the DEFAULT theme only, so setting
# this is what actually gets the Dawn assets into the image.
chroot "$ROOT" plymouth-set-default-theme morrowos >/dev/null 2>&1 \
    || fail "plymouth-set-default-theme morrowos failed (is the theme installed?)"

ACTIVE="$(chroot "$ROOT" plymouth-set-default-theme 2>/dev/null | tr -d '[:space:]')"
[ "$ACTIVE" = "morrowos" ] \
    || fail "default theme is '$ACTIVE', expected 'morrowos'"
say "default plymouth theme: $ACTIVE"

# ── 2. pin the initramfs settings that matter ──────────────────────────────
# MODULES=most is not cosmetic. The default in a chroot can be 'dep', which
# builds an initrd carrying drivers for the BUILD MACHINE's hardware only --
# it boots on the runner and on nothing else. A live ISO must carry the lot.
# COMPRESS=zstd matches what casper ships and what the kernel expects here.
mkdir -p "$ROOT/etc/initramfs-tools/conf.d"
cat > "$ROOT/etc/initramfs-tools/conf.d/morrowos.conf" <<'CONF'
# MorrowOS: a live ISO must boot on hardware it has never seen.
MODULES=most
COMPRESS=zstd
CONF

# ── 3. generate ────────────────────────────────────────────────────────────
say "generating initrd (this takes a minute)"
rm -f "$ROOT/boot/initrd.img-$KVER"
if ! chroot "$ROOT" update-initramfs -c -k "$KVER" > /tmp/morrow-initramfs.log 2>&1; then
    echo "--- update-initramfs output ---"
    tail -40 /tmp/morrow-initramfs.log
    fail "update-initramfs returned non-zero"
fi
# Warnings are normal and not fatal, but worth seeing in the CI log.
grep -iE "^W:|warning" /tmp/morrow-initramfs.log | head -15 || true

NEW="$ROOT/boot/initrd.img-$KVER"
[ -f "$NEW" ] || fail "update-initramfs reported success but produced no file"

NEW_SIZE="$(stat -c%s "$NEW")"
say "new initrd:  $(numfmt --to=iec "$NEW_SIZE" 2>/dev/null || echo "$NEW_SIZE B")"

# A drastically smaller initrd is the signature of MODULES=dep sneaking back
# in, or of a hook that bailed silently.
MIN=$(( ORIG_SIZE / 2 ))
[ "$NEW_SIZE" -ge "$MIN" ] \
    || fail "new initrd is under half the size of the base one — modules are missing"

# ── 4. verify, read-only ───────────────────────────────────────────────────
say "verifying contents"
rm -rf "${ROOT:?}$VERIFY_DIR"
chroot "$ROOT" sh -c "mkdir -p $VERIFY_DIR && unmkinitramfs /boot/initrd.img-$KVER $VERIFY_DIR" \
    >/dev/null 2>&1 || fail "unmkinitramfs could not read the new initrd"

V="$ROOT$VERIFY_DIR"
have() { find "$V" -path "*/$1" -print -quit 2>/dev/null | grep -q . ; }

# casper: without these the live ISO cannot assemble its root at all
have "scripts/casper" || fail "casper's main script is missing from the initrd"
CASPER_N="$(find "$V" -path "*/scripts/casper*" -type f 2>/dev/null | wc -l)"
say "casper scripts: $CASPER_N"
[ "$CASPER_N" -ge 5 ] || fail "only $CASPER_N casper script(s) — the hook did not run properly"

# The three modules whose absence produces, verbatim, the panic in rule 1.
BUILTIN="$ROOT/lib/modules/$KVER/modules.builtin"
for m in overlay squashfs loop; do
    if find "$V" -name "$m.ko*" -print -quit 2>/dev/null | grep -q .; then
        continue
    fi
    # A module compiled into the kernel is not in the initrd and does not
    # need to be. Only a module that is neither is a real problem.
    if grep -q "/$m\.ko" "$BUILTIN" 2>/dev/null; then
        say "module '$m': built into the kernel"
        continue
    fi
    fail "kernel module '$m' is in neither the initrd nor the kernel — this is exactly the '/cow ... no support found' panic"
done
say "overlay/squashfs/loop: available"

# plymouth itself, and the Dawn assets
find "$V" -name "plymouthd" -print -quit 2>/dev/null | grep -q . \
    || fail "plymouthd is not in the initrd"
have "themes/morrowos/morrowos.script" || fail "the MorrowOS theme script is not in the initrd"
have "themes/morrowos/mark.png"        || fail "the MorrowOS theme images are not in the initrd"
THEME_N="$(find "$V" -path "*/themes/morrowos/*" -type f 2>/dev/null | wc -l)"
say "morrowos theme files in initrd: $THEME_N"

rm -rf "${ROOT:?}$VERIFY_DIR"

# ── 5. swap it in ──────────────────────────────────────────────────────────
# Written into the staging tree only. build.sh regenerates md5sum.txt after
# this point and adds the -map entry, so an unverified initrd can never
# reach the ISO.
cp -f "$NEW" "$ORIG" || fail "could not write the new initrd into the ISO tree"
rm -f "$PRISTINE"
say "initrd replaced in the ISO staging tree"
echo "    boot splash: APPLIED"
exit 0
