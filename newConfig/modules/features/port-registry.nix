{ config, inventory, lib, ... }:

let
  hostName = config.networking.hostName;
  ports = config.homelab.ports;
  portNumbers = builtins.attrValues ports;
in {
  options.homelab.ports = lib.mkOption {
    type = lib.types.attrsOf lib.types.port;
    default = inventory.hosts.${hostName}.ports or {};
    readOnly = true;
    description = "Named listener ports assigned to this host.";
  };

  config.assertions = [{
    assertion = builtins.length portNumbers == builtins.length (lib.unique portNumbers);
    message = "inventory.hosts.${hostName}.ports contains duplicate ports";
  }];
}
