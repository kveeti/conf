{ config, lib, ... }:

let
  cfg = config.homelab.metrics;

  addInstanceLabel = job: job // {
    relabel_configs = (job.relabel_configs or []) ++ [{
      target_label = "instance";
      replacement = cfg.host;
    }];
  };

  scrapeJobs = lib.mapAttrsToList (name: scrape: addInstanceLabel ({
    job_name = name;
    metrics_path = scrape.path;
    static_configs = [{ targets = scrape.targets; }];
  } // lib.optionalAttrs (scrape.authorizationFile != null) {
    authorization.credentials_file = scrape.authorizationFile;
  })) cfg.scrapes;
in {
  options.homelab.metrics = {
    enable = lib.mkEnableOption "metrics collection";

    host = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Host label added to all metrics.";
    };

    remoteWriteUrl = lib.mkOption {
      type = lib.types.str;
      description = "VictoriaMetrics write URL.";
    };

    username = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional write username.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional write password file.";
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "Default scrape interval.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8429";
      description = "Local vmagent HTTP address.";
    };

    nodeExporter = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Collect host metrics.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9100;
        description = "Local node exporter port.";
      };

      collectors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "systemd" ];
        description = "Extra node exporter collectors.";
      };
    };

    scrapes = lib.mkOption {
      default = {};
      description = "Local metric endpoints, keyed by job name.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          targets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Endpoints scraped by this job.";
          };

          path = lib.mkOption {
            type = lib.types.str;
            default = "/metrics";
            description = "Metrics path.";
          };

          authorizationFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional bearer token file.";
          };
        };
      });
    };

    extraScrapeConfigs = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [];
      description = "Raw Prometheus scrape jobs for cases the simple API cannot express.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = (cfg.username == null) == (cfg.passwordFile == null);
      message = "homelab.metrics username and passwordFile must be set together";
    }];

    services.prometheus.exporters.node = lib.mkIf cfg.nodeExporter.enable {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.nodeExporter.port;
      enabledCollectors = cfg.nodeExporter.collectors;
    };

    services.vmagent = {
      enable = true;
      extraArgs = [ "-httpListenAddr=${cfg.listenAddress}" ];
      remoteWrite = {
        url = cfg.remoteWriteUrl;
        basicAuthUsername = cfg.username;
        basicAuthPasswordFile = cfg.passwordFile;
      };
      prometheusConfig = {
        global = {
          scrape_interval = cfg.scrapeInterval;
          external_labels.host = cfg.host;
        };
        scrape_configs =
          lib.optional cfg.nodeExporter.enable (addInstanceLabel {
            job_name = "node";
            static_configs = [{ targets = [ "127.0.0.1:${toString cfg.nodeExporter.port}" ]; }];
          })
          ++ scrapeJobs
          ++ map addInstanceLabel cfg.extraScrapeConfigs;
      };
    };
  };
}
