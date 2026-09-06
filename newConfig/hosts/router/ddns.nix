{ config, pkgs, ... }:

let
  updateDns = pkgs.writeShellApplication {
    name = "update-cloudflare-dns";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq ];
    text = ''
      providers=(
        "https://ip.veetik.com"
        "https://ipv4.icanhazip.com"
        "https://api.ipify.org"
        "https://ifconfig.co/ip"
        "https://checkip.amazonaws.com"
      )

      valid_ipv4() {
        local ip="$1"
        [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

        local octet
        local -a octets
        IFS=. read -ra octets <<<"$ip"
        for octet in "''${octets[@]}"; do
          ((octet >= 0 && octet <= 255)) || return 1
        done
      }

      current_ip=
      for provider in "''${providers[@]}"; do
        candidate=$(curl --fail --silent --show-error --location --max-time 10 "$provider" 2>/dev/null | tr -d '[:space:]') || continue
        if valid_ipv4 "$candidate"; then
          current_ip="$candidate"
          break
        fi
      done

      if [[ -z "$current_ip" ]]; then
        echo "Could not determine the public IPv4 address" >&2
        exit 1
      fi

      api() {
        local method="$1"
        local endpoint="$2"
        local payload="''${3:-}"
        local -a args=(
          --fail
          --silent
          --show-error
          --request "$method"
          "https://api.cloudflare.com/client/v4$endpoint"
          --header "Authorization: Bearer $CF_API_TOKEN"
          --header "Content-Type: application/json"
        )
        if [[ -n "$payload" ]]; then
          args+=(--data "$payload")
        fi
        curl "''${args[@]}"
      }

      records=$(api GET "/zones/$ZONE_ID/dns_records?type=A&name=$RECORD_NAME")
      record_id=$(jq --raw-output '.result[0].id // empty' <<<"$records")
      record_ip=$(jq --raw-output '.result[0].content // empty' <<<"$records")

      if [[ "$record_ip" == "$current_ip" ]]; then
        echo "$RECORD_NAME already points to $current_ip"
        exit 0
      fi

      payload=$(jq --null-input --compact-output \
        --arg name "$RECORD_NAME" \
        --arg content "$current_ip" \
        '{type: "A", name: $name, content: $content, ttl: 1, proxied: false}')

      if [[ -n "$record_id" ]]; then
        response=$(api PUT "/zones/$ZONE_ID/dns_records/$record_id" "$payload")
      else
        response=$(api POST "/zones/$ZONE_ID/dns_records" "$payload")
      fi

      if ! jq --exit-status '.success == true' <<<"$response" >/dev/null; then
        jq '.errors' <<<"$response" >&2
        exit 1
      fi

      echo "$RECORD_NAME now points to $current_ip"
    '';
  };
in {
  age.secrets.cloudflare_ddns_env = {};

  systemd.services.cloudflare-ddns = {
    description = "Update the public Cloudflare DNS record";
    wants = [ "network-online.target" "unbound.service" ];
    after = [ "network-online.target" "unbound.service" ];
    path = [ updateDns ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updateDns}/bin/update-cloudflare-dns";
      EnvironmentFile = config.age.secrets.cloudflare_ddns_env.path;
      DynamicUser = true;
      CapabilityBoundingSet = [ "" ];
      DeviceAllow = [ "" ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      UMask = "0077";
    };
  };

  systemd.timers.cloudflare-ddns = {
    description = "Update Cloudflare DNS each minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/1";
      Persistent = true;
      RandomizedDelaySec = "15s";
    };
  };

  homelab.logs.units."cloudflare-ddns.service" = {
    format = "plain";
    serviceName = "cloudflare-ddns";
  };
}
