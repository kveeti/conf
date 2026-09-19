{ config, lib, ... }:

let
  cfg = config.homelab.nginxMetrics;
in {
  options.homelab.nginxMetrics = {
    statusPort = lib.mkOption {
      type = lib.types.port;
      default = 8050;
      description = "Local nginx status port.";
    };

    exporterPort = lib.mkOption {
      type = lib.types.port;
      default = 9113;
      description = "Local nginx exporter port.";
    };
  };

  config = {
    services.nginx.virtualHosts."nginx-status" = {
      listen = [{ addr = "127.0.0.1"; port = cfg.statusPort; }];
      locations."/stub_status".extraConfig = ''
        stub_status;
        access_log off;
      '';
    };

    services.prometheus.exporters.nginx = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.exporterPort;
      scrapeUri = "http://127.0.0.1:${toString cfg.statusPort}/stub_status";
    };

    homelab.metrics.scrapes.nginx.targets = [
      "127.0.0.1:${toString cfg.exporterPort}"
    ];
  };
}
