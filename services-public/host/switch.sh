#!/usr/bin/env bash

TARGET_HOST=${1:-}
if [[ -z "$TARGET_HOST" ]]; then
	echo "usage: $0 <target_host>"
	exit 1
fi

nix-shell -p \
	nixos-rebuild \
	--run "nixos-rebuild switch --fast --flake .#services-public --build-host veeti@${TARGET_HOST} --target-host veeti@${TARGET_HOST} --use-remote-sudo"
