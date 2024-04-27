#!/bin/bash

set -euxo pipefail

if [ "$EUID" -e 0 ]; then
    echo "this script is not meant to be run as root" 
    exit 1
fi

# install aur helper
cd ~
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd ~
rm -rf ./yay

# aur packages
yay -S \
  tofi \
  minecraft-launcher \
  downgrade \
  asdf-vm
