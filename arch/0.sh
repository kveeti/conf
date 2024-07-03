#!/bin/bash

set -euo pipefail

source ./config.conf
source "./utils.sh"

timedatectl set-timezone "${TIMEZONE}"
timedatectl set-ntp true

sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman -Sy --noconfirm archlinux-keyring

if [[ $DISK == /dev/nvme* ]]; then
    boot="${DISK}p1"
    rest="${DISK}p2"
else
    boot="${DISK}1"
    rest="${DISK}2"
fi

sfdisk "${DISK}" <<EOF
label: gpt
unit: sectors

${boot} : start=2048,  size=1G,  type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
${rest} : start=,      size=,    type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
EOF

config_set REST_PARTITION "${rest}"

modprobe dm-crypt

cryptsetup luksFormat "${rest}"
cryptsetup open --type luks "${rest}" cryptlvm

pvcreate /dev/mapper/cryptlvm
vgcreate vg /dev/mapper/cryptlvm

lvcreate -L 8G vg -n swap
lvcreate -l 100%FREE vg -n root

mkfs.ext4 /dev/vg/root
mount /dev/vg/root /mnt

mkswap /dev/vg/swap
swapon /dev/vg/swap

mkfs.fat -F 32 "${boot}"
mount --mkdir "${boot}" /mnt/boot

pacstrap -K /mnt base linux-lts linux-firmware linux-headers sudo vim git curl lvm2

genfstab -U /mnt >> /mnt/etc/fstab

cp -R . /mnt/root/scripts
