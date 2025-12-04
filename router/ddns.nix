{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cloudflare-ddns;

  ddnsScript = pkgs.writeShellApplication {
    name = "cf-ddns";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    
    text = ''
      set -euo pipefail

      IP_PROVIDERS=(
        "https://ip.veetik.com"
        "https://ipv4.icanhazip.com"
        "https://api.ipify.org"
        "https://ifconfig.co/ip"
        "https://checkip.amazonaws.com"
        "https://ipecho.net/plain"
      )

      log() {
        local level="$1"
        shift
        local message="$*"
        echo "$level: $message" >&2
      }

      is_valid_ipv4() {
        local ip="$1"
        [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
        
        local -a octets
        IFS='.' read -ra octets <<< "$ip"
        for octet in "''${octets[@]}"; do
          ((octet >= 0 && octet <= 255)) || return 1
        done
        return 0
      }

      get_public_ip() {
        local ip
        
        for provider in "''${IP_PROVIDERS[@]}"; do
          log "INFO" "Trying IP provider: $provider"
          
          if ip=$(curl -fsSL --max-time 10 "$provider" 2>/dev/null | tr -d '[:space:]'); then
            if is_valid_ipv4 "$ip"; then
              log "INFO" "Successfully retrieved IP: $ip (from $provider)"
              echo "$ip"
              return 0
            else
              log "WARN" "Invalid IPv4 format from $provider: '$ip'"
            fi
          else
            log "WARN" "Failed to query $provider"
          fi
        done
        
        log "ERROR" "Could not determine public IP from any provider"
        return 1
      }

      cf_api() {
        local method="$1"
        local endpoint="$2"
        local data="''${3:-}"
        
        local args=(
          -fsSL
          -X "$method"
          "https://api.cloudflare.com/client/v4$endpoint"
          -H "Authorization: Bearer $CF_API_TOKEN"
          -H "Content-Type: application/json"
        )
        
        [[ -n "$data" ]] && args+=(-d "$data")
        
        curl "''${args[@]}"
      }

      main() {
        log "INFO" "Starting Cloudflare DDNS update"
        
        local current_ip
        current_ip=$(get_public_ip) || exit 1

        log "INFO" "Looking up DNS record: $RECORD_NAME"
        local record_data
        record_data=$(cf_api GET "/zones/$ZONE_ID/dns_records?type=A&name=$RECORD_NAME")
        
        local record_id record_ip
        read -r record_id record_ip <<<"$(echo "$record_data" | jq -r '.result[0] | "\(.id // "") \(.content // "")"')"

        if [[ -z "$record_id" ]]; then
          log "INFO" "DNS record not found, creating: $RECORD_NAME -> $current_ip"
          local create_payload
          create_payload=$(jq -cn \
            --arg type "A" \
            --arg name "$RECORD_NAME" \
            --arg content "$current_ip" \
            '{type: $type, name: $name, content: $content, ttl: 1, proxied: false}')
          
          local response
          response=$(cf_api POST "/zones/$ZONE_ID/dns_records" "$create_payload")
          
          if echo "$response" | jq -e '.success' >/dev/null; then
            log "INFO" "Successfully created DNS record"
            exit 0
          else
            log "ERROR" "Failed to create DNS record: $(echo "$response" | jq -r '.errors[0].message // "Unknown error"')"
            exit 1
          fi
        fi

        if [[ "$record_ip" == "$current_ip" ]]; then
          log "INFO" "No update needed - $RECORD_NAME already points to $current_ip"
          exit 0
        fi

        log "INFO" "Updating DNS record: $RECORD_NAME from $record_ip to $current_ip"
        local update_payload
        update_payload=$(jq -cn \
          --arg type "A" \
          --arg name "$RECORD_NAME" \
          --arg content "$current_ip" \
          '{type: $type, name: $name, content: $content, ttl: 1, proxied: false}')
        
        local response
        response=$(cf_api PUT "/zones/$ZONE_ID/dns_records/$record_id" "$update_payload")
        
        if echo "$response" | jq -e '.success' >/dev/null; then
          log "INFO" "Successfully updated DNS record"
          exit 0
        else
          log "ERROR" "Failed to update DNS record: $(echo "$response" | jq -r '.errors[0].message // "Unknown error"')"
          exit 1
        fi
      }

      main "$@"
    '';
  };

in {
  options.services.cloudflare-ddns = {
    enable = mkEnableOption "Cloudflare Dynamic DNS service";

    environmentFile = mkOption {
      type = types.path;
      example = "/run/secrets/cloudflare-ddns-env";
      description = ''
        Path to environment file containing:
        - ZONE_ID: Cloudflare zone ID
        - RECORD_NAME: DNS A record to update
        - CF_API_TOKEN: Cloudflare API token
      '';
    };

    interval = mkOption {
      type = types.str;
      default = "*:0/5";
      example = "hourly";
      description = ''
        How often to check and update the DNS record.
        Uses systemd.time format (e.g., "hourly", "daily", "*:0/5" for every 5 minutes).
        See systemd.time(7) for more information.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.cloudflare-ddns = {
      description = "Cloudflare Dynamic DNS updater";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ddnsScript}/bin/cf-ddns";
        DynamicUser = true;

        CapabilityBoundingSet = [ "" ];
        DeviceAllow = [ "" ];
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        NoNewPrivileges = true;
        ProcSubset = "pid";
        ProtectSystem = "strict";
        ProtectClock = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        UMask = "0077";

        EnvironmentFile = cfg.environmentFile;
      };
    };

    systemd.timers.cloudflare-ddns = {
      description = "Timer for Cloudflare Dynamic DNS updater";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };
  };
}

