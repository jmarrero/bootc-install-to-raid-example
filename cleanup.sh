#!/bin/bash
# Clean up loop devices, RAID array, and disk images created by
# test-raid1-multi-esp.sh.
#
# Usage: sudo ./cleanup.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Find any loop devices backed by our disk images.
LOOPS=()
for i in $(seq 1 "$NUM_DISKS"); do
    img="${DISK_DIR}/raid-disk${i}.img"
    loop=$(losetup -j "$img" 2>/dev/null | cut -d: -f1) || true
    if [ -n "$loop" ]; then
        LOOPS+=("$loop")
    fi
done

cleanup

# Clean up Anaconda artifacts
rm -f "${DISK_DIR}/anaconda-vmlinuz"
rm -f "${DISK_DIR}/anaconda-initrd.img"
rm -f "${DISK_DIR}/OVMF_VARS.fd"
rm -rf "${DISK_DIR}"/ks-serve.*
