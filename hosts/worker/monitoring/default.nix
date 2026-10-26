{ config, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [
    ../../../modules/features/disk-health.nix
    ../../../modules/features/nginx-metrics.nix
    ../../../modules/telemetry/logs.nix
    ../../../modules/telemetry/metrics.nix
    ./grafana.nix
  ];

  homelab.logs = {
    enable = true;
    url = "https://logs.internal.veetik.com";
    username = "telemetry";
    passwordFile = config.age.secrets.telemetry-pass.path;
  };

  homelab.metrics = {
    enable = true;
    listenAddress = "127.0.0.1:${toString ports.vmagent}";
    nodeExporter.port = ports.nodeExporter;
    remoteWriteUrl = "https://metrics.internal.veetik.com/api/v1/write";
    username = "telemetry";
    passwordFile = config.age.secrets.telemetry-pass.path;
    scrapes.vmagent.targets = [ "127.0.0.1:${toString ports.vmagent}" ];
  };
}
