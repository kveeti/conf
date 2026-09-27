{ config, inventory, ... }:

let
  host = inventory.hosts.${config.networking.hostName};
  kubeIp = host.kubeIpv4 or host.ipv4;
  kubeInterface = if host ? kubeIpv4 then "vlan${toString inventory.networks.kube.vlan}" else "ens3";
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
    ];
  };

  networking.firewall = {
    trustedInterfaces = [ "cni0" "flannel.1" ];
    interfaces.${kubeInterface} = {
      allowedTCPPorts = [ 2379 2380 6443 10250 ];
      allowedUDPPorts = [ 8472 ];
    };
  };
}
