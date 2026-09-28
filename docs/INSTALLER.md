# Installing MorrowOS to disk

Kubuntu's live ISO already carries Calamares, so MorrowOS has always *had* an
installer — it just said Kubuntu, because nothing in the build touched it.
`scripts/installer-branding.sh` fixes that.

## What the build changes, and what it deliberately does not

**Changed — exactly one line of Kubuntu's config:**

```
branding: kubuntu   ->   branding: morrowos
```

**Added:** `/etc/calamares/branding/morrowos/` and the Name/Icon of whichever
`.desktop` launches Calamares.

**Not touched:** the module sequence in `settings.conf`, and every file under
`/etc/calamares/modules/`.

That restraint is the point. Kubuntu's sequence — which modules run, in what
order, with what options — is tested against this exact base. Replacing it
with a hand-written one is how a remaster ends up with an installer that
reaches 100% and leaves an unbootable disk. The branding line is cosmetic and
safe; the sequence is not, so it is left alone.

## The check that actually matters

The build reports, read-only:

```
unpackfs -   source: "/cdrom/casper/filesystem.squashfs"
unpackfs source looks right
```

`unpackfs` is the module that copies the live filesystem onto the target.
If its source path is wrong, the install runs happily to 100% and produces
nothing. The build warns if the path doesn't look like a live squashfs but
does **not** rewrite it — that path depends on how the base ISO is mounted,
and guessing at it is worse than reporting it.

If you ever see that warning, stop and check before trusting an install.

## Version stamping

`branding.desc` ships with a `@VERSION@` placeholder, substituted at build
time from the ISO filename (`morrowos-v1.3.iso` → `1.3`). CI fails if the
placeholder is missing from the repo copy, because a hardcoded version there
would silently ride along in every future release.

If the running installer shows a literal `@VERSION@`, substitution didn't
happen — check the build log for the installer branding step.

## What is still not done

- **No custom module configuration.** Partitioning, users, locale and
  bootloader all behave exactly as Kubuntu's installer does. That is fine,
  and changing it is a much larger job than branding.
- **No `stylesheet.qss`.** Calamares accepts one, but a partial stylesheet
  fights the active KDE palette and readily produces unreadable text — the
  same failure class as hand-writing a partial Plasma config. The `style:`
  block in `branding.desc` covers the sidebar, which is the surface that
  carries the brand.
- **The slideshow is pre-rendered PNGs, not QML-drawn text.** No fonts to
  resolve, no layout to break on an odd window size. If `show.qml` fails to
  load, Calamares logs it and shows an empty slideshow area — the install
  still proceeds. Keep it that way: nothing in the slideshow should be
  load-bearing.

## Changing what ships preinstalled

The app set is a named list at the top of `build.sh`:

```sh
MORROW_APPS="
    firefox
    thunderbird
    libreoffice-writer libreoffice-calc libreoffice-impress
    ...
"
```

Edit it freely. A bad package name there does **not** kill the build: the
batch install is retried one package at a time and the build reports what it
couldn't install and carries on. `MORROW_SYSTEM` above it is the opposite —
those are required for the desktop to come up at all, and a failure there is
fatal on purpose.

Everything you add grows the ISO. Check the size the build reports at the end.

## Testing it

Booting the live session is not a test of the installer. Give QEMU a blank
disk and actually run it:

```sh
qemu-img create -f qcow2 test-target.qcow2 25G
qemu-system-x86_64 -m 4096 -smp 2 \
  -cdrom morrowos-vX.Y.iso \
  -drive file=test-target.qcow2,format=qcow2 \
  -boot d -vga virtio
```

Install, then boot the disk alone (drop `-cdrom` and `-boot d`). The things
worth checking on that first disk boot: the GRUB menu says MorrowOS, the
Dawn splash appears, and `cat /etc/os-release` says MorrowOS rather than
Kubuntu.
