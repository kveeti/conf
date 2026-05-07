{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    secrets.url = "git+file:///Users/veeti/code/personal/secrets";

    weather.url = "github:kveeti/weather";
    rss.url = "github:kveeti/rss";
    food.url = "github:kveeti/food";
  };

  outputs = { self, nixpkgs, disko, secrets, weather, rss, food }: {
    nixosConfigurations.nix-services-internal = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./config.nix
        ./disk.nix
        ./hardware-config.nix
        secrets.nixosModules.nix-services-internal
        weather.nixosModules.default
        rss.nixosModules.default
        food.nixosModules.default
      ];
      specialArgs = { keys = (import secrets).keys; };
    };
  };
}
