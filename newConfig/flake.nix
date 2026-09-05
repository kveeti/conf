{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
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
    };
}
