{ config, inventory, lib, ... }:

let
  host = inventory.hosts.${config.networking.hostName};
  kubeIp = host.kubeIpv4 or host.ipv4;
  kubeInterface = if host ? kubeIpv4 then "vlan${toString inventory.networks.kube.vlan}" else "ens3";
  kubeReservedRange = "192.168.50.0/27";
in {
  services.k3s = {
    enable = true;
    role = "server";
    nodeIP = kubeIp;
    disable = [ "traefik" "servicelb" ];
    extraFlags = [
      "--advertise-address=${kubeIp}"
      "--flannel-iface=${kubeInterface}"
      "--tls-san=192.168.50.2"
      "--secrets-encryption"
    ];
  };

  networking.firewall = {
    trustedInterfaces = [ "cni0" "flannel.1" ];
    interfaces.${kubeInterface} = {
      allowedTCPPorts = [ 2379 2380 6443 10250 ];
      allowedUDPPorts = [ 8472 ];
    };
  };

  systemd.network.networks."20-kube" = lib.mkIf (host ? kubeIpv4) {
    routes = [{
      Gateway = inventory.networks.kube.router4;
      Table = 50;
    }];
    routingPolicyRules = [
      {
        IncomingInterface = "flannel.1";
        Table = "main";
        SuppressPrefixLength = 0;
        Priority = 998;
      }
      {
        IncomingInterface = "cni0";
        Table = "main";
        SuppressPrefixLength = 0;
        Priority = 999;
      }
      {
        From = kubeReservedRange;
        Table = "main";
        SuppressPrefixLength = 0;
        Priority = 1000;
      }
      {
        From = kubeReservedRange;
        Table = 50;
        Priority = 1001;
      }
      {
        IncomingInterface = "flannel.1";
        Table = 50;
        Priority = 1002;
      }
      {
        IncomingInterface = "cni0";
        Table = 50;
        Priority = 1003;
      }
    ];
  };
}
