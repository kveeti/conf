{ config, ... }:

{
  imports = [ ../telemetry/metrics.nix ];

  services.prometheus.exporters.smartctl = {
    enable = true;
    listenAddress = "127.0.0.1";
  };

  homelab.metrics.scrapes.smartctl.targets = [
    "127.0.0.1:${toString config.services.prometheus.exporters.smartctl.port}"
  ];
}
