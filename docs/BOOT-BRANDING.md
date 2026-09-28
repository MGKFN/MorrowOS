# Boot branding

Two separate things, with very different risk. Keep them separate.

| | GRUB menu theme | Plymouth splash |
|---|---|---|
| Lives in | plain files on the ISO | **inside the initrd** |
| Built by | `tools/make_grub_theme.py` | `tools/make_plymouth.py` |
| Applied by | `build.sh` step 8 | `scripts/boot-splash.sh`, step 7 |
| If it breaks | text menu, still boots | stock splash, still boots |
| Can it brick the ISO | no | **yes, if unverified** |

---

## Why the splash never worked before v1.3

Plymouth reads its theme **from inside the initrd**, not from the installed
filesystem. Through v1.2 `build.sh` did this:

```sh
cp -r "$SRC/usr/share/plymouth-morrowos" "$ROOT/usr/share/plymouth/themes/morrowos"
chroot "$ROOT" plymouth-set-default-theme morrowos || true
```

Three problems, any one of which is fatal on its own:

1. `plymouth-set-default-theme` without `-R` does not rebuild the initramfs.
2. Even with `-R`, the rebuilt initrd lands in the squashfs at
   `/boot/initrd.img-*`. The ISO boots `casper/initrd`, which is a different
   file and was never touched.
3. The `xorriso -map` list had no initrd entry, so nothing could have reached
   the ISO even if it had been rebuilt.

`|| true` swallowed the only signal that any of this was wrong. The theme
shipped in every release from v1.0 and was never once loaded.

There was a fourth problem waiting behind those: the theme script itself
called `Rectangle()`, which **does not exist** in Plymouth's script module.
The script would have aborted on its first line of drawing even if it had
been in the initrd. CI now greps for this.

---

## Rule 1 is about repacking, not about initrds

> NEVER extract+repack the initrd.

That rule is correct and it still stands. The failure it describes —

```
/cow format specified as 'overlay' and no support found
```

— comes from round-tripping the shipped initrd: casper's scripts live in a
zstd segment and a naive extract-and-repack loses them.

**Regenerating** an initrd is a different operation. `update-initramfs` runs
casper's own initramfs hooks, which lay its scripts down properly. It is how
Ubuntu builds these in the first place. `scripts/boot-splash.sh` regenerates;
it never repacks, and it only ever reads the shipped initrd.

If you find yourself reaching for `unmkinitramfs | cpio -o`, stop — that is
the thing rule 1 forbids.

---

## What the splash step verifies

Nothing is swapped in until all of this passes. Any failure restores the
pristine initrd and the build continues with the stock splash.

- casper is installed and `initramfs-tools` is present in the chroot
- `plymouth-set-default-theme` reports `morrowos` afterwards — not assumed
- `MODULES=most` and `COMPRESS=zstd` are pinned first.
  **`MODULES=most` is not cosmetic**: the default in a chroot can be `dep`,
  which builds an initrd carrying drivers for the *build machine* only. It
  boots on the CI runner and nothing else.
- the new initrd is at least half the size of the base one
- `scripts/casper` is present, and at least 5 casper scripts
- `overlay`, `squashfs` and `loop` are available as modules **or built into
  the kernel** — these three are exactly what the rule-1 panic is about
- `plymouthd` is present
- the MorrowOS theme script and images are present

Then, and only then, `casper/initrd` in the staging tree is replaced.
`md5sum.txt` is regenerated afterwards by `build.sh` — it has to be, or
integrity-check boots fail.

---

## Regenerating assets

Both generators import `tools/dawn_palette.py`, so the boot screens cannot
drift from the desktop.

```sh
python3 tools/make_plymouth.py     # -> usr/share/plymouth-morrowos/
python3 tools/make_grub_theme.py   # -> iso/grub-theme/
python3 tools/check_assets.py      # every path build.sh installs
```

Needs `python3-pil`, `python3-numpy` and a DejaVu or Liberation TTF. CI does
**not** regenerate — the PNGs are committed, and CI only checks they exist.

Two things the generators deliberately avoid:

- **No `Rectangle()`.** Not a Plymouth primitive. Everything is a PNG.
- **No `Image.Text()` for the wordmark.** That needs a font *inside the
  initrd*, and which fonts the plymouth hook pulls in varies by release —
  text can render on the build host and vanish at boot. The wordmark is
  pre-rendered. `Image.Text` is used only for the password and message
  paths, where there is no alternative, and every use is null-guarded.

---

## Turning it off

```
Actions -> Build MorrowOS ISO -> Run workflow -> Brand the boot splash: off
```

or locally:

```sh
sudo MORROW_BOOT_SPLASH=0 bash build.sh ubuntu-base.iso
```

The GRUB theme stays either way; it is independent.

---

## Checking a built ISO

The run summary reports which splash shipped. To confirm on the ISO itself:

```sh
xorriso -osirrox on -indev morrowos-vX.Y.iso -extract /casper/initrd /tmp/initrd
mkdir -p /tmp/ird && unmkinitramfs /tmp/initrd /tmp/ird
find /tmp/ird -path '*themes/morrowos*' | head
find /tmp/ird -name 'overlay.ko*' -o -name 'squashfs.ko*' | head
```

Files under `themes/morrowos` means the splash is in. Nothing means the
build fell back — check the run log for the reason.

---

## Known limitations

- **No custom GRUB font.** GRUB only uses `.pf2` fonts, and naming a font the
  ISO does not carry makes the whole theme fail to load rather than fall
  back. The menu uses the unicode font `grub.cfg` already loads. To improve
  it: `grub-mkfont -o iso/grub-theme/morrow.pf2 -s 16 <some.ttf>` and add
  `item_font` / `title-font` lines to `theme.txt`.
- **The splash is not shown on the verbose entry**, which is intentional —
  that entry drops `quiet splash` so you can see where a boot fails.
- **`nomodeset` gives a low-resolution splash.** Plymouth falls back to a
  basic framebuffer; the layout scales but is coarse.
