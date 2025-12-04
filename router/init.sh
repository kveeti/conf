#!/usr/bin/env bash

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

cat ./secrets/ssh_host_ed25519_key > "$temp/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$temp/etc/ssh/ssh_host_ed25519_key"

nix --extra-experimental-features "nix-command flakes" run \
	github:nix-community/nixos-anywhere -- \
	--extra-files "$temp" \
	--generate-hardware-config nixos-generate-config ./hardware-config.nix \
	--flake .#router \
	--build-on remote \
	--target-host nixos@$TARGET_HOST
