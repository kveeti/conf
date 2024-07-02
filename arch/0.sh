#!/bin/bash

set -euxo pipefail

source "./utils.sh"

config_set DISK /dev/nvme1n1
config_set USERNAME veeti

boot="${DISK}p1"
swap="${DISK}p2"
root="${DISK}p3"

config_set ROOT_PARTITION "${root}"

timedatectl set-timezone Europe/Helsinki
timedatectl set-ntp true

sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

pacman -Sy --noconfirm archlinux-keyring

# partitions
sfdisk "${DISK}" <<EOF
label: gpt
unit: sectors

${boot} : start=2048,  size=1G,  type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
${swap} : start=,      size=8G,  type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F
${root} : start=,      size=,    type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
EOF

mkfs.fat -F 32 "${boot}"
mkswap "${swap}"
mkfs.ext4 "${root}"

mount "${root}" /mnt
mount --mkdir "${boot}" /mnt/boot
swapon "${swap}"

pacstrap -K /mnt base linux-lts linux-firmware linux-headers sudo vim git curl

cp -R . /mnt/root/scripts
