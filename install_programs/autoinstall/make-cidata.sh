#!/bin/bash

# =================================================================
# BUILD A CIDATA VOLUME FOR UNATTENDED UBUNTU INSTALLS
#
#   ./make-cidata.sh /dev/sdX        write to a USB stick  (⚠️ ERASES IT)
#   ./make-cidata.sh cidata.img      write to a disk image (for VM testing)
#
# cloud-init's NoCloud datasource scans every block device for a volume
# labelled exactly CIDATA holding `user-data` and `meta-data` at its root.
# That is why this works alongside a dd-written, read-only Ubuntu ISO:
# the config lives on a second device, so the ISO is never modified.
#
# Uses mtools, so writing an IMAGE needs no root at all. Writing to a real
# device needs sudo only for mkfs.
# =================================================================

set -euo pipefail

TARGET="${1:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/autoinstall.yaml"

if [ -z "$TARGET" ]; then
    echo "Usage: $0 /dev/sdX        (USB stick — ERASES IT)"
    echo "       $0 cidata.img      (disk image for VM testing)"
    exit 1
fi

if [ ! -f "$SRC" ]; then
    echo "ERROR: $SRC not found."
    exit 1
fi

for t in mkfs.vfat mcopy; do
    if ! command -v "$t" >/dev/null 2>&1 && ! command -v "/sbin/$t" >/dev/null 2>&1; then
        echo "ERROR: $t not found. Install them with:"
        echo "    sudo apt install -y dosfstools mtools"
        exit 1
    fi
done

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# user-data IS autoinstall.yaml: it already carries the #cloud-config header
# and the top-level `autoinstall:` key that cloud-init hands to subiquity.
cp "$SRC" "$STAGING/user-data"

# meta-data may be empty but must exist, or the datasource is skipped.
# instance-id changing is what makes cloud-init treat this as a new instance.
cat > "$STAGING/meta-data" <<EOF
instance-id: niri-student-$(date +%Y%m%d%H%M%S)
EOF

echo "Contents:"
echo "    user-data  ($(wc -l < "$STAGING/user-data") lines, from autoinstall.yaml)"
echo "    meta-data"
echo ""

if [ -b "$TARGET" ]; then
    echo "⚠️  $TARGET is a block device. This ERASES it:"
    lsblk -o NAME,SIZE,MODEL,MOUNTPOINT "$TARGET" 2>/dev/null || true
    echo ""
    read -r -p "Type ERASE to continue: " CONFIRM
    [ "$CONFIRM" = "ERASE" ] || { echo "Aborted."; exit 1; }

    # Unmount anything already mounted from it, or mkfs refuses.
    for part in $(lsblk -ln -o NAME "$TARGET" | tail -n +2); do
        sudo umount "/dev/$part" 2>/dev/null || true
    done
    sudo umount "$TARGET" 2>/dev/null || true

    sudo mkfs.vfat -n CIDATA "$TARGET"
    sudo mcopy -i "$TARGET" "$STAGING/user-data" "$STAGING/meta-data" ::/
    sync
    echo ""
    echo "Done. Plug this in alongside the Ubuntu Desktop stick and boot from"
    echo "the Ubuntu one."
else
    # 1 MiB is far more than two small text files need, and keeps the image
    # comfortably above the FAT12 minimum.
    rm -f "$TARGET"
    truncate -s 1M "$TARGET"
    mkfs.vfat -n CIDATA "$TARGET" >/dev/null
    mcopy -i "$TARGET" "$STAGING/user-data" "$STAGING/meta-data" ::/
    echo "Done: $TARGET"
    echo ""
    echo "Attach it to a test VM as a raw drive:"
    echo "    -drive file=$TARGET,if=virtio,format=raw"
fi

echo ""
echo "Verify:"
echo "    mdir -i $TARGET ::/"
