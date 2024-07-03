#!/bin/bash

set -euo pipefail

source "./utils.sh"

config_set DISK "/dev/nvme1n1"
config_set USERNAME "veeti"
config_set TIMEZONE "Europe/Helsinki"
config_set NET_INTERFACE "eno1"
config_set NET_GATEWAY "192.168.0.2"
config_set NET_DNS "192.168.0.3"
config_set HOSTNAME "pc"

bash "./0.sh"
arch-chroot /mnt "/root/scripts/1.sh"
arch-chroot /mnt /usr/bin/runuser -u "${USERNAME}" -- "/home/${USERNAME}/scripts/2.sh"
bash "./3.sh"
