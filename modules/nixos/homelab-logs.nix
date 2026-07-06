{ config, lib, ... }:

let
  cfg = config.homelab.logs;
in {
  options.homelab.logs = {
    enable = lib.mkEnableOption "ship journald logs to the homelab VictoriaLogs via a local vector";

    url = lib.mkOption {
      type = lib.types.str;
      description = "VictoriaLogs base URL, no trailing slash (e.g. http://backup.internal.veetik.com:9428).";
    };

    streamFields = lib.mkOption {
      type = lib.types.str;
      default = "host,_SYSTEMD_UNIT";
      description = "Comma-separated journald fields VictoriaLogs uses as the log stream key.";
    };

    extraSources = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = "Additional vector sources merged in (e.g. a file source for suricata eve.json).";
    };

    extraInputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Names of extraSources to also feed into the VictoriaLogs sink.";
    };
  };

  config = lib.mkIf cfg.enable {
    # vector is DynamicUser; without this its journald source can't read /var/log/journal and ships nothing
    systemd.services.vector.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];

    services.vector = {
      enable = true;
      settings = {
        sources = {
          journald = {
            type = "journald";
            current_boot_only = false;
          };
        } // cfg.extraSources;

        # map journald's numeric syslog PRIORITY (0-7) into a `level` field so
        # VictoriaLogs/Grafana recognize the log level instead of "unknown"
        transforms.journald_level = {
          type = "remap";
          inputs = [ "journald" ];
          source = ''
            priority = to_int(.PRIORITY) ?? 6
            .level = if priority <= 2 {
              "critical"
            } else if priority == 3 {
              "error"
            } else if priority == 4 {
              "warning"
            } else if priority == 5 || priority == 6 {
              "info"
            } else {
              "debug"
            }
          '';
        };

        sinks.vlogs = {
          type = "elasticsearch";
          inputs = [ "journald_level" ] ++ cfg.extraInputs;
          endpoints = [ "${cfg.url}/insert/elasticsearch/" ];
          mode = "bulk";
          api_version = "v8";
          healthcheck.enabled = false;
          query = {
            _msg_field = "message";
            _time_field = "timestamp";
            _stream_fields = cfg.streamFields;
          };
        };
      };
    };
  };
}
