{ config, lib, ... }:

let
  cfg = config.homelab.volumes;

  dirMod = lib.types.submodule {
    options = {
      owner = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      group = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      mode  = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    };
  };

  pick = a: b: if a != null then a else b;
in {
  options.homelab.stateRoot = lib.mkOption {
    type = lib.types.str;
    default = "/var/lib/microvms/${config.networking.hostName}";
    description = "Host dir holding this guest's state.img block image (matches the microvm's stateRoot).";
  };

  options.homelab.volumeSize = lib.mkOption {
    type = lib.types.int;
    default = 4096;
    description = "Size (MiB) of the auto-declared state.img block image backing homelab.volumes.";
  };

  options.homelab.volumes = lib.mkOption {
    default = {};
    description = "Per-service state dirs bound off the block /var/lib/state volume.";
    type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
      options = {
        path   = lib.mkOption { type = lib.types.str; default = "/var/lib/${name}"; description = "Guest mount path."; };
        source = lib.mkOption { type = lib.types.str; default = name; description = "Subdir under /var/lib/state."; };
        owner  = lib.mkOption { type = lib.types.str; default = name; description = "Owning guest user."; };
        group  = lib.mkOption { type = lib.types.str; default = config.owner; description = "Owning group (default = owner)."; };
        mode   = lib.mkOption { type = lib.types.str; default = "0750"; description = "Root dir mode."; };
        dirs   = lib.mkOption { type = lib.types.attrsOf dirMod; default = {}; description = "Nested child dirs; perm fields inherit the root dir when null."; };
      };
    }));
  };

  config = lib.mkIf (cfg != {}) {
    microvm.volumes = [{
      image = "${config.homelab.stateRoot}/state.img";
      mountPoint = "/var/lib/state";
      size = config.homelab.volumeSize;
    }];

    systemd.tmpfiles.rules = lib.concatLists (lib.mapAttrsToList (_: v:
      [ "d /var/lib/state/${v.source} ${v.mode} ${v.owner} ${v.group} -" ]
      ++ lib.mapAttrsToList (rel: d:
           "d ${v.path}/${rel} ${pick d.mode v.mode} ${pick d.owner v.owner} ${pick d.group v.group} -"
         ) v.dirs
    ) cfg);

    fileSystems = lib.mapAttrs' (_: v: lib.nameValuePair v.path {
      device = "/var/lib/state/${v.source}";
      options = [ "bind" ];
      depends = [ "/var/lib/state" ];
    }) cfg;
  };
}
