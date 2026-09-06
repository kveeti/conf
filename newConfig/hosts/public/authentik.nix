{ config, inventory, pkgs, ... }:

let
  domain = "auth2.veetik.com";
  publicIp = inventory.hosts.public.ipv4;
  ports = config.homelab.ports;
  environmentFile = "/run/authentik-config/environment";

  environment = {
    HOME = "/var/lib/authentik";
    AUTHENTIK_POSTGRESQL__HOST = "/run/postgresql";
    AUTHENTIK_POSTGRESQL__NAME = "authentik";
    AUTHENTIK_POSTGRESQL__USER = "authentik";
    AUTHENTIK_POSTGRESQL__SSLMODE = "disable";
    AUTHENTIK_LISTEN__HTTP = "127.0.0.1:${toString ports.authentik}";
    AUTHENTIK_LISTEN__HTTPS = "127.0.0.1:${toString ports.authentikHttps}";
    AUTHENTIK_LISTEN__LDAP = "127.0.0.1:${toString ports.authentikLdap}";
    AUTHENTIK_LISTEN__LDAPS = "127.0.0.1:${toString ports.authentikLdaps}";
    AUTHENTIK_LISTEN__RADIUS = "127.0.0.1:${toString ports.authentikRadius}";
    AUTHENTIK_LISTEN__METRICS = "127.0.0.1:${toString ports.authentikMetrics}";
    AUTHENTIK_LISTEN__DEBUG = "127.0.0.1:${toString ports.authentikDebug}";
    AUTHENTIK_LISTEN__DEBUG_PY = "127.0.0.1:${toString ports.authentikDebugPython}";
    AUTHENTIK_STORAGE__FILE__PATH = "/var/lib/authentik/media";
    AUTHENTIK_ERROR_REPORTING__ENABLED = "false";
    AUTHENTIK_DISABLE_UPDATE_CHECK = "true";
    AUTHENTIK_DISABLE_STARTUP_ANALYTICS = "true";
    AUTHENTIK_OUTPOSTS__DISABLE_EMBEDDED_OUTPOST = "true";
  };

  service = command: {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "authentik-environment.service" ];
    requires = [ "authentik-environment.service" ];
    inherit environment;
    serviceConfig = {
      ExecStart = "${pkgs.authentik}/bin/ak ${command}";
      User = "authentik";
      Group = "authentik";
      StateDirectory = "authentik";
      WorkingDirectory = "/var/lib/authentik";
      EnvironmentFile = environmentFile;
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      PrivateTmp = true;
      TemporaryFileSystem = [ "/dev/shm:rw,nodev,nosuid,mode=1777" ];
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/authentik" ];
    };
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

  users.groups.authentik = {};
  users.users.authentik = {
    isSystemUser = true;
    group = "authentik";
    home = "/var/lib/authentik";
  };

  systemd.services = {
    authentik-environment = {
      description = "Prepare Authentik secrets";
      requiredBy = [ "authentik-server.service" "authentik-worker.service" ];
      before = [ "authentik-server.service" "authentik-worker.service" ];
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

    authentik-server = service "server";
    authentik-worker = service "worker";

    authentik-config = {
      description = "Apply the homelab Authentik blueprint";
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik-server.service" "authentik-worker.service" ];
      requires = [ "authentik-server.service" "authentik-worker.service" ];
      path = [ pkgs.authentik pkgs.curl ];
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        EnvironmentFile = environmentFile;
        PrivateTmp = true;
        TemporaryFileSystem = [ "/dev/shm:rw,nodev,nosuid,mode=1777" ];
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

        exec ak apply_blueprint ${./authentik-blueprint.yaml}
      '';
    };
  };

  homelab.postgresql.databases.authentik = {
    services = [ "authentik-server" "authentik-worker" ];
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
    };
  };

  networking.hosts.${publicIp} = [ domain ];

  homelab.metrics.scrapes.authentik.targets = [
    "127.0.0.1:${toString ports.authentikMetrics}"
  ];

  homelab.logs.units = {
    "authentik-server.service" = {
      format = "json";
      serviceName = "authentik";
    };
    "authentik-worker.service" = {
      format = "json";
      serviceName = "authentik-worker";
    };
    "authentik-config.service" = {
      format = "json";
      serviceName = "authentik-config";
    };
  };
}
