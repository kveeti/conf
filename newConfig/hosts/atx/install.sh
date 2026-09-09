#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <target-host> <ssh-host-key> <initrd-ssh-host-key>" >&2
  exit 2
fi

target_host=$1
ssh_host_key=$2
initrd_ssh_host_key=$3
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
flake_root=$(cd -- "$script_dir/../.." && pwd)
temporary_files=$(mktemp -d)

cleanup() {
  rm -rf "$temporary_files"
}
trap cleanup EXIT

for key in "$ssh_host_key" "$initrd_ssh_host_key"; do
  if [[ ! -r "$key" ]]; then
    echo "key is not readable: $key" >&2
    exit 1
  fi
  if ! ssh-keygen -y -f "$key" >/dev/null; then
    echo "invalid SSH private key: $key" >&2
    exit 1
  fi
done

install -d -m755 "$temporary_files/etc/ssh"
install -d -m755 "$temporary_files/etc/secrets/initrd"
install -m600 "$ssh_host_key" \
  "$temporary_files/etc/ssh/ssh_host_ed25519_key"
install -m600 "$initrd_ssh_host_key" \
  "$temporary_files/etc/secrets/initrd/ssh_host_ed25519_key"

nix run github:nix-community/nixos-anywhere -- \
  --extra-files "$temporary_files" \
  --flake "$flake_root#atx" \
  --build-on remote \
  --target-host "nixos@$target_host" \
  --ssh-port 22
