{ ... }:

{
  imports = [
    ../../../modules/features/disk-health.nix
    ../../../modules/telemetry/metrics.nix
    ./storage.nix
  ];

  homelab.metrics = {
    enable = true;
    remoteWriteUrl = "http://127.0.0.1:18428/api/v1/write";
    scrapes = {
      victoriametrics.targets = [ "127.0.0.1:18428" ];
      vmagent.targets = [ "127.0.0.1:8429" ];
    };
  };
}
