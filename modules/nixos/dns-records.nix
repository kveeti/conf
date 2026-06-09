{ lib, ... }:

{
  options.homelab.dns = {
    defaultTargetHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Inventory host name that DNS records from this NixOS host point to by default.";
    };

    records = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "DNS names exposed by services on this NixOS host.";
    };
  };
}
