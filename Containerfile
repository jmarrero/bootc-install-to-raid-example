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

        # Regenerate the initramfs so dracut includes the mdraid module.
        # Without this, the pre-built initramfs has no RAID support and
        # the root filesystem (on md) is never found during boot.
        kernel_ver=$(ls /usr/lib/modules/)
        dracut --force --add mdraid \
            /usr/lib/modules/"${kernel_ver}"/initramfs.img \
            "${kernel_ver}"

EOF
