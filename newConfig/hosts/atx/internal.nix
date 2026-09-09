{ config, adminKeys, food, inventory, lib, pkgs, rss, weather, ... }:

let
  name = "internal";
  inventoryKey = "atx-internal";
  stateRoot = "/var/lib/microvms/${name}";
  host = inventory.hosts.${inventoryKey};
  network = inventory.networks.${host.network};
  bridge = "br-${network.interface}";
  secretDir = "${stateRoot}/secrets";
  certDir = "${stateRoot}/cert/internal.veetik.com";
  privateModules = config.homelab.microvms.${name}.guestModules or [];

  directSecrets = [
    "radicale-users"
    "food-secrets"
    "weather-secrets"
    "samba-syncer-pass"
    "paperless-security-password"
    "restic-internal-rest-pass"
    "restic-internal-encryption-pass"
    "telemetry-pass"
    "oidc-rss-client-secret"
    "oidc-paperless-client-secret"
    "oauth2-rss-cookie-secret"
    "oauth2-paperless-cookie-secret"
  ];

  copySecret = secret: ''
    install -m 0400 ${config.age.secrets.${secret}.path} ${secretDir}/${secret}
  '';

  copyCertificate = ''
    if [ -f /var/lib/acme/internal.veetik.com/fullchain.pem ]; then
      install -m 0644 -o root -g cert-readers \
        /var/lib/acme/internal.veetik.com/fullchain.pem ${certDir}/fullchain.pem
      install -m 0640 -o root -g cert-readers \
        /var/lib/acme/internal.veetik.com/key.pem ${certDir}/key.pem
    fi
  '';
in {
  age.secrets = lib.genAttrs directSecrets (_: {});

  system.activationScripts.internal-files = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0755 ${stateRoot}/ssh
      install -d -m 0711 ${secretDir}
      install -d -m 0755 -o root -g cert-readers ${certDir}
      rm -f ${secretDir}/restic-internal-repo
      ${lib.concatMapStringsSep "\n" copySecret directSecrets}
      chown 700:700 ${secretDir}/radicale-users
      printf 'PAPERLESS_SOCIALACCOUNT_PROVIDERS={"openid_connect":{"SCOPE":["openid","profile","email"],"APPS":[{"provider_id":"keycloak","name":"Keycloak","client_id":"paperless","secret":"%s","settings":{"server_url":"https://auth.veetik.com/realms/main/.well-known/openid-configuration","oauth_pkce_enabled":true}}]}}\n' \
        "$(cat ${config.age.secrets.oidc-paperless-client-secret.path})" \
        > ${secretDir}/paperless-oidc-env
      chmod 0400 ${secretDir}/paperless-oidc-env
      ${copyCertificate}
    '';
  };

  systemd.services.copy-internal-certificate = {
    description = "Copy the internal certificate into Internal VM state";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = copyCertificate;
  };
  security.acme.certs."internal.veetik.com".reloadServices = [
    "copy-internal-certificate.service"
  ];

  systemd.network.networks."60-vm-internal" = {
    matchConfig.Name = "vm-internal";
    networkConfig.Bridge = bridge;
  };

  microvm.vms.internal = {
    specialArgs = { inherit adminKeys food inventory rss weather; };
    config = { config, ... }: {
      imports = [
        ../../modules/profiles/microvm.nix
        ../../modules/features/nginx-metrics.nix
        ../../modules/services/microvm-volumes.nix
        ../../modules/services/postgresql.nix
        ../../modules/services/restic-backups.nix
        ../../modules/services/shared-secrets.nix
        rss.nixosModules.default
        food.nixosModules.default
        weather.nixosModules.default
        ./internal/food.nix
        ./internal/paperless.nix
        ./internal/radicale.nix
        ./internal/rss.nix
        ./internal/shared-folder.nix
        ./internal/weather.nix
      ] ++ privateModules;

      homelab = {
        hostKey = inventoryKey;
        stateRoot = stateRoot;
        volumeSize = 8192;
        volumes.postgresql = {
          owner = "postgres";
          mode = "0750";
        };
        backups.serverUrl = "https://backup.internal.veetik.com:${toString inventory.hosts.backup.ports.restic}";
        nginxMetrics = {
          statusPort = config.homelab.ports.nginxStatus;
          exporterPort = config.homelab.ports.nginxExporter;
        };
      };

      networking = {
        hostName = host.hostname;
        hosts.${inventory.hosts.public.ipv4} = [ "auth.veetik.com" ];
        firewall.allowedTCPPorts = [
          config.homelab.ports.http
          config.homelab.ports.https
        ];
      };

      microvm = {
        mem = lib.mkForce 3072;
        interfaces = [{
          type = "tap";
          id = "vm-internal";
          mac = "02:00:00:40:00:01";
        }];
        shares = [
          {
            source = "${stateRoot}/ssh";
            mountPoint = "/run/ssh-host";
            tag = "ssh-host";
            proto = "virtiofs";
          }
          {
            source = secretDir;
            mountPoint = "/run/secrets";
            tag = "secrets";
            proto = "virtiofs";
            readOnly = true;
          }
          {
            source = "${stateRoot}/cert";
            mountPoint = "/run/cert";
            tag = "cert";
            proto = "virtiofs";
            readOnly = true;
          }
        ];
      };

      systemd.network = {
        enable = true;
        networks."10-ethernet" = {
          matchConfig.Type = "ether";
          address = [ "${host.ipv4}/${lib.last (lib.splitString "/" network.cidr4)}" ];
          routes = [{ Gateway = network.router4; }];
          networkConfig.DHCP = "no";
        };
      };

      users = {
        groups = {
          cert-readers.gid = 6500;
          radicale.gid = 700;
          food.gid = 701;
          weather.gid = 702;
          syncer.gid = 703;
        };
        users = {
          nginx.extraGroups = [ "cert-readers" ];
          radicale.uid = 700;
          food.uid = 701;
          weather.uid = 702;
          syncer.uid = 703;
        };
      };

      services.prometheus.exporters.postgres.port = config.homelab.ports.postgresqlExporter;

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
      };

      systemd = {
        services.nginx.unitConfig.ConditionPathExists = [
          "/run/cert/internal.veetik.com/fullchain.pem"
          "/run/cert/internal.veetik.com/key.pem"
        ];
        paths.nginx-internal-certificate = {
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathChanged = "/run/cert/internal.veetik.com/fullchain.pem";
            Unit = "nginx-certificate-reload.service";
          };
        };
        services.nginx-certificate-reload = {
          description = "Reload nginx when its certificate changes";
          serviceConfig.Type = "oneshot";
          script = "${pkgs.systemd}/bin/systemctl reload-or-restart nginx.service";
        };
      };

      _module.args.withSharedVhost = virtualHost: {
        forceSSL = true;
        quic = true;
        sslCertificate = "/run/cert/internal.veetik.com/fullchain.pem";
        sslCertificateKey = "/run/cert/internal.veetik.com/key.pem";
      } // virtualHost;
    };
  };
}
