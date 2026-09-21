# MorrowOS

**A branded Linux distribution built on Ubuntu 24.04 (noble) + KDE Plasma.**
Live ISO, `MORROWOS` volume label, live user `morrow`, custom app manager.

Built solo by [Tech Haven Studios](https://github.com/MGKFN).

| | |
|---|---|
| **Latest release** | v1.1 — builds in CI, boots BIOS and UEFI |
| **Base** | Kubuntu 24.04.5 (noble), KDE Plasma 5.27 |
| **Architecture** | x86-64 only |
| **Live user** | `morrow`, no password, passwordless sudo |
| **Identity** | "Dawn" — deep indigo, sunrise amber and coral |

> **Repo was renamed** from `HavenOS` to `MorrowOS` mid-project. Old URLs still
> resolve via GitHub's 307 redirect, but update bookmarks and clones.

---

## Status

Split out explicitly, because "written" and "verified" are very different
things when a bug costs an hour-long rebuild to find.

| Component | State |
|---|---|
| Boots to Plasma desktop (BIOS) | ✅ verified |
| Boots under UEFI | ✅ verified |
| CI build pipeline | ✅ verified |
| MorrowStore launches | ✅ verified |
| MorrowStore renders content | 🔧 fix shipped, unconfirmed |
| MorrowStore installs apps | 🔧 fix shipped, unconfirmed |
| MorrowStore icon | 🔧 fixed in v1.2, unbuilt |
| Dawn colour scheme | 🔧 written in v1.2, unbuilt |
| Wallpaper actually applied | 🔧 fixed in v1.2, unbuilt |
| Custom SDDM greeter | ⬜ ships, never seen (autologin bypasses it) |
| Boot splash (Plymouth) | ❌ blocked — see [Boot splash](#boot-splash) |
| Calamares (install to disk) | ❌ live-only |

---

## The Dawn identity

The palette lives in **`tools/dawn_palette.py`** and nowhere else. The colour
scheme, the wallpaper and the icons are all generated from it, so the identity
can't drift between files — which is how v1.0 ended up shipping a colour scheme
that was a name with no colour blocks behind it.

| Role | Colour | |
|---|---|---|
| Night (views, inputs) | `#100E1A` | deepest |
| Header / panel | `#0C0A14` | |
| Window | `#171326` | deep indigo |
| Alt rows / raised | `#201B33` | |
| **Amber** | `#F2A65A` | focus, hover, links, selection |
| **Coral** | `#E8705F` | active state, warm emphasis |
| Ember | `#C2543F` | borders, pressed |
| Text | `#F3ECE3` | warm near-white |
| Dimmed text | `#A497A8` | |

Warm accents carry *emphasis*; body text stays near-white so legibility never
depends on them. Every foreground/background pair the UI renders is checked
against WCAG AA:

```bash
python3 tools/dawn_palette.py     # prints a contrast report, exits non-zero on failure
```

All 17 pairs currently pass, worst case 4.00:1 on the ember border (threshold
3.0 for UI boundaries) and 5.06:1 on negative text (threshold 4.5).

### Regenerating the assets

```bash
python3 tools/make_colorscheme.py   # MorrowDawn.colors + etc/skel/.config/kdeglobals
python3 tools/make_icons.py         # hicolor PNG tree from the SVG marks
python3 tools/make_wallpaper.py     # 1920x1080 PNG/JPG + picker screenshot
python3 tools/check_assets.py       # every path build.sh installs actually exists
```

`make_colorscheme.py` refuses to write if the palette fails its contrast check.

### The mark

A sun breaking a horizon — `usr/share/icons/morrowos-logo.svg`. The rays are
stripped below 32px, where they turn to mush.

The MorrowStore icon shares the sun disc and its gradient, but uses the **full**
disc plus a download arrow rather than the clipped-at-horizon treatment: at icon
sizes, a dome sitting on a wide horizontal bar reads unmistakably as a *hat*.
Verified legible down to 16px.

---

## Download

Builds are published as **release assets**. The ISO exceeds GitHub's 2 GiB
per-asset limit, so it ships as numbered parts — download every `.part*` file
into one folder, then reassemble.

**Linux / macOS**
```bash
cat morrowos-v1.1.iso.part* > morrowos-v1.1.iso
sha256sum -c morrowos-v1.1.iso.sha256
```

**Windows (PowerShell)** — note the absolute paths. .NET resolves a *relative*
path against its own working directory, not PowerShell's, so a bare filename
silently writes the ISO somewhere else entirely.
```powershell
$dir = (Get-Location).Path
$iso = Join-Path $dir "morrowos-v1.1.iso"

$parts = Get-ChildItem -Path $dir -Filter "morrowos-v1.1.iso.part*" | Sort-Object Name
if (-not $parts) { throw "No .part files found in $dir" }
$parts | ForEach-Object { "{0}  {1:N0} bytes" -f $_.Name, $_.Length }

$out = [System.IO.File]::Create($iso)
foreach ($p in $parts) {
    $in = [System.IO.File]::OpenRead($p.FullName)
    $in.CopyTo($out)
    $in.Close()
}
$out.Close()
(Get-FileHash $iso -Algorithm SHA256).Hash.ToLower()
```

v1.0 shipped as 35 × 20 MB parts committed into the repo at `iso/havenos-part-*`
(named before the HavenOS → MorrowOS rename). **Those 681 MB are still there, and
they're why cloning this repo is slow** — even a `--depth 1` clone pulls them,
because they're in the current tree.

That approach is retired. They can be deleted from `iso/` now that releases carry
the ISO; note that deleting them shrinks new shallow clones but *not* the repo's
history, which keeps the blobs permanently. Rewriting history to actually reclaim
the space needs `git filter-repo` and a force push — destructive, and worth doing
deliberately rather than casually.

---

## Building

### In CI (recommended)

`.github/workflows/build-iso.yml` builds the ISO on a GitHub runner and
publishes it. It uses the workflow's built-in `GITHUB_TOKEN`, scoped to this
repo and regenerated per run — **no personal access token is needed, and you
should never paste one anywhere.**

Actions tab → **Build MorrowOS ISO** → **Run workflow**. Takes 40–90 minutes.

| Input | Purpose |
|---|---|
| `base_iso_url` | Base ISO. Must be a casper live ISO containing `casper/filesystem.squashfs` |
| `version` | Release tag, e.g. `v1.2` |
| `publish_parts` | Legacy repo-commit path; leave off |

> cdimage only keeps the **current** point release, so `kubuntu-24.04.5-…` will
> start 404ing when 24.04.6 ships. The workflow fails fast on a short download
> rather than feeding a 404 page into the build. Pinning a self-hosted copy of
> the base ISO is what would make builds properly reproducible.

### Locally

```bash
sudo apt install squashfs-tools xorriso rsync
sudo ./build.sh path/to/base.iso
```

Override the output name with `ISO_OUT=morrowos-v1.2.iso`.

### Testing both boot paths

```bash
# BIOS
qemu-system-x86_64 -m 3072 -smp 2 -cdrom morrowos-v1.1.iso -boot d -vga virtio

# UEFI  (needs: sudo apt install ovmf)
qemu-system-x86_64 -m 3072 -smp 2 -cdrom morrowos-v1.1.iso -boot d -vga virtio \
    -bios /usr/share/OVMF/OVMF_CODE.fd
```

VirtualBox: use the **VMSVGA** graphics controller. UEFI is a checkbox under
System → Motherboard, so both paths can be tested there without QEMU.

Boot menu: **live**, **safe graphics** (`nomodeset`), **verbose** (drops
`quiet splash` — use this to see where a failure actually happens).

---

## Three rules that must not be broken

Each was learned by breaking it. Also documented at the top of `build.sh`.

### 1. Never extract or repack the initrd

Its 275 casper scripts live in a zstd segment. Repacking destroys them and you
get a BusyBox shell with `/cow ... no support found`. Pass configuration on the
kernel command line instead. Ship it byte-identical — md5
`861a117f845609683f50b966b5975b17`.

`build.sh` never puts the initrd in its `-map` list, so this holds by
construction.

### 2. Never blacklist `vmwgfx`

VirtualBox's VMSVGA adapter *is* an emulated VMware SVGA device and needs
`vmwgfx` for KMS. Blacklisting it means no DRM device, so X never starts and
SDDM hangs after `graphical.target`.

### 3. Never force a `Driver` in `xorg.conf.d`

Install all drivers and let X autodetect. Forcing one produces conflicting
`Device` sections and X refuses to start.

### And two corollaries

- **Never hand-write `plasma-org.kde.plasma.desktop-appletsrc.`** A partial file
  makes plasmashell render an empty desktop. This is why the wallpaper is applied
  at first login through `plasma-apply-wallpaperimage` rather than shipped as
  config.
- **Never force `LookAndFeelPackage`** at an incomplete package, and never force
  `Backend=OpenGL` / `GLCore=true` in `kwinrc` — KWin won't start under software
  rendering, which is any VM without 3D acceleration.

---

## Repository layout

```
build.sh                          rebuild the ISO from a base ISO
.github/workflows/build-iso.yml   CI build + release publishing

tools/
  dawn_palette.py                 THE palette + WCAG contrast validator
  make_colorscheme.py             generates MorrowDawn.colors + kdeglobals
  make_icons.py                   rasterises SVG marks into a hicolor tree
  make_wallpaper.py               generates the Dawn wallpaper
  check_assets.py                 verifies every path build.sh installs exists
  upload_iso_parts.py             legacy split-part uploader

etc/
  os-release, lsb-release         OS identity
  casper.conf                     live-session user config
  sddm.conf                       display manager + autologin
  X11/Xwrapper.config             lets X start without console-owner checks
  plymouth/plymouthd.conf         selects the morrowos boot theme
  skel/.config/                   KDE defaults copied into every new user
    kdeglobals                    GENERATED — Dawn colours, Papirus icons
    kwinrc                        Breeze Dark decoration, compositing off
    plasmarc, kscreenlockerrc
    kwalletrc                     wallet off (blocks session start otherwise)
    baloofilerc                   indexer off (pegs CPU on live boot)
    autostart/
      morrowos-firstrun.desktop   triggers first-login desktop setup

usr/
  local/bin/morrowos-firstrun.sh  applies wallpaper + colour scheme at login
  share/
    icons/
      morrowos-logo.svg           the mark: sun over horizon
      morrowstore.svg             app icon: sun + download arrow
      hicolor/                    GENERATED PNG tree, 16px–256px
    color-schemes/MorrowDawn.colors   GENERATED
    wallpapers/MorrowOS/          GENERATED
    plymouth-morrowos/            boot splash (see Boot splash)
    sddm-morrowos/                login screen (QML, unvalidated)
    lookandfeel-os.morrow.desktop/

morrowstore/                      the App Manager (GTK4 / libadwaita)
  main.py                         Adw.Application entry point
  app_window.py                   window, category sidebar, search, grid
  app_card.py                     per-app card widget
  installer.py                    APT / Flatpak / Snap / deb_url backend
  catalog.py                      catalog loader with built-in fallback
  catalog.json                    default catalog
  morrowstore-launcher.sh         env setup + logging wrapper
  morrowstore.desktop             menu entry

iso/
  grub.cfg                        boot menu for GRUB bases (22.04+)
  isolinux.cfg                    boot menu for isolinux bases (pre-22.04)
  disk-info.txt                   .disk/info — casper reads this
```

---

## MorrowStore

GTK4 + libadwaita, Python. Logs to `~/.cache/morrowstore.log`.

| Method | Mechanism | Needs |
|---|---|---|
| `apt` | `pkexec apt-get install` | running polkit agent |
| `flatpak` | `flatpak install` | configured remote |
| `snap` | `pkexec snap install` | running polkit agent |
| `deb_url` | download + `pkexec apt-get install ./pkg.deb` | polkit agent, network |

`deb_url` exists for Tech Haven Studios' own apps, which aren't in any repo:

```json
{
  "name": "My App",
  "method": "deb_url",
  "url": "https://.../app.deb",
  "package": "the-dpkg-package-name",
  "category": "Development",
  "icon": "applications-development",
  "description": "..."
}
```

`package` must match what `dpkg -s` reports, or installed-state detection won't
work. No entries ship by default — add real ones.

---

## Boot splash

**The Plymouth theme ships but is probably not reachable.** Plymouth loads its
theme from inside the initrd, and rule 1 forbids repacking it.
`plymouth-set-default-theme morrowos` runs in the chroot, but that writes into
the squashfs, which isn't mounted yet when the splash is drawn.

This has not been definitively tested — it may be that a cmdline
`plymouth.theme=` plus a theme present in the base initrd's search path would
work. Until someone verifies it, **expect a stock boot splash.** It is the one
piece of branding that the initrd rule genuinely blocks.

---

## Bugs found and fixed

### v1.0 development

Each of these independently produced a black screen with a working cursor, and
several were stacked on top of each other.

| Bug | Cause | Fix |
|---|---|---|
| `kwin-x11` missing | `plasma-desktop` only *recommends* it | install explicitly |
| `dbus-launch` missing | `dbus-x11` not pulled in; `startplasma-x11` needs a session bus | install explicitly |
| `install: invalid user 'ubuntu'` | initrd's `casper.conf` hardcodes `USERNAME=ubuntu` | `username=morrow` on the kernel cmdline |
| `/cow ... no support found` → BusyBox | initrd repacked, destroying the zstd segment with all 275 casper scripts | never touch the initrd (**rule 1**) |
| `vmwgfx unsupported hypervisor` | VMware DRM driver probing on Hyper-V | let it load; `hyperv_drm` / `vboxvideo` coexist |
| SDDM hangs after `graphical.target` | `vmwgfx` blacklisted, but VMSVGA *is* VMware SVGA | remove the blacklist (**rule 2**) |
| X refuses to start | two conflicting `Device` sections in `xorg.conf.d` | let X autodetect (**rule 3**) |
| Blank desktop | hand-written partial `appletsrc` | delete it, let Plasma generate its own |
| Blank desktop | `LookAndFeelPackage` forced at a skeleton package | don't force it |
| KWin won't start in VMs | `kwinrc` forced `Backend=OpenGL` + `GLCore=true` | remove; KWin falls back to software rendering |
| Integrity-check boot fails | `md5sum.txt` stale after repacking squashfs | regenerate at build time |
| Colour scheme not applied | the scheme was a name with no colour blocks | write out actual colour definitions |
| MorrowStore crash | sidebar built before the grid existed | build grid first, set state before connecting signals |
| Greeter risk | SDDM theme imported `SddmComponents 2.0`, used undefined `sessionIndex` | import removed, property declared |

### v1.1 — stability

| Bug | Cause | Fix |
|---|---|---|
| MorrowStore window blank | GTK4 renders via GSK, which needs a working GL context. With compositing off and no 3D accel, GL init fails **silently** — empty log, blank surface, frame still drawn by KWin | force `GSK_RENDERER=cairo` in the launcher |
| Installs do nothing | `pkexec` needs a graphical polkit agent to prompt for auth; without one it no-ops with no error | install `polkit-kde-agent-1`, check at install time, surface a real error |
| Every flatpak install fails | flathub remote never registered, so half the catalog could never install | `flatpak remote-add flathub` at build time |
| No installed-state in UI | backend had `is_installed()`; the UI never called it | `AppCard` takes an `installed` flag |
| Build fails: no `isolinux/` | Ubuntu dropped isolinux for GRUB-for-BIOS around 22.04 and stopped shipping `boot/grub/efi.img` — both halves of the original boot code targeted a layout that no longer exists | detect layout, write the matching menu; assemble with `xorriso -boot_image any replay` |
| CI: 4-minute failure | base ISO URL 404'd; cdimage only keeps the current point release | pin `24.04.5`, fail fast on a short download |
| CI: release upload rejected | ISO exceeds GitHub's 2 GiB per-asset limit | split into `.partNN` under the cap; idempotent publish |

### v1.2 — branding

| Bug | Cause | Fix |
|---|---|---|
| MorrowStore shows a generic icon | `usr/share/icons/morrowstore.png` existed in the source tree and `build.sh` **never copied it into the image** — `Icon=morrowstore` pointed at nothing | install into the hicolor tree + pixmaps, refresh the cache, and hard-fail the build if the icon is absent |
| Wallpaper never applied | the asset shipped, but wallpaper selection lives in `appletsrc`, which rule 4 forbids writing | apply at first login via `plasma-apply-wallpaperimage` |
| `autostart/` would be skipped | skel was copied with a non-recursive `cp`, which silently drops subdirectories | `cp -r` |
| Stale scheme references | look-and-feel `defaults` still named `MorrowDark` and `breeze-dark` after both changed | regenerate from the palette; `check_assets.py` catches dangling paths |

---

## Known gaps

- **Boot splash blocked** by the initrd rule (above)
- **Custom SDDM greeter never seen** — autologin bypasses it. Enabling it on a
  live ISO is risky: a broken greeter with autologin off locks you out of the
  session entirely, so it needs its own pass
- **Calamares rebranded but not configured** — live-only, cannot install to disk
- **Icon set is first-party only** — MorrowStore and the OS mark are custom;
  Papirus-Dark carries everything else. Deliberate: a half-finished full set
  looks worse than clean stock icons
- **Settings app is stock** — System Settings' `.desktop` is patched in place to
  read "MorrowOS Settings"; the app underneath is unmodified
- **No custom Plasma widget theme** — Breeze follows the colour scheme, so Dawn
  recolours the panel for free. A full SVG theme is a large job for a small delta
- **ISO is ~2 GB+**, up from v1.0's 682 MB — mostly the Kubuntu base, partly the
  preinstalled apps. Won't fit a 2 GB USB stick
- **v1.0's base ISO is unknown.** v1.0 built against an isolinux-based ISO, but
  24.04.5 is GRUB-only, so the original base was something else. Worth
  identifying: a different base means a different kernel than the `6.8.0-139` in
  the v1.0 notes, and any graphics regression would trace there first
- **Compositing off by default** for VM stability. Re-enable with
  <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>F12</kbd> after turning on 3D acceleration

---

## Roadmap

### v1.2 — identity (current)
- [x] Dawn palette, contrast-validated and generated from one source
- [x] Rising-sun mark and MorrowStore icon
- [x] Dawn wallpaper, checked for text legibility
- [x] Icon actually installed; wallpaper actually applied
- [ ] **Build and verify on hardware**

### v1.3 — installable
- [ ] Configure Calamares so MorrowOS installs to disk
- [ ] Validate the custom SDDM greeter safely
- [ ] Partitioning and bootloader install tested on both firmware types

### v1.4 — depth
- [ ] Settle whether the boot splash is reachable without touching the initrd
- [ ] Real Settings app rather than a rebranded System Settings
- [ ] Tech Haven Studios apps in the catalog via `deb_url`
- [ ] Removal and update support in MorrowStore

### Later
- [ ] Persistence for live USB
- [ ] Own APT repository so first-party apps update normally
- [ ] Secure Boot signing
- [ ] Trim the ISO back toward something that fits a 2 GB stick

---

## Debugging

1. Boot the **verbose** menu entry — drops `quiet splash`, shows where it stops
2. `~/.cache/morrowstore.log` — app manager failures
3. `~/.cache/morrowos-firstrun.log` — wallpaper / colour scheme application

All three exist so the next round starts from evidence rather than inference.

---

## Credentials

Live user `morrow`, no password, passwordless sudo — set by casper at boot via
`username=morrow` on the kernel command line, not baked into the image.

This is a **live/demo image**. Don't expose it to an untrusted network.
