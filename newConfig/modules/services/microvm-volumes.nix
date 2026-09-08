{ config, lib, ... }:

let
  cfg = config.homelab.volumes;

  childType = lib.types.submodule {
    options = {
      owner = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      group = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      mode = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    };
  };

  valueOr = value: fallback: if value == null then fallback else value;

  volumeDirectories = lib.concatLists (lib.mapAttrsToList (_: volume:
    [ "d /var/lib/state/${volume.source} ${volume.mode} ${volume.owner} ${volume.group} -" ]
    ++ lib.mapAttrsToList (path: child:
      "d ${volume.path}/${path} ${valueOr child.mode volume.mode} ${valueOr child.owner volume.owner} ${valueOr child.group volume.group} -"
    ) volume.dirs
  ) cfg);
in {
  options.homelab = {
    stateRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/microvms/${config.homelab.hostKey}";
      description = "Host directory containing this VM's state image.";
    };

    volumeSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "State image size in MiB.";
    };

    volumes = lib.mkOption {
      default = {};
      description = "Persistent service directories stored in the VM state image.";
      type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/${name}";
          };
          source = lib.mkOption {
            type = lib.types.str;
            default = name;
          };
          owner = lib.mkOption {
            type = lib.types.str;
            default = name;
          };
          group = lib.mkOption {
            type = lib.types.str;
            default = config.owner;
          };
          mode = lib.mkOption {
            type = lib.types.str;
            default = "0750";
          };
          dirs = lib.mkOption {
            type = lib.types.attrsOf childType;
            default = {};
          };
        };
      }));
    };
  };

  config = lib.mkIf (cfg != {}) {
    microvm.volumes = [{
      image = "${config.homelab.stateRoot}/state.img";
      mountPoint = "/var/lib/state";
      size = config.homelab.volumeSize;
    }];

    systemd.tmpfiles.rules = volumeDirectories;

    fileSystems = lib.mapAttrs' (_: volume:
      lib.nameValuePair volume.path {
        device = "/var/lib/state/${volume.source}";
        fsType = "none";
        options = [ "bind" ];
        depends = [ "/var/lib/state" ];
      }
    ) cfg;
  };
}
