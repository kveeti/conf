{ config, ... }:

let
  ports = config.homelab.ports;
in {
  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:${toString ports.victoriametrics}";
    stateDir = "victoriametrics";
    retentionPeriod = "12";
  };

  services.victorialogs = {
    enable = true;
    listenAddress = "127.0.0.1:${toString ports.victorialogs}";
    stateDir = "victorialogs";
    extraOptions = [ "-retentionPeriod=90d" ];
  };
}
