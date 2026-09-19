{ lib, ... }:

{
  options.age.secrets = lib.mkOption {
    default = {};
    description = "Secrets shared read-only from the MicroVM host.";
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        path = lib.mkOption {
          type = lib.types.str;
          default = "/run/secrets/${name}";
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0400";
        };
        owner = lib.mkOption {
          type = lib.types.str;
          default = "0";
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = "0";
        };
      };
    }));
  };
}
