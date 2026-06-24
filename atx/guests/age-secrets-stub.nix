{ lib, ... }:

{
  options.age.secrets = lib.mkOption {
    default = {};
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        file  = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; };
        path  = lib.mkOption { type = lib.types.str; default = "/run/secrets/${name}"; };
        mode  = lib.mkOption { type = lib.types.str; default = "0400"; };
        owner = lib.mkOption { type = lib.types.str; default = "0"; };
        group = lib.mkOption { type = lib.types.str; default = "0"; };
      };
    }));
  };
}
