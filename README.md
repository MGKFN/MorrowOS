# MorrowOS v1.0 "Dawn"

Ubuntu 24.04 (noble) + KDE Plasma, rebranded as an independent OS.
Live ISO, `MORROWOS` volume label, live user `morrow`.

Built by TechHaven Studios.

---

## Layout

```
build.sh                                 rebuild the ISO from an Ubuntu base ISO
etc/
  os-release, lsb-release                OS identity (MorrowOS 1.0 "Dawn")
  casper.conf                            live-session user config
  sddm.conf                              display manager + autologin
  X11/Xwrapper.config                    lets X start without console-owner checks
  plymouth/plymouthd.conf                selects the morrowos boot theme
  skel/.config/                          KDE defaults copied into every new user
    kdeglobals                           MorrowDark colour scheme, icons, widget style
    kwinrc                               Breeze Dark window decoration
    plasmarc, kscreenlockerrc
    kwalletrc                            wallet off (blocks session start otherwise)
    baloofilerc                          file indexer off (pegs CPU on live boot)
usr/share/
  plymouth-morrowos/                     boot splash (script + theme descriptor)
  sddm-morrowos/                         login screen (QML)
  lookandfeel-os.morrow.desktop/         Plasma look-and-feel package
  color-schemes/MorrowDark.colors        KDE colour scheme
  wallpapers/MorrowOS/                   generated wallpaper
morrowstore/                             the App Manager (GTK4 / libadwaita)
  main.py                                Adw.Application entry point
  app_window.py                          window, category sidebar, search, grid
  app_card.py                            per-app card widget
  installer.py                           threaded APT / Flatpak / Snap backend
  catalog.py                             catalog loader with built-in fallback
  catalog.json                           12-app default catalog
  morrowstore.desktop                    menu entry
iso/
  isolinux.cfg                           boot menu (live / safe graphics / verbose)
  disk-info.txt                          .disk/info — casper reads this
```

## Rebuild

```bash
sudo apt install squashfs-tools xorriso isolinux syslinux-common rsync
sudo ./build.sh ubuntu-24.04-desktop-amd64.iso
```

Produces `morrowos-v1.0.iso` and prints its SHA256.

## Test

```bash
qemu-system-x86_64 -m 3072 -smp 2 -cdrom morrowos-v1.0.iso -boot d -vga virtio
```

VirtualBox: use the **VMSVGA** graphics controller.

Boot menu entries: **live**, **safe graphics** (`nomodeset`), **verbose** (drops
`quiet splash`, use this to see where a failure happens).

---

## Bugs found and fixed during development

Each of these independently produced a black screen with a working mouse cursor,
and several were stacked on top of each other.

| Bug | Cause | Fix |
|---|---|---|
| `kwin-x11` missing | `plasma-desktop` only *recommends* it; installed with `--no-install-recommends` | install explicitly |
| `dbus-launch` missing | `dbus-x11` not pulled in; `startplasma-x11` needs a session bus | install explicitly |
| `install: invalid user 'ubuntu'` | initrd's `casper.conf` hardcodes `USERNAME=ubuntu` | pass `username=morrow` on the kernel cmdline |
| `/cow ... no support found` → BusyBox | initrd was extracted and repacked, destroying the zstd `main` segment holding all 275 casper scripts | never touch the initrd; ship it byte-identical |
| `vmwgfx unsupported hypervisor` | VMware DRM driver probing on Hyper-V | let it load; `hyperv_drm` / `vboxvideo` coexist |
| SDDM hangs after `graphical.target` | `vmwgfx` blacklisted, but VirtualBox VMSVGA *is* VMware SVGA — no DRM device, so X never started | remove the blacklist |
| X refuses to start | two conflicting `Device` sections in `xorg.conf.d` (`vesa` + `modesetting`) | remove both, install all drivers, let X autodetect |
| Blank desktop | hand-written partial `plasma-org.kde.plasma.desktop-appletsrc` | delete it, let Plasma generate its own |
| Blank desktop | `LookAndFeelPackage` forced at a two-file skeleton package | don't force it; set colour scheme / icons individually |
| KWin won't start in VMs | `kwinrc` forced `Backend=OpenGL` + `GLCore=true` | remove; KWin falls back to software rendering on its own |
| integrity-check boot fails | `md5sum.txt` stale after repacking squashfs | regenerate at build time |
| Greeter risk | SDDM theme imported `SddmComponents 2.0` and used an undefined `sessionIndex` | import removed, property declared; stock `breeze` active until validated on hardware |

### Re-enabling the MorrowOS login screen

The custom greeter ships but is not active. Once the desktop comes up, switch it on:

```ini
# /etc/sddm.conf
[Theme]
Current=morrowos
```

## Known / not yet done

- Custom greeter not yet validated on real hardware
- Calamares installer not configured (live-only)

## Credentials

Live user `morrow`, no password, passwordless sudo (set by casper).

## v1.1 changes (stability pass)

- **MorrowStore blank window**: forced `GSK_RENDERER=cairo` in the launcher.
  GTK4/libadwaita needs a working GL context to render via GSK; in VMs
  without 3D acceleration (VMware SVGA/vmwgfx, compositing off) GL init
  can fail with no error output, leaving the window blank. Software
  rendering sidesteps this. Override by exporting `GSK_RENDERER` before
  launch on hardware with working 3D accel.
- **MorrowStore installs silently failing**: `pkexec` needs a running
  graphical polkit agent to prompt for auth — without one it just no-ops.
  `polkit-kde-agent-1` + `policykit-1` are now installed and checked for
  at install time (surfaces a real error instead of nothing happening).
  Flathub is now registered system-wide at build time — previously no
  flatpak install could ever succeed (VS Code, Spotify, OBS, Discord,
  Blender, Steam — half the catalog) because the remote didn't exist.
- **Installed-state UI**: was a backend-only feature; `AppCard` now takes
  an `installed` flag and shows a disabled "Installed" pill instead of
  "Install".
- **New `deb_url` install method**: for Tech Haven Studios' own apps that
  aren't in any repo. Catalog entry shape:
  ```json
  {"name": "...", "method": "deb_url", "url": "https://.../app.deb",
   "package": "the-actual-dpkg-package-name", "category": "...",
   "icon": "...", "description": "..."}
  ```
  `package` should match the name `dpkg -s` reports, so "installed" state
  detection works. No entries added yet — add your own real ones.
- **Preinstalled apps**: Firefox, LibreOffice (Writer+Calc), VLC now
  installed into the squashfs at build time instead of being MorrowStore-only.
- **Icon theme**: switched default from stock `breeze-dark` to
  `papirus-icon-theme`'s Papirus-Dark. This is a real, complete icon set
  swap, not a hand-drawn MorrowOS set — that's still open.
- **Settings app branding**: System Settings' `.desktop` entry is patched
  in-place (`Name=MorrowOS Settings`, `Icon=preferences-system`) rather
  than replaced with a new app — building a standalone settings app from
  scratch was out of scope for this pass.
- **UEFI + BIOS hybrid boot, 64-bit**: final `xorriso` step now adds a
  second El Torito boot entry (`-eltorito-alt-boot`) pointing at the base
  ISO's existing EFI boot image, plus `-isohybrid-gpt-basdat`. BIOS/isolinux
  boot path is untouched. `build.sh` auto-detects the EFI image path from
  the extracted base ISO and falls back to BIOS-only with a clear message
  if it can't find one — check the printed message on first run.
