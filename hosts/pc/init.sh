#!/usr/bin/env bash

# First-install bootstrap for pc. Mirrors atx/backup: stage the ephemeral host +
# initrd-unlock SSH keys, then nixos-anywhere. Generate ./keys/ right before
# running this and delete them after (never persisted):
#   ssh-keygen -t ed25519 -N "" -f ./keys/ssh_host_ed25519_key
#   ssh-keygen -t ed25519 -N "" -f ./keys/unlocking_ssh_host_ed25519_key

TARGET_HOST=${1:-}
if [[ -z "$TARGET_HOST" ]]; then
	echo "usage: $0 <target_host>"
	exit 1
fi

flake_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

temp=$(mktemp -d)

cleanup() {
  rm -rf "$temp"
}
trap cleanup EXIT

install -d -m755 "$temp/etc/ssh"
install -d -m755 "$temp/etc/secrets/initrd"

cat ./keys/ssh_host_ed25519_key > "$temp/etc/ssh/ssh_host_ed25519_key"
cat ./keys/unlocking_ssh_host_ed25519_key > "$temp/etc/secrets/initrd/ssh_host_ed25519_key"

chmod 600 "$temp/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$temp/etc/secrets/initrd/ssh_host_ed25519_key"

nix --extra-experimental-features "nix-command flakes" run \
	github:nix-community/nixos-anywhere -- \
	--extra-files "$temp" \
	--generate-hardware-config nixos-generate-config "$flake_root/hosts/pc/hardware-config.nix" \
	--flake "path:$flake_root#pc" \
	--build-on remote \
	--target-host nixos@$TARGET_HOST --ssh-port 22
