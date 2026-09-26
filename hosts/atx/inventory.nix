{ inventory, lib }:

inventory // {
  networks = lib.mapAttrs (_: network:
    network // lib.optionalAttrs (network ? vlan) {
      interface = "vlan${toString network.vlan}";
    }
  ) inventory.networks;

  hosts = inventory.hosts // {
    atx = inventory.hosts.atx // {
      interface = "enxc87f5465d1b8";
    };
  };
}
