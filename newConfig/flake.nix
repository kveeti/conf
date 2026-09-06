{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko = {
      url = "github:nix-community/disko/a4cb7bf73f264d40560ba527f9280469f1f081c6";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    money = {
      url = "github:kveeti/money/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    secrets-backup.url = "git+file:///Users/veeti/code/personal/secrets";
    secrets-public.follows = "secrets-backup";
    secrets-router.follows = "secrets-backup";
  };

  outputs = { self, nixpkgs, disko, lanzaboote, money, secrets-backup, secrets-public, secrets-router }:
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

      nixosConfigurations = {
        router = mkHost {
          hostName = "router";
          specialArgs.adminKeys = (import secrets-router).keys.admins;
          modules = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            secrets-router.nixosModules.router
            ./hosts/router
          ];
        };

        backup = mkHost {
          hostName = "backup";
          specialArgs.adminKeys = (import secrets-backup).keys.admins;
          modules = [
            disko.nixosModules.disko
            secrets-backup.nixosModules.backup
            ./hosts/backup
          ];
        };

        public = mkHost {
          hostName = "public";
          specialArgs = {
            adminKeys = (import secrets-public).keys.admins;
            inherit money;
          };
          modules = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            secrets-public.nixosModules.public
            ./hosts/public
          ];
        };
      };
    };
}
