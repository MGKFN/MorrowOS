#!/usr/bin/env bash
# MorrowOS v1.1 "Dawn" — build script
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

echo "==> 1/8  Unpacking base ISO"
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


echo "==> 2/8  Unpacking squashfs"
unsquashfs -d "$ROOT" "$STAGE/casper/filesystem.squashfs"

echo "==> 3/8  Mounting chroot"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
mount --bind /dev "$ROOT/dev"; mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"; mount -t sysfs sysfs "$ROOT/sys"
cleanup() { umount "$ROOT/sys" "$ROOT/proc" "$ROOT/dev/pts" "$ROOT/dev" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> 4/8  Installing packages"
chroot "$ROOT" apt-get update -qq
chroot "$ROOT" apt-get install -y \
    kwin-x11 dbus-x11 \
    plymouth plymouth-themes \
    python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 python3-pil flatpak \
    xserver-xorg-video-vesa xserver-xorg-video-fbdev \
    xserver-xorg-video-vmware xserver-xorg-video-qxl \
    xserver-xorg-video-amdgpu xserver-xorg-video-ati \
    xserver-xorg-video-nouveau xserver-xorg-video-intel \
    polkit-kde-agent-1 policykit-1 \
    papirus-icon-theme \
    firefox libreoffice-writer libreoffice-calc vlc

# Flathub must be registered system-wide at build time, or every flatpak
# install in MorrowStore fails with "remote not configured" on first run.
chroot "$ROOT" flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

echo "==> 5/8  Installing MorrowOS branding"
# identity
install -m644 "$SRC/etc/os-release"           "$ROOT/etc/os-release"
install -m644 "$SRC/etc/lsb-release"          "$ROOT/etc/lsb-release"
install -m644 "$SRC/etc/casper.conf"          "$ROOT/etc/casper.conf"
install -Dm644 "$SRC/etc/X11/Xwrapper.config" "$ROOT/etc/X11/Xwrapper.config"

# plymouth
rm -rf "$ROOT/usr/share/plymouth/themes/morrowos"
cp -r "$SRC/usr/share/plymouth-morrowos" "$ROOT/usr/share/plymouth/themes/morrowos"
install -Dm644 "$SRC/etc/plymouth/plymouthd.conf" "$ROOT/etc/plymouth/plymouthd.conf"
chroot "$ROOT" plymouth-set-default-theme morrowos || true

# sddm  (theme shipped; stock breeze active until the QML is validated on hw)
rm -rf "$ROOT/usr/share/sddm/themes/morrowos"
cp -r "$SRC/usr/share/sddm-morrowos" "$ROOT/usr/share/sddm/themes/morrowos"
install -m644 "$SRC/etc/sddm.conf" "$ROOT/etc/sddm.conf"

# plasma theming
install -Dm644 "$SRC/usr/share/color-schemes/MorrowDark.colors" \
    "$ROOT/usr/share/color-schemes/MorrowDark.colors"
rm -rf "$ROOT/usr/share/wallpapers/MorrowOS"
cp -r "$SRC/usr/share/wallpapers/MorrowOS" "$ROOT/usr/share/wallpapers/"
rm -rf "$ROOT/usr/share/plasma/look-and-feel/os.morrow.desktop"
cp -r "$SRC/usr/share/lookandfeel-os.morrow.desktop" \
    "$ROOT/usr/share/plasma/look-and-feel/os.morrow.desktop"

# skel defaults
mkdir -p "$ROOT/etc/skel/.config"
cp "$SRC"/etc/skel/.config/* "$ROOT/etc/skel/.config/"

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

echo "==> 6/8  Installing MorrowStore"
mkdir -p "$ROOT/usr/lib/morrowstore" "$ROOT/usr/share/morrowstore"
cp "$SRC"/morrowstore/*.py "$ROOT/usr/lib/morrowstore/"
install -m644 "$SRC/morrowstore/catalog.json" "$ROOT/usr/share/morrowstore/catalog.json"
install -m644 "$SRC/morrowstore/morrowstore.desktop" \
    "$ROOT/usr/share/applications/morrowstore.desktop"
install -m755 "$SRC/morrowstore/morrowstore-launcher.sh" "$ROOT/usr/bin/morrowstore"

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

echo "==> 7/8  Repacking squashfs"
rm -f "$STAGE/casper/filesystem.squashfs"
mksquashfs "$ROOT" "$STAGE/casper/filesystem.squashfs" \
    -comp zstd -Xcompression-level 15 -noappend
du -sx --block-size=1 "$ROOT" | cut -f1 > "$STAGE/casper/filesystem.size"

# boot config + disk identity.  initrd/vmlinuz are left byte-for-byte untouched.
# Which menu file to write depends on the base ISO's bootloader: pre-22.04
# bases have isolinux/, modern ones are GRUB-only for both BIOS and UEFI.
WROTE_MENU=0
if [ -d "$STAGE/isolinux" ]; then
    install -m644 "$SRC/iso/isolinux.cfg" "$STAGE/isolinux/isolinux.cfg"
    echo "    boot menu -> isolinux/isolinux.cfg"
    WROTE_MENU=1
fi
if [ -d "$STAGE/boot/grub" ]; then
    install -m644 "$SRC/iso/grub.cfg" "$STAGE/boot/grub/grub.cfg"
    echo "    boot menu -> boot/grub/grub.cfg"
    WROTE_MENU=1
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

echo "==> 8/8  Building ISO (BIOS + UEFI, 64-bit)"
rm -f "$ISO_OUT"

# Rather than reconstructing the boot structures with -as mkisofs (which
# means knowing whether the base uses isolinux or GRUB, and where its EFI
# image lives -- both of which moved between Ubuntu releases), replay the
# source ISO's own boot setup verbatim and overwrite only the files we
# actually changed. Whatever BIOS+UEFI arrangement the base shipped with
# carries over intact. The initrd is never in the -map list, so rule 1
# above holds by construction.
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
    -boot_image any replay

echo
echo "Built: $ISO_OUT ($(du -h "$ISO_OUT" | cut -f1))"
sha256sum "$ISO_OUT"
echo
echo "Boot structures carried over from the base ISO:"
xorriso -indev "$ISO_OUT" -report_el_torito plain 2>&1 | head -20 || true
echo
echo "Test BIOS boot:  qemu-system-x86_64 -m 3072 -smp 2 -cdrom $ISO_OUT -boot d -vga virtio"
if [ -n "$EFI_IMG" ]; then
    echo "Test UEFI boot:  qemu-system-x86_64 -m 3072 -smp 2 -cdrom $ISO_OUT -boot d -vga virtio \\"
    echo "                   -bios /usr/share/OVMF/OVMF_CODE.fd"
    echo "  (needs the 'ovmf' package on the build/test host)"
fi
