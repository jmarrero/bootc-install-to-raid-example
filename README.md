# RAID 1 Multi-ESP Boot Test

Scripts for testing bootc installation onto a RAID 1 array with multiple ESP
(EFI System Partition) partitions -- one per disk -- so that any disk can boot
independently if another fails.

## Prerequisites

- podman
- qemu-system-x86_64, edk2-ovmf
- mdadm, dosfstools, e2fsprogs, util-linux

All scripts must be run as **root**.

## Usage

### 1. Install bootc onto a RAID 1 array

```sh
sudo ./test-raid1-multi-esp.sh
```

This builds a test container image (CentOS Stream 10 based by default), creates
3 loop-backed disk images in `/var/tmp/`, assembles a RAID 1 array, runs
`bootc install to-existing-root`, and verifies that every ESP received
bootloader files.

To use a different base image:

```sh
sudo ./test-raid1-multi-esp.sh quay.io/centos-bootc/centos-bootc:stream10
```

### 2. Boot the installed system in a VM

```sh
sudo ./boot-vm.sh
```

This launches a QEMU VM with all 3 disks attached. Log in and verify the system
works. Press **Ctrl-A X** to exit the VM.

### 3. Test degraded boot (single disk)

```sh
sudo ./boot-vm.sh --disk 1
```

This boots the VM from only disk 1, simulating a disk failure. You can
substitute any disk number from 1 to 3.

### 4. Clean up

```sh
sudo ./cleanup.sh
```

Tears down loop devices, stops the RAID array, and removes the disk images.
