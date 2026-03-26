#!/bin/bash
# Boot a VM from the RAID 1 disk images created by test-raid1-multi-esp.sh.
#
# Usage: sudo ./boot-vm.sh [--disk N]
#   --disk N   Boot from only disk N (e.g. --disk 1), simulating a
#              disk failure scenario with a degraded RAID 1.
#   Without flags, all disks are attached (full RAID 1 array).
#
# Prerequisites: qemu-system-x86_64, edk2-ovmf (UEFI firmware)
# Must be run as root (disk images are owned by root).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

########################################################################
# Parse arguments
########################################################################
DISKS=()
if [ "${1:-}" = "--disk" ]; then
    if [ -z "${2:-}" ] || [ "$2" -lt 1 ] || [ "$2" -gt "$NUM_DISKS" ] 2>/dev/null; then
        echo "Error: --disk requires a number between 1 and ${NUM_DISKS}" >&2
        exit 1
    fi
    DISKS=("${DISK_DIR}/raid-disk${2}.img")
    echo "==> Booting VM from disk ${2} only (degraded RAID 1)"
else
    for i in $(seq 1 "$NUM_DISKS"); do
        DISKS+=("${DISK_DIR}/raid-disk${i}.img")
    done
    echo "==> Booting VM from all ${NUM_DISKS} disks (full RAID 1)"
fi

########################################################################
# Locate OVMF firmware
########################################################################
OVMF=""
for candidate in \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd; do
    if [ -f "$candidate" ]; then
        OVMF="$candidate"
        break
    fi
done
if [ -z "$OVMF" ]; then
    echo "Error: OVMF firmware not found. Install edk2-ovmf." >&2
    exit 1
fi

########################################################################
# Verify disk images exist
########################################################################
for disk in "${DISKS[@]}"; do
    if [ ! -f "$disk" ]; then
        echo "Error: ${disk} not found. Run test-raid1-multi-esp.sh first." >&2
        exit 1
    fi
done

########################################################################
# Build qemu drive arguments
########################################################################
DRIVE_ARGS=()
for i in "${!DISKS[@]}"; do
    DRIVE_ARGS+=(-drive "file=${DISKS[$i]},format=raw,if=virtio,index=${i}")
done

########################################################################
# Launch the VM
########################################################################
echo "==> Starting qemu (press Ctrl-A X to quit)"
qemu-system-x86_64 \
    -machine q35,accel=kvm \
    -cpu host \
    -m 2048 \
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF}" \
    "${DRIVE_ARGS[@]}" \
    -nographic
