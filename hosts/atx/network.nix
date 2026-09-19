{ inventory, lib, ... }:

let
  host = inventory.hosts.atx;
  networks = inventory.networks;
  hostNetwork = networks.${host.network};
  guestNetworkNames = [ "minecraft" "iot" "media" ];
  guestNetworks = map (name: networks.${name}) guestNetworkNames;

  bridgeName = network: "br-${network.interface}";

  mkBridge = network:
    lib.nameValuePair "10-${bridgeName network}" {
      netdevConfig = {
        Name = bridgeName network;
        Kind = "bridge";
      };
    };

  mkVlan = network:
    lib.nameValuePair "20-${network.interface}" {
      netdevConfig = {
        Name = network.interface;
        Kind = "vlan";
      };
      vlanConfig.Id = network.vlan;
    };

  attachVlanToBridge = network:
    lib.nameValuePair "40-${network.interface}" {
      matchConfig.Name = network.interface;
      networkConfig.Bridge = bridgeName network;
    };

  configureGuestBridge = network:
    lib.nameValuePair "50-${bridgeName network}" {
      matchConfig.Name = bridgeName network;
      networkConfig = {
        LinkLocalAddressing = "no";
        DHCP = "no";
      };
    };

  bridgeDevices = builtins.listToAttrs (map mkBridge ([ hostNetwork ] ++ guestNetworks));
  vlanDevices = builtins.listToAttrs (map mkVlan guestNetworks);
  vlanAttachments = builtins.listToAttrs (map attachVlanToBridge guestNetworks);
  guestBridges = builtins.listToAttrs (map configureGuestBridge guestNetworks);
in {
  systemd.network = {
    enable = true;
    wait-online.ignoredInterfaces = [ "wlo1" ];

    netdevs = bridgeDevices // vlanDevices;

    networks = {
      "30-trunk" = {
        matchConfig.Name = host.interface;
        networkConfig = {
          Bridge = bridgeName hostNetwork;
          VLAN = map (network: network.interface) guestNetworks;
        };
      };

      "50-host-bridge" = {
        matchConfig.Name = bridgeName hostNetwork;
        address = [ "${host.ipv4}/${lib.last (lib.splitString "/" hostNetwork.cidr4)}" ];
        routes = [{ Gateway = hostNetwork.router4; }];
        networkConfig.DHCP = "no";
      };
    } // vlanAttachments // guestBridges;
  };
}
