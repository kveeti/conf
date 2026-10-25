{ config, inventory, ... }:

let
  ports = config.homelab.ports;
in {
  networking.firewall.extraInputRules = ''
    ip saddr ${inventory.hosts.worker.ipv4} \
      tcp dport { ${toString ports.victoriametrics}, ${toString ports.victorialogs}, ${toString ports.victoriatraces} } accept
  '';

  services.victoriametrics = {
    enable = true;
    listenAddress = "0.0.0.0:${toString ports.victoriametrics}";
    stateDir = "victoriametrics";
    retentionPeriod = "12";
  };

  services.victorialogs = {
    enable = true;
    listenAddress = "0.0.0.0:${toString ports.victorialogs}";
    stateDir = "victorialogs";
    extraOptions = [ "-retentionPeriod=90d" ];
  };

  services.victoriatraces = {
    enable = true;
    listenAddress = "0.0.0.0:${toString ports.victoriatraces}";
    stateDir = "victoriatraces";
    retentionPeriod = "30d";
    extraOptions = [
      "-otlpGRPCListenAddr=127.0.0.1:${toString ports.victoriatracesOtlp}"
      "-otlpGRPC.tls=false"
    ];
  };
}
