{
  description = "Veeti's NixOS and nix-darwin configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/1267bb4920d0fc06ea916734c11b0bf004bbe17e";
    nixpkgs-router.url = "github:NixOS/nixpkgs/ac62194c3917d5f474c1a844b6fd6da2db95077d";
    nixpkgs-public.url = "github:NixOS/nixpkgs/078d69f03934859a181e81ba987c2bb033eebfc5";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/4bd9165a9165d7b5e33ae57f3eecbcb28fb231c9";

    disko.url = "github:nix-community/disko/a4cb7bf73f264d40560ba527f9280469f1f081c6";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    disko-router.url = "github:nix-community/disko/00395d188e3594a1507f214a2f15d4ce5c07cb28";
    disko-router.inputs.nixpkgs.follows = "nixpkgs-router";

    disko-public.url = "github:nix-community/disko/00395d188e3594a1507f214a2f15d4ce5c07cb28";
    disko-public.inputs.nixpkgs.follows = "nixpkgs-public";

    secrets-dev.url = "git+file:///Users/veeti/code/personal/secrets?rev=303ab7d805e319be03514f13f86b69b7b79760cc";
    secrets-internal.url = "git+file:///Users/veeti/code/personal/secrets?rev=ac39e17787303b12a1534f26bf6b0e119ef3eeb8";
    secrets-router.url = "git+file:///Users/veeti/code/personal/secrets?rev=b2b9ede3334e28902923a133a99c83b6bfa90129";
    secrets-public.url = "git+file:///Users/veeti/code/personal/secrets?rev=d1d9444b803995601b8bec39e10288bc4c8fdc69";

    weather.url = "github:kveeti/weather/6af9846820941a85aba04ea9a040308a2c23b358";
    rss.url = "github:kveeti/rss/375850566401198f7736ef0a4a75998c731cd784";
    food.url = "github:kveeti/food/cc61e77586c3f016ea61515ce6133f4d17f99b92";

    nixvim.url = "github:nix-community/nixvim/b8f76bf5751835647538ef8784e4e6ee8deb8f95";

    mac.url = "path:./mac";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-router,
      nixpkgs-public,
      nixpkgs-unstable,
      disko,
      disko-router,
      disko-public,
      secrets-dev,
      secrets-internal,
      secrets-router,
      secrets-public,
      weather,
      rss,
      food,
      nixvim,
      mac,
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

      internal = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        modules = [
          disko.nixosModules.disko
          ./modules/nixos/dns-records.nix
          ./nix-services-internal/host/config.nix
          ./nix-services-internal/host/disk.nix
          ./nix-services-internal/host/hardware-config.nix
          secrets-internal.nixosModules.nix-services-internal
          weather.nixosModules.default
          rss.nixosModules.default
          food.nixosModules.default
        ];
        specialArgs = { keys = (import secrets-internal).keys; };
      };

      serviceDnsRecords = mkDnsRecords internal;
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

        nix-services-internal = internal;

        services-public = nixpkgs-public.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            disko-public.nixosModules.disko
            ./modules/nixos/dns-records.nix
            ./services-public/host/config.nix
            ./services-public/host/disk.nix
            ./services-public/host/hardware-config.nix
            secrets-public.nixosModules.services-public
          ];
          specialArgs = { keys = (import secrets-public).keys; };
        };

        dev = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            disko.nixosModules.disko
            ./modules/nixos/dns-records.nix
            ./dev/host/config.nix
            ./dev/host/disk.nix
            ./dev/host/hardware-config.nix
            secrets-dev.nixosModules.dev
            nixvim.nixosModules.nixvim
          ];
          specialArgs = {
            keys = (import secrets-dev).keys;
            pkgs-unstable = import nixpkgs-unstable {
              system = linuxSystem;
            };
          };
        };
      };

      darwinConfigurations = {
        inherit (mac.darwinConfigurations) e;
      };
    };
}
