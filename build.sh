#!/usr/bin/env bash
# MorrowOS "Dawn" — build script
# Rebuilds the ISO from an Ubuntu 24.04 (noble) live ISO base.
# Run as root.  Requires: squashfs-tools xorriso isolinux syslinux-common rsync
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
ISO_IN="${1:-ubuntu-base.iso}"
ISO_OUT="${ISO_OUT:-morrowos-v1.1.iso}"
WORK="/tmp/morrowos-build"
STAGE="$WORK/iso"
ROOT="$WORK/squashfs-root"

# ── HARD-WON LESSONS (do not "optimise" these away) ──────────────────────────
#  * NEVER extract+repack the initrd.  Its 275 casper scripts live in a
#    zstd-compressed segment; repacking destroys them and you get a BusyBox
#    prompt with "/cow format specified as 'overlay' and no support found".
#    Pass config via the kernel cmdline instead (casper reads username=).
#    REGENERATING one is a different operation and is allowed: casper's own
#    initramfs hooks lay its scripts down properly, which is how Ubuntu
#    builds these in the first place.  That is what scripts/boot-splash.sh
#    does, and it verifies the result before letting it near the ISO --
#    see the long comment at the top of that file.  Do not "simplify" it
#    into a repack.
#  * NEVER blacklist vmwgfx.  VirtualBox VMSVGA *is* emulated VMware SVGA and
#    needs it for KMS.  Blacklisting it means no DRM device, X never starts,
#    and SDDM hangs after "Reached graphical.target".
#  * NEVER force a Driver in xorg.conf.d.  Install every video driver and let
#    X autodetect.  Two Device sections = X refuses to start.
#  * NEVER hand-write plasma-org.kde.plasma.desktop-appletsrc.  A partial file
#    makes plasmashell render an empty desktop.
#  * NEVER force LookAndFeelPackage at an incomplete package.
#  * NEVER force Backend=OpenGL / GLCore=true in kwinrc — KWin won't start
#    under software rendering (any VM without 3D accel).
#  * plasma-desktop does NOT hard-depend on kwin-x11 or dbus-x11.  Install
#    both explicitly or you get a black screen with a working cursor.
# ─────────────────────────────────────────────────────────────────────────────

for t in unsquashfs mksquashfs xorriso rsync; do
    command -v "$t" >/dev/null || { echo "MISSING: $t"; exit 1; }
done
[ -f "$ISO_IN" ] || { echo "Base ISO not found: $ISO_IN"; exit 1; }

echo "==> 1/9  Unpacking base ISO"
rm -rf "$WORK"; mkdir -p "$STAGE"
xorriso -osirrox on -indev "$ISO_IN" -extract / "$STAGE"
chmod -R u+w "$STAGE"

# --- boot layout diagnostics -------------------------------------------
# Ubuntu dropped isolinux in favour of GRUB-for-BIOS around 22.04, and
# stopped shipping boot/grub/efi.img at the same time. Different bases
# therefore need different handling, so dump what we actually got --
# this runs before the hour-long chroot work so a layout surprise fails
# cheap and with evidence instead of late and blind.
echo "--- top level of base ISO ---"
ls -A "$STAGE"
echo "--- isolinux/ ---"
ls -A "$STAGE/isolinux" 2>/dev/null || echo "(absent)"
echo "--- boot/grub/ ---"
ls -A "$STAGE/boot/grub" 2>/dev/null || echo "(absent)"
echo "--- EFI/ ---"
ls -AR "$STAGE/EFI" 2>/dev/null | head -20 || echo "(absent)"
echo "--- El Torito catalog ---"
xorriso -indev "$ISO_IN" -report_el_torito plain 2>&1 | head -30 || true
echo "-----------------------------------------------------------------"


echo "==> 2/9  Unpacking squashfs"
unsquashfs -d "$ROOT" "$STAGE/casper/filesystem.squashfs"

echo "==> 3/9  Mounting chroot"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
mount --bind /dev "$ROOT/dev"; mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"; mount -t sysfs sysfs "$ROOT/sys"
cleanup() { umount "$ROOT/sys" "$ROOT/proc" "$ROOT/dev/pts" "$ROOT/dev" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> 4/10  Installing packages"
chroot "$ROOT" apt-get update -qq

# ── REQUIRED ────────────────────────────────────────────────────────────────
# Without these the image does not boot to a usable desktop. A failure here
# is fatal, and should be.
MORROW_SYSTEM="
    kwin-x11 dbus-x11
    plymouth plymouth-themes
    python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 python3-pil
    flatpak
    xserver-xorg-video-vesa xserver-xorg-video-fbdev
    xserver-xorg-video-vmware xserver-xorg-video-qxl
    xserver-xorg-video-amdgpu xserver-xorg-video-ati
    xserver-xorg-video-nouveau xserver-xorg-video-intel
    polkit-kde-agent-1 policykit-1
    papirus-icon-theme gtk-update-icon-cache
"

# ── THE APP SET — EDIT THIS LIST ────────────────────────────────────────────
# This is what a user finds installed on first boot. Add or remove freely;
# everything here grows the ISO, so check the size the build reports at the
# end if you add something large.
#
# Unlike the list above, a failure here is NOT fatal. One mistyped or
# renamed package would otherwise kill a 40-minute build at minute 12, so
# the batch is retried one package at a time and the build reports what it
# could not install and carries on.
MORROW_APPS="
    firefox
    thunderbird
    libreoffice-writer libreoffice-calc libreoffice-impress
    vlc gwenview okular
    kate ark spectacle kcalc filelight
    partitionmanager
    git curl wget htop
    build-essential python3-pip
    calamares
"

chroot "$ROOT" apt-get install -y $MORROW_SYSTEM

if chroot "$ROOT" apt-get install -y $MORROW_APPS; then
    echo "    app set installed"
else
    echo "    batch app install failed — retrying one at a time to find the culprit"
    FAILED_APPS=""
    for pkg in $MORROW_APPS; do
        chroot "$ROOT" apt-get install -y "$pkg" >/dev/null 2>&1 \
            || FAILED_APPS="$FAILED_APPS $pkg"
    done
    if [ -n "$FAILED_APPS" ]; then
        echo "!!  could not install:$FAILED_APPS"
        echo "    the build continues without them — check the names against"
        echo "    the noble archive if you expected them to be there."
    fi
fi

# Flathub must be registered system-wide at build time, or every flatpak
# install in MorrowStore fails with "remote not configured" on first run.
chroot "$ROOT" flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

echo "==> 5/10  Installing MorrowOS branding"
# identity
install -m644 "$SRC/etc/os-release"           "$ROOT/etc/os-release"
install -m644 "$SRC/etc/lsb-release"          "$ROOT/etc/lsb-release"
install -m644 "$SRC/etc/casper.conf"          "$ROOT/etc/casper.conf"
install -Dm644 "$SRC/etc/X11/Xwrapper.config" "$ROOT/etc/X11/Xwrapper.config"

# plymouth.  The theme is only installed here -- making it the default and
# getting it into the initrd (which is where plymouth actually reads it from)
# happens in step 7, which verifies both instead of "|| true"-ing past them.
rm -rf "$ROOT/usr/share/plymouth/themes/morrowos"
cp -r "$SRC/usr/share/plymouth-morrowos" "$ROOT/usr/share/plymouth/themes/morrowos"
install -Dm644 "$SRC/etc/plymouth/plymouthd.conf" "$ROOT/etc/plymouth/plymouthd.conf"

# sddm  (theme shipped; stock breeze active until the QML is validated on hw)
rm -rf "$ROOT/usr/share/sddm/themes/morrowos"
cp -r "$SRC/usr/share/sddm-morrowos" "$ROOT/usr/share/sddm/themes/morrowos"
install -m644 "$SRC/etc/sddm.conf" "$ROOT/etc/sddm.conf"

# plasma theming
install -Dm644 "$SRC/usr/share/color-schemes/MorrowDawn.colors" \
    "$ROOT/usr/share/color-schemes/MorrowDawn.colors"
rm -rf "$ROOT/usr/share/wallpapers/MorrowOS"
cp -r "$SRC/usr/share/wallpapers/MorrowOS" "$ROOT/usr/share/wallpapers/"
rm -rf "$ROOT/usr/share/plasma/look-and-feel/os.morrow.desktop"
cp -r "$SRC/usr/share/lookandfeel-os.morrow.desktop" \
    "$ROOT/usr/share/plasma/look-and-feel/os.morrow.desktop"

# skel defaults.  -r matters: .config/autostart/ is a subdirectory, and a
# plain cp would silently skip it, taking the first-run setup with it.
mkdir -p "$ROOT/etc/skel/.config"
cp -r "$SRC"/etc/skel/.config/. "$ROOT/etc/skel/.config/"

# First-run desktop setup.  The wallpaper selection lives in
# plasma-org.kde.plasma.desktop-appletsrc, which must never be hand-written
# (rule 4 above), so it is applied at first login through Plasma's own CLI
# instead.  Without this the wallpaper ships but is never selected.
install -Dm755 "$SRC/usr/local/bin/morrowos-firstrun.sh" \
    "$ROOT/usr/local/bin/morrowos-firstrun.sh"

# SDDM resolves Session= with or without the .desktop suffix depending on
# version; the symlink makes both spellings work.
ln -sf plasma.desktop "$ROOT/usr/share/xsessions/plasma.desktop.desktop"

# Brand System Settings in-place rather than shipping a parallel .desktop
# file under a guessed app ID (Plasma has used both systemsettings.desktop
# and org.kde.systemsettings.desktop across releases — patch whichever
# exists so we don't end up with two icons in the menu).
for f in "$ROOT"/usr/share/applications/systemsettings.desktop \
         "$ROOT"/usr/share/applications/org.kde.systemsettings.desktop; do
    [ -f "$f" ] || continue
    sed -i \
        -e 's/^Name=.*/Name=MorrowOS Settings/' \
        -e 's/^Icon=.*/Icon=preferences-system/' \
        "$f"
done

echo "==> 6/10  Installing MorrowStore"
mkdir -p "$ROOT/usr/lib/morrowstore" "$ROOT/usr/share/morrowstore"
cp "$SRC"/morrowstore/*.py "$ROOT/usr/lib/morrowstore/"
install -m644 "$SRC/morrowstore/catalog.json" "$ROOT/usr/share/morrowstore/catalog.json"
install -m644 "$SRC/morrowstore/morrowstore.desktop" \
    "$ROOT/usr/share/applications/morrowstore.desktop"
install -m755 "$SRC/morrowstore/morrowstore-launcher.sh" "$ROOT/usr/bin/morrowstore"

# Icons.  morrowstore.desktop says Icon=morrowstore, and through v1.0 that
# pointed at a file which was never installed -- the asset existed in the
# source tree and nothing copied it in, so the launcher and task manager
# both fell back to a generic placeholder.  Install into the hicolor theme
# (where icon lookup actually looks), with a /usr/share/pixmaps copy as the
# fallback for anything that ignores themes, then refresh the cache or the
# new files are not picked up until something else invalidates it.
for size in 16 22 24 32 48 64 128 256; do
    for name in morrowstore morrowos-logo; do
        src="$SRC/usr/share/icons/hicolor/${size}x${size}/apps/${name}.png"
        [ -f "$src" ] || continue
        install -Dm644 "$src" \
            "$ROOT/usr/share/icons/hicolor/${size}x${size}/apps/${name}.png"
    done
done
for name in morrowstore morrowos-logo; do
    [ -f "$SRC/usr/share/icons/${name}.svg" ] && \
        install -Dm644 "$SRC/usr/share/icons/${name}.svg" \
            "$ROOT/usr/share/icons/hicolor/scalable/apps/${name}.svg"
    [ -f "$SRC/usr/share/icons/${name}.png" ] && \
        install -Dm644 "$SRC/usr/share/icons/${name}.png" \
            "$ROOT/usr/share/pixmaps/${name}.png"
done
chroot "$ROOT" gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || \
    echo "    (icon cache refresh skipped — gtk-update-icon-cache unavailable)"

# Fail loudly if the icon the .desktop file names is not actually present,
# rather than shipping another release with a placeholder icon.
test -f "$ROOT/usr/share/icons/hicolor/256x256/apps/morrowstore.png" || {
    echo "!! morrowstore icon missing from the image after install"; exit 1; }

echo "==> 7/10  Boot splash"
# Plymouth reads its theme from inside the INITRD, not from the filesystem.
# Through v1.2 the theme was installed into the squashfs and nothing ever
# touched the initrd, so every boot showed the stock Kubuntu splash.
#
# This is the only step that can produce an unbootable ISO, so it is the only
# step that verifies itself: boot-splash.sh keeps the pristine initrd aside,
# checks the regenerated one for casper's scripts, the overlay/squashfs/loop
# modules and the theme, and restores the original on any failure.  A failure
# here costs a stock splash, never a boot -- so it warns and carries on.
#
# Set MORROW_BOOT_SPLASH=0 to skip it entirely and ship the base initrd.
SPLASH_OK=0
if [ "${MORROW_BOOT_SPLASH:-1}" = "1" ]; then
    if bash "$SRC/scripts/boot-splash.sh" "$ROOT" "$STAGE"; then
        SPLASH_OK=1
    else
        echo "    continuing with the base initrd — the ISO will still boot,"
        echo "    it will just show the stock splash."
    fi
else
    echo "    skipped (MORROW_BOOT_SPLASH=0)"
fi

echo "==> 8/10  Installer branding"
# Makes the disk installer say MorrowOS rather than Kubuntu. It edits exactly
# one line of Kubuntu's settings.conf (the branding: line) and leaves the
# tested module sequence alone -- see scripts/installer-branding.sh for why.
# Like the splash, it degrades rather than failing the build.
INSTALLER_OK=0
# Derive the version from the output filename. The trailing-dot strip is
# load-bearing: "morrowos-v1.3.iso" otherwise yields "1.3." and the installer
# advertises MorrowOS 1.3. "Dawn".
MORROW_VERSION="${MORROW_VERSION:-$(printf '%s' "$ISO_OUT" \
    | sed -n 's/.*morrowos-v\{0,1\}\([0-9][0-9.]*\).*/\1/p' \
    | sed 's/\.*$//')}"
[ -n "$MORROW_VERSION" ] || MORROW_VERSION="1.0"
if bash "$SRC/scripts/installer-branding.sh" "$ROOT" "$MORROW_VERSION"; then
    INSTALLER_OK=1
else
    echo "    continuing with the stock installer — it still works,"
    echo "    it will just say Kubuntu."
fi

# The live user is created at boot by casper (username= on the cmdline).
# It must NOT pre-exist in the image or casper's user-setup-apply collides.
for u in morrow haven ubuntu; do
    sed -i "/^$u:/d" "$ROOT/etc/passwd" "$ROOT/etc/shadow" \
                     "$ROOT/etc/group"  "$ROOT/etc/gshadow" 2>/dev/null || true
    rm -rf "$ROOT/home/$u"
done
sed -i 's/^sudo:x:27:.*$/sudo:x:27:/' "$ROOT/etc/group"
grep -q '^nopasswdlogin:' "$ROOT/etc/group" || echo 'nopasswdlogin:x:1002:' >> "$ROOT/etc/group"

chroot "$ROOT" apt-get clean
rm -rf "$ROOT/var/lib/apt/lists"/* "$ROOT/etc/resolv.conf"
cleanup; trap - EXIT

echo "==> 9/10  Repacking squashfs"
rm -f "$STAGE/casper/filesystem.squashfs"
mksquashfs "$ROOT" "$STAGE/casper/filesystem.squashfs" \
    -comp zstd -Xcompression-level 15 -noappend
du -sx --block-size=1 "$ROOT" | cut -f1 > "$STAGE/casper/filesystem.size"

# boot config + disk identity.  vmlinuz is left byte-for-byte untouched; the
# initrd is only ever replaced by step 7, and only after it has verified the
# replacement (see scripts/boot-splash.sh).  If that step did not run or did
# not pass, casper/initrd here is still the base ISO's own file.
# Which menu file to write depends on the base ISO's bootloader: pre-22.04
# bases have isolinux/, modern ones are GRUB-only for both BIOS and UEFI.
WROTE_MENU=0
if [ -d "$STAGE/isolinux" ]; then
    install -m644 "$SRC/iso/isolinux.cfg" "$STAGE/isolinux/isolinux.cfg"
    echo "    boot menu -> isolinux/isolinux.cfg"
    WROTE_MENU=1
fi
GRUB_THEME=0
if [ -d "$STAGE/boot/grub" ]; then
    install -m644 "$SRC/iso/grub.cfg" "$STAGE/boot/grub/grub.cfg"
    echo "    boot menu -> boot/grub/grub.cfg"
    WROTE_MENU=1

    # Menu theme.  Unlike the splash this is just files on the ISO: if GRUB
    # cannot load it (no gfxmenu, no png, a bad theme.txt) it falls back to
    # the plain text menu and still boots, and grub.cfg tests for the file
    # before setting $theme.
    if [ -d "$SRC/iso/grub-theme" ]; then
        rm -rf "$STAGE/boot/grub/themes/morrowos"
        mkdir -p "$STAGE/boot/grub/themes"
        cp -r "$SRC/iso/grub-theme" "$STAGE/boot/grub/themes/morrowos"
        echo "    boot menu theme -> boot/grub/themes/morrowos"
        GRUB_THEME=1
    fi
fi
if [ "$WROTE_MENU" = "0" ]; then
    echo "!! Base ISO has neither isolinux/ nor boot/grub/ — see the layout"
    echo "   dump in step 1 above and adapt this block."
    exit 1
fi

mkdir -p "$STAGE/.disk"
install -m644 "$SRC/iso/disk-info.txt" "$STAGE/.disk/info"

# md5sum.txt must match the new squashfs or integrity-check boots fail
( cd "$STAGE" && rm -f md5sum.txt && \
  find . -type f -not -name md5sum.txt \
         -not -path "./isolinux/boot.cat" \
         -not -path "./boot/grub/boot.cat" \
         -not -name "boot.catalog" -print0 \
  | xargs -0 md5sum > md5sum.txt )

echo "==> 10/10  Building ISO (BIOS + UEFI, 64-bit)"
rm -f "$ISO_OUT"

# Rather than reconstructing the boot structures with -as mkisofs (which
# means knowing whether the base uses isolinux or GRUB, and where its EFI
# image lives -- both of which moved between Ubuntu releases), replay the
# source ISO's own boot setup verbatim and overwrite only the files we
# actually changed. Whatever BIOS+UEFI arrangement the base shipped with
# carries over intact.
#
# The initrd is in the -map list only when $SPLASH_OK is 1, which step 7
# sets only after verifying the regenerated initrd still contains casper's
# scripts and the overlay/squashfs/loop modules.  An unverified initrd can
# therefore never reach the ISO.
xorriso -indev "$ISO_IN" -outdev "$ISO_OUT" \
    -volid "MORROWOS" \
    -compliance no_emul_toc \
    -map "$STAGE/casper/filesystem.squashfs" /casper/filesystem.squashfs \
    -map "$STAGE/casper/filesystem.size"     /casper/filesystem.size \
    -map "$STAGE/.disk/info"                 /.disk/info \
    -map "$STAGE/md5sum.txt"                 /md5sum.txt \
    $( [ -f "$STAGE/isolinux/isolinux.cfg" ] && \
       echo -map "$STAGE/isolinux/isolinux.cfg" /isolinux/isolinux.cfg ) \
    $( [ -f "$STAGE/boot/grub/grub.cfg" ] && \
       echo -map "$STAGE/boot/grub/grub.cfg" /boot/grub/grub.cfg ) \
    $( [ "$GRUB_THEME" = "1" ] && \
       echo -map "$STAGE/boot/grub/themes/morrowos" /boot/grub/themes/morrowos ) \
    $( [ "$SPLASH_OK" = "1" ] && \
       echo -map "$STAGE/casper/initrd" /casper/initrd ) \
    -boot_image any replay

echo
echo "Built: $ISO_OUT ($(du -h "$ISO_OUT" | cut -f1))"
if [ "$SPLASH_OK" = "1" ]; then
    echo "Boot splash: MorrowOS (initrd regenerated and verified)"
else
    echo "Boot splash: STOCK — the initrd was left untouched"
fi
if [ "$GRUB_THEME" = "1" ]; then
    echo "Boot menu:   MorrowOS Dawn theme"
fi
if [ "$INSTALLER_OK" = "1" ]; then
    echo "Installer:   MorrowOS-branded (version $MORROW_VERSION)"
else
    echo "Installer:   STOCK — it will say Kubuntu"
fi
sha256sum "$ISO_OUT"
echo
echo "Boot structures carried over from the base ISO:"
xorriso -indev "$ISO_OUT" -report_el_torito plain 2>&1 | head -20 || true
echo
echo "Test BIOS boot:  qemu-system-x86_64 -m 3072 -smp 2 -cdrom $ISO_OUT -boot d -vga virtio"
# The replay approach carries the base ISO's UEFI boot structures over, so
# this is always worth testing.  (This used to be gated on $EFI_IMG, which is
# never assigned anywhere -- the hint silently never printed.)
echo "Test UEFI boot:  qemu-system-x86_64 -m 3072 -smp 2 -cdrom $ISO_OUT -boot d -vga virtio \\"
echo "                   -bios /usr/share/OVMF/OVMF_CODE.fd"
echo "  (needs the 'ovmf' package on the build/test host)"
