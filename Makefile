home:
	home-manager switch --flake .#veeti@pc

nixos:
	sudo nixos-rebuild switch --flake .#pc