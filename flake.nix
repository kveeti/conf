{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    secrets-pc.follows = "secrets";
    mac.url = "path:./mac";

    secrets.url = "git+file:///home/veeti/code/secrets";
    secrets-worker.follows = "secrets";
    secrets-atx.follows = "secrets";
    secrets-o11y.follows = "secrets";
    secrets-router.follows = "secrets";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixvim, disko, lanzaboote, money, food, rss, weather, microvm, home-manager, secrets, secrets-atx, secrets-worker, secrets-o11y, secrets-router, secrets-pc, mac }:
    let
      inventory = import ./inventory.nix;
      routerInventory = import ./hosts/router/inventory.nix { inherit inventory; lib = nixpkgs.lib; };
      atxInventory = import ./hosts/atx/inventory.nix { inherit inventory; lib = nixpkgs.lib; };

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
            inventory = routerInventory;
            vlan111OutboundAllowedIP = (import secrets-router).vlan111OutboundAllowedIP;
            pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; };
          };
          modules = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            microvm.nixosModules.host
            secrets-router.nixosModules.router
            {
              microvm.vms.homeassistant.config = {
                disabledModules = [
                  "services/home-automation/home-assistant.nix"
                ];
                imports = [
                  "${nixpkgs-unstable}/nixos/modules/services/home-automation/home-assistant.nix"
                ];
              };
            }
            ./hosts/router
          ];
        };

        router-recovery = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            adminKeys = (import secrets-router).keys.admins;
            inventory = routerInventory;
            routerSystem = router.config.system.build.toplevel;
            diskoPackage = disko.packages.x86_64-linux.disko;
          };
          modules = [ ./hosts/router/recovery.nix ];
        };

        atx = mkHost {
          hostName = "atx";
          specialArgs = {
            adminKeys = (import secrets-atx).keys.admins;
            inventory = atxInventory;
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

        worker = mkHost {
          hostName = "worker";
          specialArgs = {
            adminKeys = (import secrets-worker).keys.admins;
            inherit rss weather;
          };
          modules = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            secrets-worker.nixosModules.worker
            ./hosts/worker
          ];
        };

        pc = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            microvm.nixosModules.host
            home-manager.nixosModules.home-manager
            ./hosts/pc/configuration.nix
            ./hosts/pc/disk.nix
            ./hosts/pc/hardware-config.nix
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.extraSpecialArgs = {
                inherit nixpkgs;
                pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; };
              };
              home-manager.sharedModules = [ nixvim.homeModules.nixvim ];
              home-manager.users.veeti = import ./hosts/pc/home.nix;
            }
            secrets-pc.nixosModules.pc
          ];
          specialArgs = {
            inherit inventory;
            inputs = { inherit lanzaboote; };
            keys = (import secrets-pc).keys;
          };
        };

        o11y = mkHost {
          hostName = "o11y";
          specialArgs = {
            adminKeys = (import secrets-o11y).keys.admins;
          };
          modules = [
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            secrets-o11y.nixosModules.o11y
            ./hosts/o11y
          ];
        };
      };

      homeConfigurations."veeti@pc" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
            "discord"
            "steam"
            "steam-unwrapped"
            "steam-run"
          ];
        };
        extraSpecialArgs = {
          inherit nixpkgs;
          pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; };
        };
        modules = [ nixvim.homeModules.nixvim ./hosts/pc/home.nix ];
      };

      darwinConfigurations = {
        inherit (mac.darwinConfigurations) e;
      };
    };
}
