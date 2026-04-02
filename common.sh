#!/bin/bash
# Shared configuration and cleanup for RAID 1 multi-ESP test scripts.

NUM_DISKS=3
DISK_SIZE="10G"
DISK_DIR="/var/tmp"
MOUNTPOINT="/var/mnt/raid-test"
MD_DEV="/dev/md/test-raid1"

ESP_TYPE="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
RAID_TYPE="A19D880F-05FC-4D3B-A006-743F0F84911E"

IMAGE="localhost/bootc-raid1-test"

BOOT_ISO_URL="https://mirror.stream.centos.org/10-stream/BaseOS/x86_64/iso/CentOS-Stream-10-latest-x86_64-boot.iso"
BOOT_ISO="${DISK_DIR}/CentOS-Stream-10-boot.iso"
KS_PORT=8099

# Tear down loop devices, RAID array, and disk images.
cleanup() {
    echo "==> Cleaning up"
    umount "$MOUNTPOINT" 2>/dev/null || true
    rmdir "$MOUNTPOINT" 2>/dev/null || true
    mdadm --stop "$MD_DEV" 2>/dev/null || true
    for loop in "${LOOPS[@]}"; do
        mdadm --zero-superblock "${loop}p2" 2>/dev/null || true
        losetup -d "$loop" 2>/dev/null || true
    done
    for i in $(seq 1 "$NUM_DISKS"); do
        rm -f "${DISK_DIR}/raid-disk${i}.img"
    done
}
