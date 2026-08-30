# Unattended Ubuntu 26.04 Desktop install

`autoinstall.yaml` in this directory automates the Ubuntu install and stages
the niri/Dank setup. **The ISO stays stock** — nothing is rebuilt or
repackaged. Fixing a bug in the setup script means pushing to git, not
re-imaging a 5 GB USB stick.

## Why not a custom ISO?

Building a remastered ISO (Cubic, `livefs-editor`) bakes the setup script in
**at build time**. Every fix means rebuilding and redistributing the image to
every machine that has not been installed yet. Since the config here fetches
the script from GitHub during `late-commands`, the newest version is always
used, and the only thing that ever needs redistributing is a 3 KB YAML file.

## Delivery

Subiquity looks for the config in this order, first match wins:

1. Kernel command line (`subiquity.autoinstallpath=...`)
2. Root of the running installer system
3. cloud-init user data
4. Root of the installation medium

### Route A — CIDATA stick (works with a `dd`-written ISO) ✅ recommended

An Ubuntu ISO written with `dd` is read-only ISO9660, so you **cannot** copy
`autoinstall.yaml` onto it. Use a second, small USB stick instead — cloud-init
scans every block device for one labelled `CIDATA`:

```bash
./make-cidata.sh /dev/sdX        # ⚠️ ERASES that device
```

Boot the machine from the Ubuntu Desktop stick with the CIDATA stick also
plugged in.

The volume label must be exactly `CIDATA`, and the files must be named
`user-data` and `meta-data` at the filesystem root. `make-cidata.sh` handles
both; `autoinstall.yaml` is copied verbatim as `user-data` because it already
carries the `#cloud-config` header and the top-level `autoinstall:` key.

### Route B — single stick

If you write the ISO with a tool that produces a *writable* FAT partition
(Rufus in ISO mode, Ventoy, or `unetbootin`) rather than `dd`, copy
`autoinstall.yaml` into the partition that contains the `casper/` directory.

## What is automated, and what is not

| | |
|---|---|
| Locale, keyboard (`gb`), timezone | automatic |
| Third-party drivers, codecs | automatic |
| Security updates | automatic |
| Dotfiles clone into `~/.dotfiles` | automatic (`late-commands`) |
| **Disk / partitioning** | **interactive on purpose — it erases disks** |
| **Username and password** | **interactive — each student sets their own** |
| niri/Dank setup | one command on first login (a login banner reminds them) |

To make the disk step automatic too, delete `storage` from
`interactive-sections` and add a layout, e.g.:

```yaml
  storage:
    layout:
      name: lvm
```

Do that only when you are certain which disk the machine will install to.

## Before you boot

- **Disable Secure Boot in BIOS.** The DKMS modules this stack needs (nvidia,
  `broadcom-sta`) will not load with it on, and `drivers: install: true`
  otherwise stops for a MOK enrollment password — which ends the unattended
  run anyway.
- Wired ethernet is more reliable than wifi during install; the
  `late-commands` clone needs network.

## Testing it

Do not test on real hardware first. In a VM:

```bash
qemu-img create -f qcow2 test.qcow2 40G
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
    -drive file=test.qcow2,if=virtio \
    -drive file=ubuntu-26.04-desktop-amd64.iso,media=cdrom \
    -drive file=cidata.img,if=virtio,format=raw
```

`make-cidata.sh` can write to a file instead of a device, which is what that
third `-drive` expects.
