{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    secrets.url = "git+file:///Users/veeti/code/personal/secrets";
  };

  outputs = { self, nixpkgs, disko, agenix, secrets }: {
    nixosConfigurations.backup = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./config.nix
        ./disk.nix
        ./hardware-config.nix
        secrets.nixosModules.backup
      ];
      specialArgs = { keys = (import secrets).keys; };
    };
  };
}
