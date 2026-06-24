lib:

{ vmName, stateRoot, secrets }:
let
  stateDir = "${stateRoot}/secrets";
  materialize = name: s:
    if s.derive != null then ''
      ( umask 077; ${s.derive} ) > ${stateDir}/${name}
      chmod ${s.mode} ${stateDir}/${name}
    '' else "install -m ${s.mode} ${s.source} ${stateDir}/${name}";
in {
  host.system.activationScripts."${vmName}-secrets" = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0711 ${stateDir}
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList materialize secrets)}
    '';
  };

  guest = { lib, ... }: {
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

    config.microvm.shares = [{
      source = stateDir;
      mountPoint = "/run/secrets";
      tag = "secrets";
      proto = "virtiofs";
    }];
  };
}
