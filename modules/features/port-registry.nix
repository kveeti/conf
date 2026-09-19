{ config, inventory, lib, ... }:

let
  hostKey = config.homelab.hostKey;
  ports = config.homelab.ports;
  portNumbers = builtins.attrValues ports;
in {
  options.homelab = {
    hostKey = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Inventory key for this host.";
    };

    ports = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = inventory.hosts.${hostKey}.ports or {};
      readOnly = true;
      description = "Named listener ports assigned to this host.";
    };
  };

  config.assertions = [{
    assertion = builtins.length portNumbers == builtins.length (lib.unique portNumbers);
    message = "inventory.hosts.${hostKey}.ports contains duplicate ports";
  }];
}
