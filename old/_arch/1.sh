#!/bin/bash

set -euxo pipefail

# pacstrap packages:
# base linux-lts linux-firmware linux-headers networkmanager sudo vim git curl

# root partition must be given as the first argument
# e.g. /dev/sda1
root_partition=$1
if [ -z "$root_partition" ]; then
  echo "root partition not given"
  exit 1
fi

username=veeti

# timezone
ln -sf /usr/share/zoneinfo/Europe/Helsinki /etc/localtime

# time
hwclock --systohc

# locale
sed -i '/en_US.UTF-8/s/^#//' /etc/locale.gen
locale-gen

# language
> /etc/locale.conf
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# keymap
> /etc/vconsole.conf
echo "KEYMAP=fi" > /etc/vconsole.conf

# systemd-boot
bootctl --path=/boot install

# systemd-boot - loader.conf
> /boot/loader/loader.conf
cat << EOF > /boot/loader/loader.conf
default arch
timeout 4
console-mode max
editor no
EOF

# systemd-boot - create menu entry
> /boot/loader/entries/arch.conf
cat << EOF > /boot/loader/entries/arch.conf
title arch
linux /vmlinuz-linux-lts
initrd /initramfs-linux-lts.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "$root_partition") rw
EOF

# hostname
echo "pc" > /etc/hostname

systemctl enable NetworkManager

echo "root password"
passwd

echo "exit chroot, reboot into arch and run 2.sh as root"

echo "exit"
echo "umount -R /mnt"
echo "reboot"
