{ config, lib, ... }:

let
  cfg = config.homelab.nginxMetrics;
in {
  options.homelab.nginxMetrics = {
    enable = lib.mkEnableOption "stub_status + prometheus nginx exporter, scraped by the local vmagent";

    statusPort = lib.mkOption {
      type = lib.types.port;
      default = 8050;
      description = "Loopback port serving nginx stub_status for the exporter.";
    };

    exporterPort = lib.mkOption {
      type = lib.types.port;
      default = 9113;
      description = "prometheus-nginx-exporter listen port (bound to localhost).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."nginx-stub-status" = {
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

    homelab.metrics.scrapeConfigs = [{
      job_name = "nginx";
      static_configs = [{ targets = [ "127.0.0.1:${toString cfg.exporterPort}" ]; }];
    }];
  };
}
