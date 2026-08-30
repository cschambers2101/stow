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

Do not test on real hardware first. In a VM.

**Host packages.** `qemu-system-x86` does *not* pull in `qemu-img`, and without
it neither the command below nor libvirt can create a qcow2 disk:

```bash
sudo apt install -y qemu-system-x86 qemu-utils ovmf
```

**Boot the guest with UEFI firmware, not legacy BIOS.** Real machines install
in UEFI mode, and the Secure Boot note above only means anything there — a
BIOS-booted guest silently tests a different path, including a different
bootloader and partition layout. `OVMF_CODE_4M.fd` is the non-Secure-Boot
build, which is what this stack wants. `OVMF_VARS_4M.fd` must be copied first,
because the guest writes to it:

```bash
qemu-img create -f qcow2 test.qcow2 40G
cp /usr/share/OVMF/OVMF_VARS_4M.fd .

qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -machine q35 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
    -drive if=pflash,format=raw,file=OVMF_VARS_4M.fd \
    -drive file=test.qcow2,if=virtio \
    -drive file=ubuntu-26.04.1-desktop-amd64.iso,media=cdrom \
    -drive file=cidata.img,if=virtio,format=raw
```

`make-cidata.sh` can write to a file instead of a device, which is what that
last `-drive` expects.

### Or under libvirt, if you want snapshots

Worth it for repeated runs — reverting a failed setup script takes about half a
second, against half an hour for a reinstall.

```bash
sudo apt install -y virt-manager libvirt-daemon-system libvirt-clients
sudo usermod -aG libvirt "$USER"        # then LOG OUT AND BACK IN
mkdir -p "$HOME"/vms                    # virt-install creates the disk, not the dir

# ONE-TIME: a qcow2 copy of the UEFI variable template. Ubuntu ships only raw,
# and raw nvram cannot be snapshotted. See "The nvram trap" below.
qemu-img convert -f raw -O qcow2 \
    /usr/share/OVMF/OVMF_VARS_4M.fd "$HOME"/vms/OVMF_VARS_4M.qcow2

virt-install --connect qemu:///system --name niri-test \
    --memory 4096 --vcpus 2 --cpu host-passthrough \
    --disk path="$HOME"/vms/niri-test.qcow2,size=40,format=qcow2,bus=virtio \
    --cdrom "$HOME"/Downloads/iso/ubuntu-26.04.1-desktop-amd64.iso \
    --osinfo detect=on,require=off \
    --boot loader=/usr/share/OVMF/OVMF_CODE_4M.fd,loader.readonly=yes,loader.type=pflash,nvram.template="$HOME"/vms/OVMF_VARS_4M.qcow2,nvram.templateFormat=qcow2 \
    --xml ./os/nvram/@format=qcow2 \
    --network network=default,model=virtio \
    --graphics vnc,listen=127.0.0.1 --video virtio --sound none --noautoconsole
```

Install Ubuntu, **log in once and clear the GNOME first-run wizard**, then shut
the guest down and snapshot it. Whatever state you leave it in is what every
revert lands on, so clearing the wizard now means never seeing it again:

```bash
virsh --connect qemu:///system snapshot-create-as niri-test base-install \
    "clean 26.04.1, first login done, before setup script"

# the loop, from here on
virsh --connect qemu:///system snapshot-revert niri-test base-install
virsh --connect qemu:///system start niri-test
```

**Snapshot with the guest shut off, not running.** A running snapshot writes the
guest's whole 4 GB of RAM into the qcow2 on every cycle. Shut-off snapshots are
disk-only and revert in well under a second.

### The nvram trap

`--graphics spice` fails outright — Ubuntu's QEMU is built without SPICE
support — so use `vnc`. `listen=127.0.0.1` keeps the console off the network.
The rest of that command is shaped by one problem, which is worth explaining
because it fails *late*, after the install, when you first try to snapshot:

```
error: Operation not supported: internal snapshots of a VM with pflash
based firmware require QCOW2 nvram format
```

`virt-install` builds the UEFI variable store in raw format, and libvirt will
not snapshot a raw one. Three plausible-looking fixes do not work:

- `--boot nvram.format=qcow2` — rejected, `Unknown --boot options`.
- Setting only `format='qcow2'` on an existing guest — libvirt then refuses to
  convert the raw *template*: `conversion of the nvram template to another
  target format is not supported`.
- Deleting the `template` attributes to sidestep that — libvirt puts them back.

What works is giving libvirt a template that is *already* qcow2, so no
conversion is asked for. That in turn rules out `--boot firmware=efi`:
autoselection matches against the firmware descriptors in
`/usr/share/qemu/firmware/`, and a custom template matches none of them —
`Unable to find 'efi' firmware that is compatible with the current
configuration`. Hence the explicit `loader=...` path instead. `OVMF_CODE_4M.fd`
is the non-Secure-Boot build, which is what this stack wants anyway.

**Retrofitting a guest that is already installed.** Convert the existing file
rather than regenerating from the template — regenerating discards the UEFI
boot entry the Ubuntu installer wrote. Shut the guest down first:

```bash
sudo cp /var/lib/libvirt/qemu/nvram/niri-test_VARS.fd{,.bak}
sudo qemu-img convert -f raw -O qcow2 \
    /var/lib/libvirt/qemu/nvram/niri-test_VARS.fd \
    /var/lib/libvirt/qemu/nvram/niri-test_VARS.qcow2

virsh --connect qemu:///system dumpxml niri-test > niri-test.xml
```

In that file, replace the whole `<os>` opening tag and firmware block — drop
`firmware='efi'` and the `<firmware>` feature list, keep an explicit loader, and
point `<nvram>` at the qcow2 template and the converted file:

```xml
  <os>
    <type arch='x86_64' machine='pc-i440fx-resolute'>hvm</type>
    <loader readonly='yes' type='pflash' format='raw'>/usr/share/OVMF/OVMF_CODE_4M.fd</loader>
    <nvram template='/home/YOU/vms/OVMF_VARS_4M.qcow2' templateFormat='qcow2' format='qcow2'>/var/lib/libvirt/qemu/nvram/niri-test_VARS.qcow2</nvram>
    <boot dev='hd'/>
  </os>
```

Then `virsh --connect qemu:///system define niri-test.xml` and boot it once to
confirm it still finds the bootloader before you snapshot.

### Permissions

Under `qemu:///system` the guest runs as `libvirt-qemu`, which cannot traverse a
`750` home directory to reach the ISO. Grant traverse-only access rather than
copying files around — `--x` is not read:

```bash
setfacl -m u:libvirt-qemu:x "$HOME" "$HOME"/vms
```
