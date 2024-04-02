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

> /boot/loader/loader.conf
cat << EOF > /boot/loader/loader.conf
default arch
timeout 4
console-mode max
editor no
EOF

# create menu entry
> /boot/loader/entries/arch.conf
cat << EOF > /boot/loader/entries/arch.conf
title arch
linux /vmlinuz-linux-lts
initrd /initramfs-linux-lts.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "$root_partition") rw
EOF

# hostname
echo "pc" > /etc/hostname

# enable network manager
systemctl enable NetworkManager

# multilib
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

# packages
pacman -Syu \
  amd-ucode \
  vulkan-radeon \
  xf86-video-amdgpu \
  lib32-vulkan-radeon \
  mesa \
  mesa-utils \
  lib32-mesa \
  wayland \
  xorg-xwayland \
  sway \
  swayidle \
  swaylock \
  bluez \
  bluez-utils \
  pavucontrol \
  wireplumber \
  pipewire \
  pipewire-audio \
  pipewire-alsa \
  pipewire-jack \
  pipewire-pulse \
  pipewire-session-manager \
  ttf-jetbrains-mono-nerd \
  archlinux-keyring \
  base-devel \
  unzip \
  zip \
  htop \
  neofetch \
  wl-clipboard \
  ripgrep \
  go \
  docker \
  docker-compose \
  grim \
  slurp \
  gnome-keyring \
  polkit \
  wezterm \
  neovim \
  firefox \
  keepassxc \
  discord \
  steam

# services
systemctl enable bluetooth docker
systemctl start bluetooth docker

# user
useradd -m -G wheel,docker -s /bin/bash "$username"

# passwords
passwd
passwd "$username"

# run 2.sh as created user
script_location="$(dirname "$0")"
su -m "$username" -s /bin/bash -c "$script_location/2.sh"
