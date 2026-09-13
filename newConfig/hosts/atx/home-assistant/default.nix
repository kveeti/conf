{ config, adminKeys, inventory, lib, pkgs-unstable, ... }:

let
  name = "homeassistant";
  inventoryKey = "home-assistant";
  stateRoot = "/var/lib/microvms/${name}";
  secretDir = "${stateRoot}/secrets";
  certDir = "${stateRoot}/cert/internal.veetik.com";
  host = inventory.hosts.${inventoryKey};
  network = inventory.networks.${host.network};
  bridge = "br-${network.interface}";
  privateModules = config.homelab.microvms.${name}.guestModules or [];

  copiedSecrets = {
    mqtt-password = { source = "ha-mqtt-password"; mode = "0400"; };
    z2m-env = { source = "ha-z2m-env"; mode = "0400"; };
    prometheus-token = { source = "ha-prometheus-token"; mode = "0400"; };
    telemetry-pass = { source = "telemetry-pass"; mode = "0400"; };
    wg-iot-priv = { source = "wg-iot-priv"; mode = "0400"; };
    wg-iot-psk = { source = "wg-iot-psk"; mode = "0400"; };
    restic-ha-rest-pass = { source = "restic-ha-rest-pass"; mode = "0400"; };
    restic-ha-encryption-pass = { source = "restic-ha-encryption-pass"; mode = "0400"; };
  };

  copySecret = destination: secret: ''
    install -m ${secret.mode} ${config.age.secrets.${secret.source}.path} ${secretDir}/${destination}
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
  age.secrets = lib.genAttrs (map (secret: secret.source) (builtins.attrValues copiedSecrets)) (_: {});

  system.activationScripts.home-assistant-files = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0755 ${stateRoot}/ssh
      install -d -m 0700 ${secretDir}
      install -d -m 0755 -o root -g cert-readers ${certDir}
      rm -f ${secretDir}/restic-ha-repo
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList copySecret copiedSecrets)}
      ${copyCertificate}
    '';
  };

  systemd.services.copy-home-assistant-certificate = {
    description = "Copy the internal certificate into Home Assistant VM state";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = copyCertificate;
  };
  security.acme.certs."internal.veetik.com".reloadServices = [
    "copy-home-assistant-certificate.service"
  ];

  systemd.network.networks."60-vm-ha" = {
    matchConfig.Name = "vm-ha";
    networkConfig.Bridge = bridge;
  };

  microvm.vms.homeassistant = {
    specialArgs = {
      inherit adminKeys inventory pkgs-unstable;
    };

    config = { config, lib, pkgs, ... }: {
      imports = [
        ../../../modules/profiles/microvm.nix
        ../../../modules/services/microvm-volumes.nix
        ../../../modules/services/restic-backups.nix
        ../../../modules/services/shared-secrets.nix
        ./home-assistant.nix
        ./mqtt.nix
        ./nginx.nix
      ] ++ privateModules;

      homelab = {
        hostKey = inventoryKey;
        stateRoot = stateRoot;
        volumeSize = 4096;
        volumes = {
          mosquitto = {
            owner = "mosquitto";
            mode = "0755";
          };
          zigbee2mqtt = {
            owner = "zigbee2mqtt";
            mode = "0700";
          };
          hass = {
            owner = "hass";
            mode = "0700";
          };
        };
        backups = {
          serverUrl = "https://backup.internal.veetik.com:${toString inventory.hosts.backup.ports.restic}";
          instances = {
            hass = {
              repository = "ha";
              username = "ha";
              tag = "hass";
              restPasswordFile = "/run/secrets/restic-ha-rest-pass";
              encryptionPasswordFile = "/run/secrets/restic-ha-encryption-pass";
              paths = [ "/var/lib/hass" ];
              excludes = [
                "/var/lib/hass/home-assistant_v2.db"
                "/var/lib/hass/home-assistant_v2.db-shm"
                "/var/lib/hass/home-assistant_v2.db-wal"
              ];
              after = [ "var-lib-hass.mount" ];
              before = [ "home-assistant.service" ];
              requiredBy = [ "home-assistant.service" ];
              hasData = ''[ -n "$(ls -A /var/lib/hass 2>/dev/null)" ]'';
              restore = ''
                restic restore --tag hass latest --target / --include /var/lib/hass
                chown -R hass:hass /var/lib/hass
              '';
            };
            zigbee2mqtt = {
              repository = "ha";
              username = "ha";
              tag = "zigbee2mqtt";
              restPasswordFile = "/run/secrets/restic-ha-rest-pass";
              encryptionPasswordFile = "/run/secrets/restic-ha-encryption-pass";
              paths = [ "/var/lib/zigbee2mqtt" ];
              after = [ "var-lib-zigbee2mqtt.mount" ];
              hasData = ''[ -n "$(ls -A /var/lib/zigbee2mqtt 2>/dev/null)" ]'';
              restore = ''
                restic restore --tag zigbee2mqtt latest --target / --include /var/lib/zigbee2mqtt
                chown -R zigbee2mqtt:zigbee2mqtt /var/lib/zigbee2mqtt
              '';
            };
          };
        };
        metrics.scrapes.hass = {
          path = "/api/prometheus";
          authorizationFile = "/run/credentials/vmagent.service/prometheus-token";
          targets = [ "127.0.0.1:${toString config.homelab.ports.homeAssistant}" ];
        };
      };

      networking = {
        hostName = host.hostname;
        nameservers = [ network.router4 ];
        firewall = {
          allowedTCPPorts = [ config.homelab.ports.https ];
          allowedUDPPorts = [ config.homelab.ports.wireguard ];
        };
      };

      microvm = {
        mem = lib.mkForce 1024;
        interfaces = [{
          type = "tap";
          id = "vm-ha";
          mac = "02:00:00:14:00:01";
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
        netdevs."25-wg-iot" = {
          netdevConfig = {
            Kind = "wireguard";
            Name = "wg-iot";
          };
          wireguardConfig = {
            PrivateKeyFile = "/run/credentials/systemd-networkd.service/wg-iot-priv";
            ListenPort = config.homelab.ports.wireguard;
          };
          wireguardPeers = [{
            PublicKey = "1KioECK3czkVCkQP1l7C0EfHrVCjQvvrM/uTf2KG1SM=";
            PresharedKeyFile = "/run/credentials/systemd-networkd.service/wg-iot-psk";
            AllowedIPs = [ "10.255.20.2/32" ];
          }];
        };
        networks = {
          "10-ethernet" = {
            matchConfig.Type = "ether";
            address = [ "${host.ipv4}/${lib.last (lib.splitString "/" network.cidr4)}" ];
            routes = [{ Gateway = network.router4; }];
            networkConfig.DHCP = "no";
          };
          "25-wg-iot" = {
            matchConfig.Name = "wg-iot";
            address = [ "10.255.20.1/24" ];
            networkConfig = {
              LinkLocalAddressing = "no";
              DHCP = "no";
            };
            linkConfig.RequiredForOnline = "yes";
          };
        };
      };

      systemd.services = {
        systemd-networkd = {
          after = [ "run-secrets.mount" ];
          wants = [ "run-secrets.mount" ];
          serviceConfig.LoadCredential = [
            "wg-iot-priv:/run/secrets/wg-iot-priv"
            "wg-iot-psk:/run/secrets/wg-iot-psk"
          ];
        };
        vmagent.serviceConfig.LoadCredential = [
          "prometheus-token:/run/secrets/prometheus-token"
        ];
      };

      environment.systemPackages = [ pkgs.wireguard-tools ];
    };
  };
}
