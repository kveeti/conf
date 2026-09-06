{ config, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [
    ../../../modules/features/disk-health.nix
    ../../../modules/telemetry/logs.nix
    ../../../modules/telemetry/metrics.nix
    ./grafana.nix
    ./ingest.nix
    ./probes.nix
    ./storage.nix
  ];

  homelab.logs = {
    enable = true;
    url = "http://127.0.0.1:${toString ports.victorialogs}";
  };

  homelab.metrics = {
    enable = true;
    listenAddress = "127.0.0.1:${toString ports.vmagent}";
    nodeExporter.port = ports.nodeExporter;
    remoteWriteUrl = "http://127.0.0.1:${toString ports.victoriametrics}/api/v1/write";
    scrapes = {
      victoriametrics.targets = [ "127.0.0.1:${toString ports.victoriametrics}" ];
      vmagent.targets = [ "127.0.0.1:${toString ports.vmagent}" ];
    };
  };
}
