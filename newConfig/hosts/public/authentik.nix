{ config, inventory, pkgs, ... }:

let
  domain = "auth2.veetik.com";
  publicIp = inventory.hosts.public.ipv4;
  ports = config.homelab.ports;
  environmentFile = "/run/authentik-config/environment";
  image = "ghcr.io/goauthentik/server@sha256:c0ab98c3d26d4fe66a513b0ac96ab97abc47cec9d4255abb0ba61e7f2dba1ce0";

  blueprintSecrets = [
    "authentik-google-client-id"
    "authentik-google-client-secret"
    "oidc-rss-client-secret"
    "oidc-paperless-client-secret"
    "oidc-grafana-client-secret"
    "oidc-money-client-secret"
  ];

  volumes = [
    "/run/postgresql:/run/postgresql:ro"
    "/var/lib/authentik:/data"
    "/var/lib/authentik/media:/media"
    "/var/lib/authentik/certs:/certs"
    "${./authentik-blueprint.yaml}:/blueprints/homelab.yaml:ro"
  ] ++ map (name: "${config.age.secrets.${name}.path}:/run/agenix/${name}:ro") blueprintSecrets;

  environment = {
    HOME = "/data";
    AUTHENTIK_POSTGRESQL__HOST = "/run/postgresql";
    AUTHENTIK_POSTGRESQL__NAME = "authentik";
    AUTHENTIK_POSTGRESQL__USER = "authentik";
    AUTHENTIK_POSTGRESQL__SSLMODE = "disable";
    AUTHENTIK_LISTEN__HTTP = "0.0.0.0:9000";
    AUTHENTIK_LISTEN__HTTPS = "127.0.0.1:${toString ports.authentikHttps}";
    AUTHENTIK_LISTEN__LDAP = "127.0.0.1:${toString ports.authentikLdap}";
    AUTHENTIK_LISTEN__LDAPS = "127.0.0.1:${toString ports.authentikLdaps}";
    AUTHENTIK_LISTEN__RADIUS = "127.0.0.1:${toString ports.authentikRadius}";
    AUTHENTIK_LISTEN__METRICS = "0.0.0.0:${toString ports.authentikMetrics}";
    AUTHENTIK_LISTEN__DEBUG = "127.0.0.1:${toString ports.authentikDebug}";
    AUTHENTIK_LISTEN__DEBUG_PY = "127.0.0.1:${toString ports.authentikDebugPython}";
    AUTHENTIK_STORAGE__FILE__PATH = "/media";
    AUTHENTIK_BLUEPRINTS_DIR = "/blueprints";
    AUTHENTIK_ERROR_REPORTING__ENABLED = "false";
    AUTHENTIK_DISABLE_UPDATE_CHECK = "true";
    AUTHENTIK_DISABLE_STARTUP_ANALYTICS = "true";
    AUTHENTIK_OUTPOSTS__DISABLE_EMBEDDED_OUTPOST = "true";
  };

  container = {
    inherit image volumes environment;
    environmentFiles = [ environmentFile ];
    user = "990:988";
    extraOptions = [ "--hostuser=authentik" ];
  };
in {
  age.secrets = {
    authentik-secret-key = {};
    authentik-google-client-id = {
      owner = "authentik";
      group = "authentik";
    };
    authentik-google-client-secret = {
      owner = "authentik";
      group = "authentik";
    };
    restic-authentik-rest-pass = {};
    restic-authentik-encryption-pass = {};
    oidc-rss-client-secret = {
      owner = "authentik";
      group = "authentik";
    };
    oidc-paperless-client-secret = {
      owner = "authentik";
      group = "authentik";
    };
    oidc-grafana-client-secret = {
      owner = "authentik";
      group = "authentik";
    };
    oidc-money-client-secret = {
      owner = "authentik";
      group = "authentik";
    };
  };

  users.groups.authentik.gid = 988;
  users.users.authentik = {
    isSystemUser = true;
    group = "authentik";
    home = "/var/lib/authentik";
    uid = 990;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/authentik 0750 authentik authentik -"
    "d /var/lib/authentik/media 0750 authentik authentik -"
    "d /var/lib/authentik/certs 0750 authentik authentik -"
  ];

  virtualisation.oci-containers.containers = {
    authentik-server = container // {
      cmd = [ "server" ];
      ports = [
        "127.0.0.1:${toString ports.authentik}:9000"
        "127.0.0.1:${toString ports.authentikMetrics}:${toString ports.authentikMetrics}"
      ];
    };
    authentik-worker = container // { cmd = [ "worker" ]; };
  };

  systemd.services = {
    authentik-environment = {
      description = "Prepare Authentik secrets";
      requiredBy = [ "podman-authentik-server.service" "podman-authentik-worker.service" ];
      before = [ "podman-authentik-server.service" "podman-authentik-worker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "authentik-config";
        RuntimeDirectoryMode = "0700";
        LoadCredential = [ "secret-key:${config.age.secrets.authentik-secret-key.path}" ];
      };
      script = ''
        printf 'AUTHENTIK_SECRET_KEY=%s\n' \
          "$(cat "$CREDENTIALS_DIRECTORY/secret-key")" \
          > ${environmentFile}
        printf 'AUTHENTIK_BOOTSTRAP_EMAIL=security@veetik.com\n' \
          >> ${environmentFile}
        printf 'AUTHENTIK_BOOTSTRAP_PASSWORD=/K4+m39XOZQw1jVLIvkwnXOIiPAr+9b9\n' \
          >> ${environmentFile}
        chmod 0400 ${environmentFile}
      '';
    };

    podman-authentik-server.unitConfig.RequiresMountsFor = [ "/var/lib/authentik" "/var/lib/containers" ];
    podman-authentik-worker.unitConfig.RequiresMountsFor = [ "/var/lib/authentik" "/var/lib/containers" ];

    authentik-config = {
      description = "Apply the homelab Authentik blueprint";
      wantedBy = [ "multi-user.target" ];
      after = [ "podman-authentik-server.service" "podman-authentik-worker.service" ];
      requires = [ "podman-authentik-server.service" "podman-authentik-worker.service" ];
      path = [ pkgs.podman pkgs.curl pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ready=false
        for _ in $(seq 1 120); do
          if curl --fail --silent http://127.0.0.1:${toString ports.authentik}/-/health/ready/ >/dev/null; then
            ready=true
            break
          fi
          sleep 1
        done

        if [ "$ready" != true ]; then
          echo "Authentik did not become ready within 120 seconds" >&2
          exit 1
        fi

        for attempt in 1 2 3; do
          if podman exec authentik-server ak apply_blueprint homelab.yaml; then
            exit 0
          fi
          if [ "$attempt" -lt 3 ]; then
            sleep 5
          fi
        done

        exit 1
      '';
    };
  };

  homelab.postgresql.databases.authentik = {
    services = [ "podman-authentik-server" "podman-authentik-worker" ];
    backup = {
      restPasswordFile = config.age.secrets.restic-authentik-rest-pass.path;
      encryptionPasswordFile = config.age.secrets.restic-authentik-encryption-pass.path;
    };
  };

  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "veetik.com";
    forceSSL = true;
    listen = [
      { addr = publicIp; port = ports.http; }
      { addr = publicIp; port = ports.https; ssl = true; }
    ];
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString ports.authentik}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $hostname;
        proxy_set_header X-Request-ID $request_id;
      '';
    };
  };

  networking.hosts.${publicIp} = [ domain ];

  homelab.metrics.scrapes.authentik.targets = [
    "127.0.0.1:${toString ports.authentikMetrics}"
  ];

  homelab.logs.units = {
    "podman-authentik-server.service" = {
      format = "json";
      serviceName = "authentik";
    };
    "podman-authentik-worker.service" = {
      format = "json";
      serviceName = "authentik-worker";
    };
    "authentik-config.service" = {
      format = "json";
      serviceName = "authentik-config";
    };
  };
}
