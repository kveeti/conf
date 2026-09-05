{ ... }:

{
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
    url = "http://127.0.0.1:19428";
  };

  homelab.metrics = {
    enable = true;
    remoteWriteUrl = "http://127.0.0.1:18428/api/v1/write";
    scrapes = {
      victoriametrics.targets = [ "127.0.0.1:18428" ];
      vmagent.targets = [ "127.0.0.1:8429" ];
    };
  };
}
