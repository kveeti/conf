#!/bin/bash

set -euxo pipefail

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
  bluez \
  bluez-utils \
  ttf-jetbrains-mono-nerd \
  archlinux-keyring \
  base-devel \
  unzip \
  zip \
  htop \
  openssh \
  neofetch \
  wl-clipboard \
  ripgrep \
  go \
  docker \
  docker-compose \
  neovim \
  tmux \
  firefox \
  keepassxc \
  discord \
  steam \
  wayland \
  xorg-xwayland \
  sway \
  swayidle \
  swaylock \
  pavucontrol \
  wireplumber \
  pipewire \
  pipewire-audio \
  pipewire-alsa \
  pipewire-jack \
  pipewire-pulse \
  pipewire-session-manager \
  gnome-keyring \
  polkit \
  grim \
  slurp \
  openresolv \
  wireguard-tools \
  alacritty

# plasma:
#  plasma \
#  sddm \
#  dolphin \
#  flameshot
#
# enable sddm service

# sway packages:
#  wayland \
#  xorg-xwayland \
#  sway \
#  swayidle \
#  swaylock \
#  pavucontrol \
#  wireplumber \
#  pipewire \
#  pipewire-audio \
#  pipewire-alsa \
#  pipewire-jack \
#  pipewire-pulse \
#  pipewire-session-manager \
#  gnome-keyring \
#  polkit \
#  grim \
#  slurp

# printing:
#  cups \
#  nss-mdns \
#  hplip \ # maybe not needed
#  hplip-plugin # maybe not needed
#
# enable cups and avahi-daemon (https://wiki.archlinux.org/title/avahi#Hostname_resolution) services

# services
systemctl enable bluetooth docker
systemctl start bluetooth docker

# user
useradd -m -G wheel,docker -s /bin/bash "$username"
echo "$username ALL=(ALL) ALL" > /etc/sudoers.d/10-"$username"
echo "$username password"
passwd "$username"

# run 3.sh as created user
script_location="$(dirname "$0")"
su -m "$username" -s /bin/bash -c "$script_location/3.sh"
