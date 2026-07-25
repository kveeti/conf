{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.logs;
  basicAuthEnabled = cfg.basicAuthUsername != null && cfg.basicAuthPasswordFile != null;
  credentialsEnvironment = "/run/vector-telemetry-pass/environment";
in {
  options.homelab.logs = {
    enable = lib.mkEnableOption "ship journald logs to the homelab VictoriaLogs via a local vector";

    url = lib.mkOption {
      type = lib.types.str;
      description = "VictoriaLogs base URL, no trailing slash (e.g. http://backup.internal.veetik.com:9428).";
    };

    basicAuthUsername = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "HTTP Basic Auth username for log ingestion.";
    };

    basicAuthPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "File containing the HTTP Basic Auth password for log ingestion.";
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
    assertions = [{
      assertion =
        (cfg.basicAuthUsername == null)
        == (cfg.basicAuthPasswordFile == null);
      message = "homelab.logs basicAuthUsername and basicAuthPasswordFile must be set together";
    }];

    # Convert the password-only agenix secret into an EnvironmentFile without
    # putting it in the Nix store. Restrict passwords to a safe base64url form.
    systemd.services.vector-telemetry-pass = lib.mkIf basicAuthEnabled {
      description = "Prepare Vector telemetry credentials";
      before = [ "vector.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "vector-telemetry-pass";
        RuntimeDirectoryMode = "0700";
        LoadCredential = [ "telemetry_password:${cfg.basicAuthPasswordFile}" ];
      };
      script = ''
        password="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/telemetry_password")"
        if [[ ! "$password" =~ ^[A-Za-z0-9_-]+$ ]]; then
          echo "telemetry password must be non-empty base64url (A-Z, a-z, 0-9, _ or -)" >&2
          exit 1
        fi
        printf 'TELEMETRY_PASSWORD=%s\n' "$password" > ${credentialsEnvironment}
        chmod 0600 ${credentialsEnvironment}
      '';
    };

    # vector is DynamicUser; without this its journald source can't read /var/log/journal and ships nothing
    systemd.services.vector = {
      requires = lib.optional basicAuthEnabled "vector-telemetry-pass.service";
      after = lib.optional basicAuthEnabled "vector-telemetry-pass.service";
      serviceConfig = {
        SupplementaryGroups = [ "systemd-journal" ];
        EnvironmentFile = lib.mkIf basicAuthEnabled credentialsEnvironment;
      };
    };

    services.vector = {
      enable = true;
      # Build-time validation cannot resolve the runtime password environment variable.
      validateConfig = !basicAuthEnabled;
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
        } // lib.optionalAttrs basicAuthEnabled {
          auth = {
            strategy = "basic";
            user = cfg.basicAuthUsername;
            password = "\${TELEMETRY_PASSWORD}";
          };
        };
      };
    };
  };
}
