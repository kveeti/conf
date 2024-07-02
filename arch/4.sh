#!/bin/bash

set -euo pipefail

source ./config.conf
source "./utils.sh"

rm -rf "/mnt/root/scripts"
rm -rf "/mnt/home/${USERNAME}/scripts"
