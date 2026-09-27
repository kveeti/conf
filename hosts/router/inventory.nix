{ inventory, lib }:

let
  localInterfaces = {
    wireguard = "wg0";
    unifi = "vm-unifi";
  };

  vlanInterface = network: "vlan${toString network.vlan}";

  networks = lib.mapAttrs (name: network:
    network // (if network ? vlan then {
      vlanInterface = vlanInterface network;
      interface = if name == "iot" then "br-${vlanInterface network}" else vlanInterface network;
    } else {
      interface = localInterfaces.${name};
    })
  ) inventory.networks;
in
inventory // {
  inherit networks;

  router = {
    wanInterface = "wan0";
    lanInterface = "lan0";
    ifbInterface = "ifb-wan";
    sixRdInterface = "6rd-*";
    dhcpNetworks = {
      management = {
        start = "192.168.5.2";
        end = "192.168.5.254";
        lease = "24h";
      };
      trusted = {
        start = "192.168.10.200";
        end = "192.168.10.254";
        lease = "24h";
      };
      iot = {
        start = "192.168.20.10";
        end = "192.168.20.254";
        lease = "24h";
      };
      untrusted = {
        start = "192.168.30.2";
        end = "192.168.30.254";
        lease = "24h";
      };
      servers = {
        start = "192.168.40.200";
        end = "192.168.40.254";
        lease = "24h";
      };
      dmz = {
        start = "192.168.66.2";
        end = "192.168.66.2";
        lease = "24h";
        netmask = "255.255.255.248";
      };
      media = {
        start = "192.168.111.8";
        end = "192.168.111.8";
        lease = "24h";
        dns = [ "1.1.1.1" "1.0.0.1" "9.9.9.9" "149.112.112.112" ];
      };
    };
    dnsNetworks = [
      "wireguard"
      "management"
      "trusted"
      "iot"
      "untrusted"
      "servers"
      "kube"
      "dmz"
      "minecraft"
      "unifi"
    ];
    internetNetworks = [ "wireguard" "management" "trusted" "iot" "untrusted" "servers" "kube" "dmz" "minecraft" ];
    mdnsNetworks = [ "trusted" "iot" "untrusted" "servers" ];
  };
}
