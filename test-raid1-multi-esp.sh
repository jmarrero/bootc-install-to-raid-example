#!/bin/bash
# Example: Install a bootc image onto a RAID 1 array with an ESP on each disk.
#
# This creates 3 loop-backed disks, each with an ESP and a RAID partition,
# assembles a RAID 1 array, installs bootc onto it, and then verifies that
# every ESP received bootloader files — so any disk can boot if another fails.
#
# Usage: sudo ./test-raid1-multi-esp.sh [BASE_IMAGE]
#   BASE_IMAGE is used as the FROM in the Containerfile, with bootc and bootupd
#   COPR RPMs layered on top. Defaults to quay.io/centos-bootc/centos-bootc:stream10.
#
# Prerequisites: podman, mdadm, dosfstools, e2fsprogs, util-linux
# Must be run as root.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

########################################################################
# Build the container image
########################################################################
BASE_IMAGE="${1:-quay.io/centos-bootc/centos-bootc:stream10}"
echo "==> Building ${IMAGE} from ${BASE_IMAGE}"
podman build --build-arg "BASE_IMAGE=${BASE_IMAGE}" -t "$IMAGE" "$SCRIPT_DIR"

LOOPS=()

########################################################################
# Step 1: Create disks, each with an ESP + RAID partition
########################################################################
for i in $(seq 1 "$NUM_DISKS"); do
    disk="${DISK_DIR}/raid-disk${i}.img"

    echo "==> Creating disk ${i}: ${disk}"
    truncate -s "$DISK_SIZE" "$disk"
    loop=$(losetup --show -f -P "$disk")

    sfdisk "$loop" <<SFDISK
label: gpt
size=512M, type=${ESP_TYPE}
type=${RAID_TYPE}
SFDISK
    partx -u "$loop"
    udevadm settle

    mkfs.vfat -F 32 "${loop}p1"

    LOOPS+=("$loop")
done

########################################################################
# Step 2: Assemble RAID 1, format, and mount
########################################################################
RAID_PARTS=()
for loop in "${LOOPS[@]}"; do
    RAID_PARTS+=("${loop}p2")
done

echo "==> Creating RAID 1 array from ${NUM_DISKS} disks"
mdadm --create "$MD_DEV" \
    --level=1 \
    --raid-devices="$NUM_DISKS" \
    --metadata=1.2 \
    --run \
    "${RAID_PARTS[@]}"
mdadm --wait "$MD_DEV" 2>/dev/null || true

echo "==> Formatting RAID array with ext4"
mkfs.ext4 -q "$MD_DEV"

echo "==> Mounting RAID array at ${MOUNTPOINT}"
mkdir -p "$MOUNTPOINT"
mount "$MD_DEV" "$MOUNTPOINT"
mkdir -p "${MOUNTPOINT}/boot"

lsblk --paths "${LOOPS[@]}"

########################################################################
# Step 3: Install bootc onto the RAID array
########################################################################
echo "==> Running bootc install to-existing-root"
podman run \
    --rm \
    --privileged \
    -v "${MOUNTPOINT}:/target" \
    -v /dev:/dev \
    -v /run/udev:/run/udev:ro \
    --pid=host \
    --security-opt label=type:unconfined_t \
    "$IMAGE" \
    bootc install to-existing-root \
        --acknowledge-destructive \
        --target-no-signature-verification \
        --karg=rd.auto \
        /target

########################################################################
# Step 4: Verify every ESP has bootloader files
########################################################################
echo "==> Validating ESP partitions"
ESP_MOUNT="/var/mnt/esp-check"
fail=0

for i in "${!LOOPS[@]}"; do
    esp="${LOOPS[$i]}p1"

    echo "--- Checking ESP on disk $((i+1)) (${esp})"
    mkdir -p "$ESP_MOUNT"
    mount "$esp" "$ESP_MOUNT"

    find "$ESP_MOUNT" -type f
    if [ -d "${ESP_MOUNT}/EFI" ] && [ -n "$(ls -A "${ESP_MOUNT}/EFI")" ]; then
        echo "    OK: EFI directory found with content"
    else
        echo "    FAIL: EFI directory missing or empty on ${esp}"
        fail=1
    fi

    umount "$ESP_MOUNT"
    rmdir "$ESP_MOUNT"
done

########################################################################
# Step 5: Verify RAID superblocks and tear down for VM boot
########################################################################
echo "==> Verifying RAID superblocks on member devices"
for loop in "${LOOPS[@]}"; do
    echo "--- ${loop}p2:"
    mdadm --examine "${loop}p2" || { echo "    FAIL: no valid superblock"; fail=1; }
done

echo "==> Tearing down RAID and loop devices (disk images are preserved)"
umount "$MOUNTPOINT" 2>/dev/null || true
rmdir "$MOUNTPOINT" 2>/dev/null || true
mdadm --stop "$MD_DEV"
for loop in "${LOOPS[@]}"; do
    losetup -d "$loop"
done
sync

########################################################################
# Result
########################################################################
if [ "$fail" -eq 0 ]; then
    echo "==> SUCCESS: All ${NUM_DISKS} ESP partitions have bootloader files"
    echo "==> Disk images ready in ${DISK_DIR}. Run ./boot-vm.sh to test."
else
    echo "==> FAILURE: One or more ESP partitions are missing bootloader files"
    exit 1
fi
