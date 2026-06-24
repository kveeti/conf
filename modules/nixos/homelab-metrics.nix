{ config, lib, ... }:

let
  cfg = config.homelab.metrics;
in {
  options.homelab.metrics = {
    enable = lib.mkEnableOption "push metrics to the homelab VictoriaMetrics via a local vmagent";

    remoteWriteUrl = lib.mkOption {
      type = lib.types.str;
      description = "VictoriaMetrics remote-write endpoint (…/api/v1/write).";
    };

    instance = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Value of the `host` external label attached to every series from this node.";
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "Global scrape interval.";
    };

    nodeExporter = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run node_exporter on localhost and scrape it.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 9100;
        description = "node_exporter listen port (bound to localhost).";
      };
      enabledCollectors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "systemd" ];
        description = "Extra node_exporter collectors to enable.";
      };
    };

    scrapeConfigs = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [];
      description = "Extra Prometheus scrape_configs for service exporters on this node.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.node = lib.mkIf cfg.nodeExporter.enable {
      enable = true;
      listenAddress = "127.0.0.1";
      inherit (cfg.nodeExporter) port enabledCollectors;
      extraFlags = [ "--collector.textfile.directory=/var/lib/node-exporter-textfile" ];
    };

    systemd.tmpfiles.rules = lib.mkIf cfg.nodeExporter.enable [
      "d /var/lib/node-exporter-textfile 0755 root root -"
    ];

    services.vmagent = {
      enable = true;
      remoteWrite.url = cfg.remoteWriteUrl;
      prometheusConfig = {
        global = {
          scrape_interval = cfg.scrapeInterval;
          external_labels.host = cfg.instance;
        };
        scrape_configs =
          lib.optional cfg.nodeExporter.enable {
            job_name = "node";
            static_configs = [{ targets = [ "127.0.0.1:${toString cfg.nodeExporter.port}" ]; }];
            relabel_configs = [{
              target_label = "instance";
              replacement = cfg.instance;
            }];
          }
          ++ map (sc: sc // {
            relabel_configs =
              [{ target_label = "instance"; replacement = cfg.instance; }]
              ++ (sc.relabel_configs or []);
          }) cfg.scrapeConfigs;
      };
    };
  };
}
