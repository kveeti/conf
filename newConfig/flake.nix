{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko = {
      url = "github:nix-community/disko/a4cb7bf73f264d40560ba527f9280469f1f081c6";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    secrets-backup.url = "git+file:///Users/veeti/code/personal/secrets";
  };

  outputs = { self, nixpkgs, disko, secrets-backup }:
    let
      inventory = import ./inventory.nix;

      mkHost = {
        hostName,
        modules,
        specialArgs ? {},
      }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inventory; } // specialArgs;
          modules = [ { networking.hostName = hostName; } ] ++ modules;
        };
    in {
      lib = {
        inherit inventory mkHost;
      };

      nixosModules = {
        base = ./modules/profiles/base.nix;
        server = ./modules/profiles/server.nix;
      };

      nixosConfigurations.backup = mkHost {
        hostName = "backup";
        specialArgs.adminKeys = (import secrets-backup).keys.admins;
        modules = [
          disko.nixosModules.disko
          secrets-backup.nixosModules.backup
          ./hosts/backup
        ];
      };
    };
}
