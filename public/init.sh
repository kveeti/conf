#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST=${1:-}
if [[ -z "$TARGET_HOST" ]]; then
  echo "usage: $0 <target_host>" >&2
  exit 1
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
temp=$(mktemp -d)

cleanup() {
  rm -rf "$temp"
}
trap cleanup EXIT

install -d -m755 "$temp/etc/ssh" "$temp/etc/secrets/initrd"
install -m600 "$script_dir/keys/ssh_host_ed25519_key" "$temp/etc/ssh/ssh_host_ed25519_key"
install -m600 "$script_dir/keys/unlocking_ssh_host_ed25519_key" "$temp/etc/secrets/initrd/ssh_host_ed25519_key"

nix --extra-experimental-features "nix-command flakes" run \
  github:nix-community/nixos-anywhere -- \
  --extra-files "$temp" \
  --generate-hardware-config nixos-generate-config "$script_dir/hardware-config.nix" \
  --flake "$repo_root#public" \
  --build-on remote \
  --target-host "nixos@$TARGET_HOST" --ssh-port 22
