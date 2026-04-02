#!/bin/bash
# Example: Install a bootc image onto a RAID 1 array with an ESP on each disk
# using Anaconda and a kickstart file inside a QEMU VM.
#
# This creates 3 blank disk images, boots Anaconda from a CentOS boot ISO,
# and uses a kickstart to partition the disks, assemble RAID 1, and deploy
# the bootc container image via the ostreecontainer kickstart command.
#
# Usage: sudo ./test-raid1-multi-esp.sh <REGISTRY_IMAGE_URL> [BASE_IMAGE]
#   REGISTRY_IMAGE_URL  Registry URL to push the built image to (required)
#                       e.g. quay.io/<user>/bootc-raid1-test:latest
#   BASE_IMAGE          FROM image for the Containerfile (optional)
#                       Defaults to quay.io/centos-bootc/centos-bootc:stream10
#
# Prerequisites: podman, qemu-system-x86_64, edk2-ovmf, curl, python3
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
# Parse arguments
########################################################################
if [ $# -lt 1 ]; then
    echo "Usage: $0 <REGISTRY_IMAGE_URL> [BASE_IMAGE]" >&2
    echo "  e.g. $0 quay.io/<user>/bootc-raid1-test:latest" >&2
    exit 1
fi
IMAGE_URL="$1"
BASE_IMAGE="${2:-quay.io/centos-bootc/centos-bootc:stream10}"

########################################################################
# Build and push the container image
########################################################################
echo "==> Building ${IMAGE} from ${BASE_IMAGE}"
podman build --build-arg "BASE_IMAGE=${BASE_IMAGE}" -t "$IMAGE" "$SCRIPT_DIR"

echo "==> Pushing ${IMAGE} to ${IMAGE_URL}"
podman push "$IMAGE" "$IMAGE_URL"

########################################################################
# Step 1: Create blank disk images
########################################################################
for i in $(seq 1 "$NUM_DISKS"); do
    disk="${DISK_DIR}/raid-disk${i}.img"
    echo "==> Creating disk ${i}: ${disk}"
    truncate -s "$DISK_SIZE" "$disk"
done

########################################################################
# Step 2: Download boot ISO (if not cached)
########################################################################
if [ -f "$BOOT_ISO" ]; then
    echo "==> Using cached boot ISO: ${BOOT_ISO}"
else
    echo "==> Downloading boot ISO to ${BOOT_ISO}"
    curl -L -o "$BOOT_ISO" "$BOOT_ISO_URL"
fi

########################################################################
# Step 3: Extract kernel and initrd from ISO
########################################################################
echo "==> Extracting kernel and initrd from boot ISO"
ISO_MNT=$(mktemp -d "${DISK_DIR}/iso-mnt.XXXXXX")
mount -o loop,ro "$BOOT_ISO" "$ISO_MNT"
cp "${ISO_MNT}/images/pxeboot/vmlinuz" "${DISK_DIR}/anaconda-vmlinuz"
cp "${ISO_MNT}/images/pxeboot/initrd.img" "${DISK_DIR}/anaconda-initrd.img"
umount "$ISO_MNT"
rmdir "$ISO_MNT"

########################################################################
# Step 4: Generate kickstart from template
########################################################################
echo "==> Generating kickstart"
KS_DIR=$(mktemp -d "${DISK_DIR}/ks-serve.XXXXXX")
sed "s|@@IMAGE_URL@@|${IMAGE_URL}|g" \
    "${SCRIPT_DIR}/kickstart.cfg.in" > "${KS_DIR}/kickstart.cfg"

echo "--- Kickstart contents:"
cat "${KS_DIR}/kickstart.cfg"

########################################################################
# Step 5: Start temporary HTTP server for kickstart
########################################################################
echo "==> Starting HTTP server on port ${KS_PORT}"
python3 -m http.server "$KS_PORT" --directory "$KS_DIR" &
HTTP_PID=$!
# shellcheck disable=SC2064
trap "kill $HTTP_PID 2>/dev/null || true; rm -rf '$KS_DIR'" EXIT

########################################################################
# Step 6: Locate OVMF firmware
########################################################################
OVMF_CODE=""
for candidate in \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd; do
    if [ -f "$candidate" ]; then
        OVMF_CODE="$candidate"
        break
    fi
done
if [ -z "$OVMF_CODE" ]; then
    echo "Error: OVMF firmware not found. Install edk2-ovmf." >&2
    exit 1
fi

OVMF_VARS_ORIG=""
for candidate in \
    /usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/edk2/x64/OVMF_VARS.fd; do
    if [ -f "$candidate" ]; then
        OVMF_VARS_ORIG="$candidate"
        break
    fi
done
if [ -z "$OVMF_VARS_ORIG" ]; then
    echo "Error: OVMF_VARS firmware not found. Install edk2-ovmf." >&2
    exit 1
fi

OVMF_VARS_COPY="${DISK_DIR}/OVMF_VARS.fd"
cp "$OVMF_VARS_ORIG" "$OVMF_VARS_COPY"

########################################################################
# Step 7: Run Anaconda in QEMU
########################################################################
echo "==> Running Anaconda installer in QEMU"
timeout 1800 qemu-system-x86_64 \
    -machine q35,accel=kvm \
    -cpu host \
    -m 4096 \
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,file=${OVMF_VARS_COPY}" \
    -cdrom "$BOOT_ISO" \
    -drive "file=${DISK_DIR}/raid-disk1.img,format=raw,if=virtio,index=0" \
    -drive "file=${DISK_DIR}/raid-disk2.img,format=raw,if=virtio,index=1" \
    -drive "file=${DISK_DIR}/raid-disk3.img,format=raw,if=virtio,index=2" \
    -nic user,model=virtio-net-pci \
    -nographic \
    -kernel "${DISK_DIR}/anaconda-vmlinuz" \
    -initrd "${DISK_DIR}/anaconda-initrd.img" \
    -append "inst.stage2=cdrom inst.ks=http://10.0.2.2:${KS_PORT}/kickstart.cfg console=ttyS0 inst.notmux"

echo "==> Anaconda installation completed"

# Clean up HTTP server (trap handles this, but be explicit)
kill "$HTTP_PID" 2>/dev/null || true
rm -rf "$KS_DIR"

########################################################################
# Step 8: Verify every ESP has bootloader files
########################################################################
echo "==> Validating ESP partitions"
ESP_MOUNT="/var/mnt/esp-check"
fail=0

for i in $(seq 1 "$NUM_DISKS"); do
    disk="${DISK_DIR}/raid-disk${i}.img"
    loop=$(losetup --show -f -P "$disk")

    echo "--- Checking ESP on disk ${i} (${loop}p1)"
    mkdir -p "$ESP_MOUNT"
    mount "${loop}p1" "$ESP_MOUNT"

    find "$ESP_MOUNT" -type f
    if [ -d "${ESP_MOUNT}/EFI" ] && [ -n "$(ls -A "${ESP_MOUNT}/EFI")" ]; then
        echo "    OK: EFI directory found with content"
    else
        echo "    FAIL: EFI directory missing or empty"
        fail=1
    fi

    umount "$ESP_MOUNT"
    rmdir "$ESP_MOUNT" 2>/dev/null || true
    losetup -d "$loop"
done

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
