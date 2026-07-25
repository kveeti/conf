{
  description = "Dev VM home-manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/1267bb4920d0fc06ea916734c11b0bf004bbe17e";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim/b8f76bf5751835647538ef8784e4e6ee8deb8f95";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nixvim, ... }: {
    homeConfigurations.veeti = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ];
      };
      extraSpecialArgs = { inherit nixvim; };
      modules = [ ./atx/guests/dev/home.nix ];
    };
  };
}
