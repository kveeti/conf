{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.logs;
  authEnabled = cfg.username != null && cfg.passwordFile != null;
  credentialsFile = "/run/vector-credentials/environment";
  json = builtins.toJSON;

  units = lib.mapAttrsToList (unit: value: {
    inherit unit;
    inherit (value) format serviceName;
  }) cfg.units;

  formatExpression = lib.foldr (entry: rest: ''
    if unit == ${json entry.unit} {
      ${json entry.format}
    } else {
      ${rest}
    }
  '') ''"auto"'' units;

  namedUnits = builtins.filter (entry: entry.serviceName != null) units;
  serviceExpression = lib.foldr (entry: rest: ''
    if unit == ${json entry.unit} {
      ${json entry.serviceName}
    } else {
      ${rest}
    }
  '') ''default_service'' namedUnits;
in {
  options.homelab.logs = {
    enable = lib.mkEnableOption "log collection";

    url = lib.mkOption {
      type = lib.types.str;
      description = "VictoriaLogs base URL.";
    };

    username = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional write username.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional file containing a base64url write password.";
    };

    streamFields = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "host" "service" "source" ];
      description = "Fields which identify a log stream.";
    };

    units = lib.mkOption {
      default = {};
      description = "Log rules keyed by systemd unit.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          format = lib.mkOption {
            type = lib.types.enum [ "auto" "json" "logfmt" "plain" ];
            default = "auto";
            description = "Message format.";
          };

          serviceName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Service name shown in logs.";
          };
        };
      });
    };

    extraVectorSources = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = "Raw Vector sources for logs outside journald.";
    };

    extraVectorInputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Pre-normalized Vector inputs sent to VictoriaLogs.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = (cfg.username == null) == (cfg.passwordFile == null);
      message = "homelab.logs username and passwordFile must be set together";
    }];

    systemd.services.vector-credentials = lib.mkIf authEnabled {
      description = "Prepare Vector credentials";
      before = [ "vector.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "vector-credentials";
        RuntimeDirectoryMode = "0700";
        LoadCredential = [ "password:${cfg.passwordFile}" ];
      };
      script = ''
        password="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/password")"
        if [[ ! "$password" =~ ^[A-Za-z0-9_-]+$ ]]; then
          echo "log write password must be base64url" >&2
          exit 1
        fi
        printf 'TELEMETRY_PASSWORD=%s\n' "$password" > ${credentialsFile}
        chmod 0600 ${credentialsFile}
      '';
    };

    systemd.services.vector = {
      requires = lib.optional authEnabled "vector-credentials.service";
      after = lib.optional authEnabled "vector-credentials.service";
      serviceConfig = {
        SupplementaryGroups = [ "systemd-journal" ];
        EnvironmentFile = lib.mkIf authEnabled credentialsFile;
      };
    };

    services.vector = {
      enable = true;
      validateConfig = !authEnabled;
      settings = {
        sources = {
          journald = {
            type = "journald";
            current_boot_only = false;
          };
        } // cfg.extraVectorSources;

        transforms.normalize_journald = {
          type = "remap";
          inputs = [ "journald" ];
          source = ''
            raw_message = if exists(.message) { to_string(.message) ?? "" } else { "" }
            message = strip_ansi_escape_codes(raw_message)
            event_timestamp = .timestamp
            unit = if exists(._SYSTEMD_UNIT) { to_string(._SYSTEMD_UNIT) ?? "" } else { "" }
            identifier = if exists(.SYSLOG_IDENTIFIER) { to_string(.SYSLOG_IDENTIFIER) ?? "" } else { "" }
            transport = if exists(._TRANSPORT) { to_string(._TRANSPORT) ?? "journal" } else { "journal" }
            priority = if exists(.PRIORITY) { to_int(.PRIORITY) ?? 6 } else { 6 }
            pid = if exists(._PID) { to_int(._PID) ?? null } else { null }
            boot_id = if exists(._BOOT_ID) { to_string(._BOOT_ID) ?? "" } else { "" }
            container = if exists(.CONTAINER_NAME) { to_string(.CONTAINER_NAME) ?? "" } else { "" }

            default_service = if unit != "" {
              replace(unit, r'\.service$', "")
            } else if identifier != "" {
              identifier
            } else {
              transport
            }

            format = ${formatExpression}
            payload = {}
            parsed = false
            parse_error = false
            trimmed = strip_whitespace(message)

            if format == "json" || (format == "auto" && starts_with(trimmed, "{")) {
              candidate, err = parse_json(message)
              if err == null && is_object(candidate) {
                payload = candidate
                parsed = true
              } else {
                parse_error = true
              }
            } else if format == "logfmt" {
              candidate, err = parse_key_value(message)
              if err == null {
                payload = candidate
                parsed = true
              } else {
                parse_error = true
              }
            }

            if parsed { . = payload } else { . = {} }

            if parsed && is_string(.message) {
              .message = string!(.message)
            } else if parsed && is_string(.msg) {
              .message = string!(.msg)
            } else {
              .message = message
            }
            del(.msg)

            app_level = if is_string(.level) {
              downcase(string!(.level))
            } else if is_string(.severity) {
              downcase(string!(.severity))
            } else {
              ""
            }

            mapped_app_level = if includes(["fatal", "panic", "alert", "emergency"], app_level) {
              "critical"
            } else if includes(["err", "error"], app_level) {
              "error"
            } else if includes(["warn", "warning"], app_level) {
              "warning"
            } else if includes(["notice", "info"], app_level) {
              "info"
            } else if includes(["trace", "debug"], app_level) {
              "debug"
            } else {
              ""
            }

            journal_level = if priority <= 2 {
              "critical"
            } else if priority == 3 {
              "error"
            } else if priority == 4 {
              "warning"
            } else if priority >= 7 {
              "debug"
            } else {
              "info"
            }

            if mapped_app_level != "" {
              .level = mapped_app_level
              .level_source = "app"
            } else {
              .level = journal_level
              .level_source = "journal"
            }
            del(.severity)

            if exists(.request_id) && !is_string(.request_id) { del(.request_id) }
            if !exists(.request_id) && is_string(.req_id) {
              .request_id = string!(.req_id)
            } else if !exists(.request_id) && is_string(.requestId) {
              .request_id = string!(.requestId)
            }
            del(.req_id)
            del(.requestId)

            del(._msg)
            del(._time)
            del(._stream)
            del(._stream_id)
            del(.pid)
            del(.boot_id)
            del(.container_name)
            del(.parse_error)

            .schema_version = 1
            .host = ${json config.networking.hostName}
            .unit = unit
            .service = ${serviceExpression}
            .source = "journal"
            .event_kind = "log"
            .journal_priority = priority
            .syslog_identifier = identifier
            .transport = transport
            .timestamp = event_timestamp

            if pid != null { .pid = pid }
            if boot_id != "" { .boot_id = boot_id }
            if container != "" { .container_name = container }
            if parse_error { .parse_error = true }
          '';
        };

        sinks.victorialogs = {
          type = "elasticsearch";
          inputs = [ "normalize_journald" ] ++ cfg.extraVectorInputs;
          endpoints = [ "${cfg.url}/insert/elasticsearch/" ];
          mode = "bulk";
          api_version = "v8";
          healthcheck.enabled = false;
          query = {
            _msg_field = "message";
            _time_field = "timestamp";
            _stream_fields = lib.concatStringsSep "," cfg.streamFields;
          };
        } // lib.optionalAttrs authEnabled {
          auth = {
            strategy = "basic";
            user = cfg.username;
            password = "\${TELEMETRY_PASSWORD}";
          };
        };
      };
    };
  };
}
