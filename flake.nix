{
  description = "Veeti's NixOS and nix-darwin configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/1267bb4920d0fc06ea916734c11b0bf004bbe17e";
    nixpkgs-router.url = "github:NixOS/nixpkgs/ac62194c3917d5f474c1a844b6fd6da2db95077d";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/9ae611a455b90cf061d8f332b977e387bda8e1ca";

    disko.url = "github:nix-community/disko/a4cb7bf73f264d40560ba527f9280469f1f081c6";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    lanzaboote.url = "github:nix-community/lanzaboote/v1.1.0";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs";

    disko-router.url = "github:nix-community/disko/00395d188e3594a1507f214a2f15d4ce5c07cb28";
    disko-router.inputs.nixpkgs.follows = "nixpkgs-router";

    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";

    nixvim.url = "github:nix-community/nixvim/nixos-25.11";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";

    secrets-router.url = "git+file:///Users/veeti/code/personal/secrets?rev=a2758487512d8456546da3c3fe7a7cbe675c56a3";
    secrets-atx.url = "git+file:///Users/veeti/code/personal/secrets?rev=a87d655a036669822fc23eee2736f1ab35c00563";
    secrets-backup.url = "git+file:///Users/veeti/code/personal/secrets?rev=e4b32ebb26e9ea5ac19173c7e5ae6a6b70bf2aec";
    secrets-pc.url = "git+file:///Users/veeti/code/personal/secrets?rev=990f67cf535399bc448aa028d3f2d7e410bf5b30";

    weather.url = "github:kveeti/weather/6af9846820941a85aba04ea9a040308a2c23b358";
    rss.url = "github:kveeti/rss/375850566401198f7736ef0a4a75998c731cd784";
    food.url = "github:kveeti/food/cc61e77586c3f016ea61515ce6133f4d17f99b92";

    mac.url = "path:./mac";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-router,
      nixpkgs-unstable,
      disko,
      disko-router,
      secrets-router,
      secrets-atx,
      secrets-backup,
      secrets-pc,
      weather,
      rss,
      food,
      mac,
      microvm,
      nixvim,
      home-manager,
      lanzaboote,
    }:
    let
      linuxSystem = "x86_64-linux";
      inventory = import ./router/inventory.nix;

      mkDnsRecords = hostConfig:
        let
          targetHost = hostConfig.config.homelab.dns.defaultTargetHost;
          targetAddress = inventory.hosts.${targetHost}.ipv4;
        in
          map (name: {
            inherit name;
            address = targetAddress;
          }) hostConfig.config.homelab.dns.records;

      atx = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        modules = [
          disko.nixosModules.disko
          ./atx/configuration.nix
          ./atx/disk.nix
          ./atx/hardware-config.nix
          secrets-atx.nixosModules.atx
        ];
        specialArgs = {
          inherit microvm rss food weather mac nixvim;
          keys = (import secrets-atx).keys;
          pkgs-unstable = import nixpkgs-unstable { system = linuxSystem; };
          mediaUser = import ./atx/media-ids.nix;
        };
      };

      serviceDnsRecords = mkDnsRecords atx;
    in {
      nixosConfigurations = rec {
        router = nixpkgs-router.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            disko-router.nixosModules.disko
            ./modules/nixos/dns-records.nix
            ./router/config.nix
            ./router/disk.nix
            ./router/hardware-config.nix
            secrets-router.nixosModules.router
          ];
          specialArgs = {
            secrets = import secrets-router;
            inherit serviceDnsRecords;
          };
        };

        inherit atx;

        backup = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            disko.nixosModules.disko
            ./backup/config.nix
            ./backup/disk.nix
            ./backup/hardware-config.nix
            secrets-backup.nixosModules.backup
          ];
          specialArgs = {
            keys = (import secrets-backup).keys;
          };
        };

        pc = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            ./pc/configuration.nix
            ./pc/disk.nix
            ./pc/hardware-config.nix
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.users.veeti = import ./pc/home.nix;
            }
            secrets-pc.nixosModules.pc
          ];
          specialArgs = {
            inputs = { inherit lanzaboote; };
            keys = (import secrets-pc).keys;
          };
        };
      };

      darwinConfigurations = {
        inherit (mac.darwinConfigurations) e;
      };
    };
}
