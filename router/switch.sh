#!/usr/bin/env bash

nix-shell -p \
	nixos-rebuild \
	--run "nixos-rebuild switch --fast --flake .#router --build-host veeti@192.168.5.1 --target-host veeti@192.168.5.1 --use-remote-sudo"
