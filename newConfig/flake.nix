{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/9ae611a455b90cf061d8f332b977e387bda8e1ca";

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

    food.url = "github:kveeti/food/cc61e77586c3f016ea61515ce6133f4d17f99b92";
    rss.url = "github:kveeti/rss/375850566401198f7736ef0a4a75998c731cd784";
    weather.url = "github:kveeti/weather/6af9846820941a85aba04ea9a040308a2c23b358";

    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    secrets-backup.url = "git+file:///Users/veeti/code/personal/secrets";
    secrets-atx.follows = "secrets-backup";
    secrets-public.follows = "secrets-backup";
    secrets-router.follows = "secrets-backup";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, lanzaboote, money, food, rss, weather, microvm, secrets-atx, secrets-backup, secrets-public, secrets-router }:
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

      nixosConfigurations = rec {
        router = mkHost {
          hostName = "router";
          specialArgs = {
            adminKeys = (import secrets-router).keys.admins;
            vlan111OutboundAllowedIP = (import secrets-router).vlan111OutboundAllowedIP;
          };
          modules = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            microvm.nixosModules.host
            secrets-router.nixosModules.router
            ./hosts/router
          ];
        };

        router-recovery = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            adminKeys = (import secrets-router).keys.admins;
            inherit inventory;
            routerSystem = router.config.system.build.toplevel;
            diskoPackage = disko.packages.x86_64-linux.disko;
          };
          modules = [ ./hosts/router/recovery.nix ];
        };

        atx = mkHost {
          hostName = "atx";
          specialArgs = {
            adminKeys = (import secrets-atx).keys.admins;
            inherit food rss weather;
            pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; };
          };
          modules = [
            disko.nixosModules.disko
            microvm.nixosModules.host
            secrets-atx.nixosModules.atx
            ./hosts/atx
          ];
        };

        backup = mkHost {
          hostName = "backup";
          specialArgs.adminKeys = (import secrets-backup).keys.admins;
          modules = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
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
