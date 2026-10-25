{ config, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [
    ../../../modules/features/disk-health.nix
    ../../../modules/features/nginx-metrics.nix
    ../../../modules/telemetry/logs.nix
    ../../../modules/telemetry/metrics.nix
    ./ingest.nix
    ./probes.nix
    ./query.nix
    ./storage.nix
    ./tracing.nix
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
      opentelemetry.targets = [ "127.0.0.1:${toString ports.otelCollectorMetrics}" ];
      victoriatraces.targets = [ "127.0.0.1:${toString ports.victoriatraces}" ];
    };
  };
}
