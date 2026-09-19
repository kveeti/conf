{ config, inventory, lib, ... }:

let
  network = inventory.networks.wireguard;
  peers = builtins.attrValues (import ./wireguard-peers.nix);
  ports = config.homelab.ports;

  address4 =
    "${network.router4}/${lib.last (lib.splitString "/" network.cidr4)}";
in {
  age.secrets = lib.genAttrs
    ([ "wg_privkey" ] ++ map (peer: peer.presharedKeySecret) peers)
    (_: {
      mode = "0640";
      owner = "systemd-network";
      group = "systemd-network";
    });

  systemd.network = {
    networks."30-wireguard" = {
      matchConfig.Name = network.interface;
      address = [ address4 ];
      networkConfig.IPMasquerade = "ipv4";
    };

    netdevs."30-wireguard" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = network.interface;
        MTUBytes = "1300";
      };
      wireguardConfig = {
        PrivateKeyFile = config.age.secrets.wg_privkey.path;
        ListenPort = ports.wireguard;
      };
      wireguardPeers = map (peer: {
        PublicKey = peer.publicKey;
        PresharedKeyFile = config.age.secrets.${peer.presharedKeySecret}.path;
        AllowedIPs = [ "${peer.ipv4}/32" ];
      }) peers;
    };
  };
}
