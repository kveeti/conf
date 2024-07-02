#!/bin/bash

set -euxo pipefail

source "./utils.sh"

config_set DISK "/dev/nvme1n1"
config_set USERNAME "veeti"

bash ./0.sh
arch-chroot /mnt "/root/scripts/1.sh"
arch-chroot /mnt /usr/bin/runuser -u $USERNAME -- "/home/${USERNAME}/scripts/2.sh"

rm -rf /mnt/root/scripts
rm -rf "/mnt/home/${USERNAME}/scripts"

