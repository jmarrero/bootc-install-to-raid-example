# bootc + bootupd RAID 1 Multi-ESP: Implementation Guide

## Summary

This guide documents how to boot bootc/ostree from a software RAID 1
array where /boot is a directory on the RAID root filesystem (no
separate /boot partition).

## Partition Layout

```
vda: ESP (vda1) + RAID member (vda2) ─┐
vdb: ESP (vdb1) + RAID member (vdb2) ─┼─ md0 (/ with /boot inside)
vdc: ESP (vdc1) + RAID member (vdc2) ─┘
```

## Required Fixes

### 1. Custom GRUB with mdraid1x

Stock CentOS grubx64.efi lacks the mdraid1x module. Rebuild with:
```bash
grub2-mkimage -O x86_64-efi -o grubx64.efi ... mdraid1x diskfilter
```

### 2. BLS Entry Path Fix

bootc generates paths like `/ostree/...` but must be `/boot/ostree/...`:
```bash
sed -i 's|^linux /ostree/|linux /boot/ostree/|' "$entry"
```

### 3. fstab Device Path Fix

Each ESP has different UUID. Use device paths:
```
/dev/vda1  /boot/efi   vfat  defaults  0 2
/dev/vdb1  /boot/efi2  vfat  noauto    0 2
/dev/vdc1  /boot/efi3  vfat  noauto    0 2
```

### 4. Initramfs with mdraid

```bash
dracut --force --add mdraid /usr/lib/modules/VERSION/initramfs.img VERSION
```

## Test Results

All degraded boot tests PASSED - any single disk can boot independently.
