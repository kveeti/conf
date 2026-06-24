#!/usr/bin/env bash

# First-install bootstrap for the backup host. Mirrors atx/init.sh: stage the
# ephemeral host + initrd-unlock SSH keys, then nixos-anywhere. The keys are
# generated right before this runs and deleted right after (never persisted).

TARGET_HOST=${1:-}
if [[ -z "$TARGET_HOST" ]]; then
	echo "usage: $0 <target_host>"
	exit 1
fi

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
	--generate-hardware-config nixos-generate-config ./hardware-config.nix \
	--flake .#backup \
	--build-on remote \
	--target-host veeti@$TARGET_HOST --ssh-port 22
