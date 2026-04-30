{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    secrets.url = "git+file:///Users/veeti/code/personal/secrets";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, secrets, home-manager, nixvim }: {
    nixosConfigurations.dev = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./config.nix
        ./disk.nix
        ./hardware-config.nix
        secrets.nixosModules.dev
        nixvim.nixosModules.nixvim
      ];
      specialArgs = {
        keys = (import secrets).keys;
        pkgs-unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
        };
      };
    };
  };
}
