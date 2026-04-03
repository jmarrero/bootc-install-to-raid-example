ARG BASE_IMAGE=quay.io/centos-bootc/centos-bootc:stream10
FROM ${BASE_IMAGE}

COPY ./bootupd-0.2.32.44.g30f99d4-1.fc43.x86_64.rpm /bootupd-0.2.32.44.g30f99d4-1.fc43.x86_64.rpm

RUN <<EOF
        set -euxo pipefail

        cat >/etc/yum.repos.d/packit-bootc-pr.repo <<REPOEOF
[copr:copr.fedorainfracloud.org:packit:bootc-dev-bootc-1911]
name=Copr repo for bootc PR 1911
baseurl=https://download.copr.fedorainfracloud.org/results/packit/bootc-dev-bootc-1911/centos-stream-\$releasever-\$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/packit/bootc-dev-bootc-1911/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
REPOEOF
        dnf -y update bootc
        rm -f /etc/yum.repos.d/packit-bootc-pr.repo

#         cat >/etc/yum.repos.d/coreos-continuous.repo <<REPOEOF
# [copr:copr.fedorainfracloud.org:group_CoreOS:continuous]
# name=Copr repo for continuous owned by @CoreOS
# baseurl=https://download.copr.fedorainfracloud.org/results/@CoreOS/continuous/centos-stream-\$releasever-\$basearch/
# type=rpm-md
# skip_if_unavailable=True
# gpgcheck=1
# gpgkey=https://download.copr.fedorainfracloud.org/results/@CoreOS/continuous/pubkey.gpg
# repo_gpgcheck=0
# enabled=1
# enabled_metadata=1
# REPOEOF
#         dnf -y install bootupd-0.2.32.41.gb788553 mdadm
#         rm -f /etc/yum.repos.d/coreos-continuous.repo
#

        dnf -y remove bootupd
        rpm -i /bootupd-0.2.32.44.g30f99d4-1.fc43.x86_64.rpm

        # SOFTWARE RAID (mdraid) ONLY: Rebuild grubx64.efi with mdraid1x.
        #
        # The stock CentOS grubx64.efi does not include the mdraid1x
        # module, so GRUB cannot access filesystems on Linux software
        # RAID (mdraid) arrays. We rebuild the EFI binary with mdraid1x
        # (and its diskfilter dependency) added, then replace it in the
        # path bootupd reads from.
        #
        # This is NOT needed for hardware RAID or Intel VROC/RST, where
        # the UEFI firmware assembles the array and presents it to GRUB
        # as a single block device. However, other software-defined
        # storage stacks (e.g. Btrfs RAID, LVM on multiple disks) may
        # need a similar approach — embedding the appropriate GRUB
        # module(s) so GRUB can read from the storage layer at boot.
        #
        # NOTE: This produces an unsigned binary. Secure Boot must be
        # disabled, or you must sign it with a MOK-enrolled key.
        dnf install -y grub2-tools grub2-efi-x64-modules

        # Find the bootupd EFI source path for the grub2 component
        grub_efi_dir=$(dirname "$(find /usr/lib/efi/grub2 -name grubx64.efi -print -quit)")

        # Get the list of modules currently embedded in grubx64.efi by
        # extracting the module header names, then append mdraid1x.
        # Since we cannot introspect the existing binary easily, we use
        # the known default module set from the CentOS GRUB2 build plus
        # the RAID modules we need.
        grub2-mkimage \
            -O x86_64-efi \
            -o "${grub_efi_dir}/grubx64.efi" \
            -p /EFI/centos \
            -d /usr/lib/grub/x86_64-efi \
            all_video boot blscfg cat configfile cryptodisk echo ext2 \
            f2fs fat font gcry_rijndael gcry_rsa gcry_serpent \
            gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm \
            gzio halt http iso9660 jpeg loadenv loopback linux lvm \
            luks luks2 memdisk minicmd net normal part_gpt part_msdos \
            password_pbkdf2 pgp png reboot regexp search \
            search_fs_file search_fs_uuid search_label serial sleep \
            syslinuxcfg test tftp video xfs \
            mdraid1x diskfilter

        dnf clean all

        # SOFTWARE RAID (mdraid) ONLY: Regenerate initramfs with mdraid.
        #
        # The pre-built initramfs does not include the mdraid dracut
        # module, so the kernel cannot assemble the md array and the
        # root filesystem is never found during boot.
        #
        # This is NOT needed for hardware RAID controllers (which
        # expose a single block device to the OS) or Intel VROC/RST
        # on UEFI (where the firmware handles array assembly during
        # pre-boot). For VROC, the kernel does need mdadm with IMSM
        # metadata support in the initramfs to re-assemble the array
        # after handoff from firmware — if the default initramfs does
        # not include that, a similar dracut customization would be
        # needed (e.g. dracut --add "mdraid dm").
        kernel_ver=$(ls /usr/lib/modules/)
        dracut --force --add mdraid \
            /usr/lib/modules/"${kernel_ver}"/initramfs.img \
            "${kernel_ver}"

EOF
